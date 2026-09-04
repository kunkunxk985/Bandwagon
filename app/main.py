from __future__ import annotations

import asyncio
import concurrent.futures
import hashlib
import hmac
import time
from contextlib import asynccontextmanager
from pathlib import Path
from typing import Any, Optional

from fastapi import FastAPI, Request
from fastapi.responses import FileResponse, JSONResponse, RedirectResponse
from fastapi.staticfiles import StaticFiles

from . import config
from . import demo as demo_data
from .bwh import fetch_history, fetch_service, test_bwh_connection
from .util import TTLCache
from .xui import XUIClient, test_xui_connection

WEB = Path(__file__).resolve().parent.parent / "web"
cache = TTLCache()
CACHE_KEY = "overview"
COOKIE = "wagong_deck"
IDLE_AFTER = 300.0  # 超过这个秒数没有前端访问，后台轮询暂停
_last_client_hit = 0.0


def _cookie_value() -> str:
    secret = config.DASHBOARD_PASSWORD.encode("utf-8")
    digest = hmac.new(secret, b"wagong-deck", hashlib.sha256).hexdigest()
    return digest


def _authorized(request: Request) -> bool:
    if not config.DASHBOARD_PASSWORD:
        return True
    return request.cookies.get(COOKIE) == _cookie_value()


def _calculate_budget(bwh_data: dict) -> dict:
    quota = bwh_data.get("quotaBytes") or 0
    used = bwh_data.get("usedBytes") or 0
    reset_at = bwh_data.get("resetAt") or 0
    now = time.time()
    if not quota or not reset_at:
        return {"hasBudget": False}

    reset_sec = reset_at if reset_at < 1e11 else reset_at / 1000
    days_left = max(0.01, (reset_sec - now) / 86400.0)
    cycle_days = 30.0
    days_passed = max(0.01, cycle_days - days_left)
    time_percent = min(100.0, max(0.0, (days_passed / cycle_days) * 100.0))
    used_percent = min(100.0, max(0.0, (used / quota) * 100.0))
    remaining_bytes = max(0, quota - used)
    daily_budget = remaining_bytes / days_left
    current_daily_rate = used / days_passed

    if used_percent >= 90 or (days_left > 4 and daily_budget < current_daily_rate * 0.4):
        status = "urgent"
    elif used_percent > time_percent + 12:
        status = "warning"
    elif used_percent > time_percent:
        status = "moderate"
    else:
        status = "healthy"

    projected_days = (remaining_bytes / current_daily_rate) if current_daily_rate > 0 else 999.0

    return {
        "hasBudget": True,
        "daysLeft": round(days_left, 1),
        "daysPassed": round(days_passed, 1),
        "timePercent": round(time_percent, 1),
        "usedPercent": round(used_percent, 1),
        "remainingBytes": remaining_bytes,
        "dailyBudgetBytes": int(daily_budget),
        "currentDailyBytes": int(current_daily_rate),
        "status": status,
        "projectedDaysLeft": round(projected_days, 1),
    }


def _collect() -> dict:
    if config.DEMO:
        return demo_data.overview()

    fetched_at = int(time.time() * 1000)
    payload: dict[str, Any] = {
        "ok": True,
        "demo": False,
        "fetchedAt": fetched_at,
        "bwh": {
            "configured": config.BWH_CONFIGURED,
            "error": None,
        },
        "budget": {"hasBudget": False},
        "bwhHistory": [],
        "xui": {
            "configured": config.XUI_CONFIGURED,
            "error": None,
            "server": None,
            "inbounds": [],
            "clients": [],
            "onlineCount": 0,
            "clientCount": 0,
            "enabledCount": 0,
            "clientUsedBytes": 0,
        },
    }

    # 并发执行 BWH 与 XUI 数据采集任务
    def _get_bwh_service():
        if not config.BWH_CONFIGURED:
            return None
        cached = cache.get("bwh_service")
        if cached is not None or cache.get("bwh_fail") is not None:
            return cached
        try:
            res = fetch_service()
            cache.set("bwh_service", res, 30)
            return res
        except Exception as exc:
            cache.set("bwh_fail", True, 45)
            raise exc

    def _get_bwh_history():
        if not config.BWH_CONFIGURED:
            return None
        cached = cache.get("bwh_history")
        if cached is not None:
            return cached
        try:
            res = fetch_history()
            cache.set("bwh_history", res, 300)
            cache.set("bwh_history_last", res, 86400)
            return res
        except Exception as exc:
            last = cache.get("bwh_history_last")
            if last:
                return last
            raise exc

    def _get_xui_snapshot():
        if not config.XUI_CONFIGURED:
            return None
        cached = cache.get("xui")
        if cached is not None or cache.get("xui_fail") is not None:
            return cached
        client: Optional[XUIClient] = None
        try:
            client = XUIClient()
            res = client.snapshot()
            cache.set("xui", res, 15)
            return res
        except Exception as exc:
            cache.set("xui_fail", True, 45)
            raise exc
        finally:
            if client is not None:
                client.close()

    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as executor:
        f_bwh_srv = executor.submit(_get_bwh_service)
        f_bwh_his = executor.submit(_get_bwh_history)
        f_xui = executor.submit(_get_xui_snapshot)

        # 处理 BWH Service
        try:
            service = f_bwh_srv.result()
            if service:
                payload["bwh"].update(service)
                payload["bwh"]["configured"] = True
                payload["bwh"]["error"] = None
                payload["budget"] = _calculate_budget(service)
        except Exception as exc:
            payload["bwh"]["error"] = str(exc)
            payload["ok"] = False

        # 处理 BWH History
        try:
            history = f_bwh_his.result()
            payload["bwhHistory"] = history or []
        except Exception as exc:
            if not payload["bwh"].get("error"):
                payload["bwh"]["error"] = str(exc)

        # 处理 XUI Snapshot
        try:
            snapshot = f_xui.result()
            if snapshot:
                payload["xui"].update(snapshot)
                payload["xui"]["configured"] = True
                if payload["xui"].get("error") is None:
                    payload["xui"]["error"] = None
        except Exception as exc:
            payload["xui"]["error"] = str(exc)
            payload["ok"] = False

    return payload


def get_overview(force: bool = False) -> dict:
    if force:
        for key in (CACHE_KEY, "bwh_service", "bwh_history", "bwh_fail", "xui", "xui_fail"):
            cache.delete(key)
    else:
        hit = cache.get(CACHE_KEY)
        if hit is not None:
            return hit
    data = _collect()
    cache.set(CACHE_KEY, data, 15)
    return data


async def _poller() -> None:
    while True:
        try:
            idle = time.monotonic() - _last_client_hit > IDLE_AFTER
            if not idle and not config.DEMO:
                await asyncio.to_thread(get_overview, True)
        except Exception:
            pass
        await asyncio.sleep(config.REFRESH_INTERVAL or 20)


@asynccontextmanager
async def lifespan(_app: FastAPI):
    task = asyncio.create_task(_poller())
    try:
        yield
    finally:
        task.cancel()


app = FastAPI(title="Bandwagon", lifespan=lifespan)
app.mount("/assets", StaticFiles(directory=str(WEB)), name="assets")


@app.middleware("http")
async def gate(request: Request, call_next):
    global _last_client_hit
    path = request.url.path
    public = (
        path in ("/login", "/api/login", "/api/health", "/api/test-connection", "/favicon.ico")
        or path.startswith("/assets/")
    )
    if public or _authorized(request):
        if path in ("/api/overview", "/api/refresh"):
            _last_client_hit = time.monotonic()
        return await call_next(request)
    if path.startswith("/api/"):
        return JSONResponse({"error": "unauthorized"}, status_code=401)
    return RedirectResponse("/login")


@app.get("/api/health")
def api_health():
    return {
        "ok": True,
        "demo": config.DEMO,
        "bwh": config.BWH_CONFIGURED,
        "xui": config.XUI_CONFIGURED,
    }


@app.get("/api/settings")
def api_get_settings():
    return config.public_settings()


@app.post("/api/settings")
async def api_save_settings(request: Request):
    try:
        body = await request.json()
    except Exception:
        body = {}
    if not isinstance(body, dict):
        return JSONResponse({"ok": False, "error": "无效设置"}, status_code=400)
    saved = config.save_settings(body)
    data = get_overview(force=True)
    return {"ok": True, "settings": saved, "overview": data}


@app.post("/api/test-connection")
async def api_test_connection(request: Request):
    try:
        body = await request.json()
    except Exception:
        body = {}
    if not isinstance(body, dict):
        return JSONResponse({"ok": False, "error": "无效请求参数"}, status_code=400)

    target = str(body.get("target") or "").lower()
    if target == "bwh":
        veid = str(body.get("bwhVeid") or "").strip()
        key = str(body.get("bwhApiKey") or "").strip()
        base = str(body.get("bwhApiBase") or "").strip()
        res = await asyncio.to_thread(test_bwh_connection, veid=veid, api_key=key, api_base=base)
        return res
    elif target == "xui":
        url = str(body.get("xuiBaseUrl") or "").strip()
        token = str(body.get("xuiApiToken") or "").strip()
        user = str(body.get("xuiUsername") or "").strip()
        pwd = str(body.get("xuiPassword") or "").strip()
        two_factor = str(body.get("xuiTwoFactor") or "").strip()
        ssl_val = body.get("xuiVerifySsl")
        res = await asyncio.to_thread(
            test_xui_connection,
            base_url=url,
            token=token,
            username=user,
            password=pwd,
            two_factor=two_factor,
            verify_ssl=ssl_val,
        )
        return res

    return JSONResponse({"ok": False, "error": f"未知测试目标: {target}"}, status_code=400)


@app.get("/api/overview")
def api_overview():
    return get_overview()


@app.post("/api/refresh")
def api_refresh():
    return get_overview(force=True)


@app.post("/api/login")
async def api_login(request: Request):
    if not config.DASHBOARD_PASSWORD:
        return {"ok": True}
    try:
        body = await request.json()
    except Exception:
        body = {}
    password = str((body or {}).get("password") or "")
    if password != config.DASHBOARD_PASSWORD:
        return JSONResponse({"ok": False, "error": "密码不对"}, status_code=401)
    response = JSONResponse({"ok": True})
    response.set_cookie(COOKIE, _cookie_value(), httponly=True, samesite="lax", max_age=60 * 60 * 24 * 14)
    return response


@app.get("/login")
def login_page():
    return FileResponse(WEB / "login.html")


@app.get("/")
def index():
    return FileResponse(WEB / "index.html")
