from __future__ import annotations

import time
from typing import Any, Dict, List, Optional, Set

import httpx

from . import config
from .util import as_int, maybe_json

__all__ = ["XUIError", "XUIClient", "test_xui_connection"]


class XUIError(RuntimeError):
    pass


class XUIClient:
    def __init__(
        self,
        base_url: str = "",
        token: str = "",
        username: str = "",
        password: str = "",
        two_factor: str = "",
        verify_ssl: Optional[bool] = None,
    ) -> None:
        self.base = (base_url or config.XUI_BASE_URL).rstrip("/")
        self.token = token if token != "" else config.XUI_API_TOKEN
        self.username = username if username != "" else config.XUI_USERNAME
        self.password = password if password != "" else config.XUI_PASSWORD
        self.two_factor = two_factor if two_factor != "" else config.XUI_TWO_FACTOR
        self.verify_ssl = config.XUI_VERIFY_SSL if verify_ssl is None else verify_ssl
        self.last_error = ""
        self._csrf = ""
        self._client = httpx.Client(
            timeout=20.0,
            verify=self.verify_ssl,
            follow_redirects=True,
            headers={"Accept": "application/json"},
            limits=httpx.Limits(max_keepalive_connections=5, max_connections=10, keepalive_expiry=30.0),
        )
        self._logged_in = bool(self.token)

    def close(self) -> None:
        if not self._client.is_closed:
            self._client.close()

    def _headers(self) -> dict:
        headers = {"Accept": "application/json"}
        if self.token:
            headers["Authorization"] = f"Bearer {self.token}"
        if self._csrf:
            headers["X-CSRF-Token"] = self._csrf
        return headers

    def _ensure_csrf(self) -> None:
        if self._csrf or not self.base:
            return
        for path in ("/csrf-token", "/panel/csrf-token"):
            try:
                response = self._client.get(f"{self.base}{path}", timeout=8.0)
                if response.status_code == 200:
                    body = response.json()
                    if isinstance(body, dict) and body.get("obj"):
                        self._csrf = str(body["obj"])
                        return
            except Exception:
                continue

    def login(self) -> None:
        if self.token:
            self._logged_in = True
            return
        if not self.base:
            raise XUIError("3X-UI 面板地址未配置")
        if not self.username or not self.password:
            raise XUIError("未配置 3X-UI Token 或账号密码")

        self._csrf = ""
        self._ensure_csrf()
        payload: Dict[str, Any] = {
            "username": self.username,
            "password": self.password,
        }
        if self.two_factor:
            payload["twoFactorCode"] = self.two_factor
            payload["twoFactor"] = self.two_factor

        last_error = "登录失败"
        for login_path in ("/login", "/panel/login"):
            try:
                self._client.get(f"{self.base}{login_path}", timeout=6.0)
            except Exception:
                pass
            for kwargs in ({"data": payload}, {"json": payload}):
                try:
                    response = self._client.post(
                        f"{self.base}{login_path}",
                        headers=self._headers(),
                        timeout=12.0,
                        **kwargs,
                    )
                except httpx.ConnectError as exc:
                    raise XUIError(f"无法连接到面板 ({self.base}): 拒绝连接或网络不可达") from exc
                except httpx.ConnectTimeout as exc:
                    raise XUIError(f"连接面板超时 ({self.base})") from exc
                except httpx.HTTPError as exc:
                    last_error = str(exc)
                    continue

                if response.status_code == 403 and not response.content:
                    last_error = "面板拒绝登录 (HTTP 403，可能触发了登录限流，请稍后再试)"
                    continue
                try:
                    body = response.json()
                except ValueError:
                    if response.status_code == 404:
                        continue
                    last_error = f"登录返回非 JSON (HTTP {response.status_code})，请核对面板路径"
                    continue
                if body.get("success"):
                    self._logged_in = True
                    return
                last_error = str(body.get("msg") or last_error)

        raise XUIError(last_error)

    def _request(self, method: str, path: str, **kwargs) -> Any:
        if not self._logged_in:
            self.login()
        url = f"{self.base}{path}"
        kwargs.setdefault("headers", self._headers())
        try:
            response = self._client.request(method, url, timeout=kwargs.pop("timeout", 15.0), **kwargs)
        except httpx.RequestError as exc:
            self.last_error = f"请求失败: {exc}"
            raise XUIError(self.last_error) from exc

        if response.status_code in (401, 403) and not self.token:
            self._logged_in = False
            self.login()
            kwargs["headers"] = self._headers()
            response = self._client.request(method, url, **kwargs)

        if response.status_code in (401, 403):
            self.last_error = f"{path} 认证被拒 (HTTP {response.status_code})"
            raise XUIError(self.last_error)

        response.raise_for_status()
        try:
            body = response.json()
        except ValueError as exc:
            raise XUIError(f"{path} 返回非 JSON 数据") from exc
        if isinstance(body, dict) and body.get("success") is False:
            raise XUIError(str(body.get("msg") or f"{path} 失败"))
        if isinstance(body, dict) and "obj" in body:
            return body.get("obj")
        return body

    def try_request(self, method: str, path: str, **kwargs) -> Any:
        try:
            return self._request(method, path, **kwargs)
        except (XUIError, httpx.HTTPError) as exc:
            self.last_error = str(exc)
            return None

    def server_status(self) -> Optional[dict]:
        obj = self.try_request("GET", "/panel/api/server/status")
        if obj is None:
            obj = self.try_request("POST", "/server/status")
        if obj is None:
            obj = self.try_request("GET", "/server/status")
        if not isinstance(obj, dict):
            return None
        mem = obj.get("mem") or {}
        disk = obj.get("disk") or {}
        swap = obj.get("swap") or {}
        xray = obj.get("xray") or {}
        net_io = obj.get("netIO") or obj.get("net_io") or {}
        net_traffic = obj.get("netTraffic") or obj.get("net_traffic") or {}
        loads = obj.get("loads") or [0, 0, 0]
        return {
            "cpu": obj.get("cpu") or 0,
            "cpuCores": obj.get("cpuCores") or obj.get("cpu_cores") or 0,
            "memUsed": as_int(mem.get("current")),
            "memTotal": as_int(mem.get("total")),
            "swapUsed": as_int(swap.get("current")),
            "swapTotal": as_int(swap.get("total")),
            "diskUsed": as_int(disk.get("current")),
            "diskTotal": as_int(disk.get("total")),
            "xray": xray.get("state") or "",
            "xrayVersion": xray.get("version") or "",
            "xrayError": xray.get("errorMsg") or "",
            "uptime": as_int(obj.get("uptime")),
            "load1": loads[0] if len(loads) > 0 else 0,
            "load5": loads[1] if len(loads) > 1 else 0,
            "load15": loads[2] if len(loads) > 2 else 0,
            "tcp": as_int(obj.get("tcpCount") or obj.get("tcp_count")),
            "udp": as_int(obj.get("udpCount") or obj.get("udp_count")),
            "netIoUp": as_int(net_io.get("up")),
            "netIoDown": as_int(net_io.get("down")),
            "netSent": as_int(net_traffic.get("sent")),
            "netRecv": as_int(net_traffic.get("recv")),
        }

    def online_emails(self) -> Set[str]:
        # v3 是 /clients/onlines，v2 是 /inbounds/onlines
        obj = self.try_request("POST", "/panel/api/clients/onlines")
        if obj is None:
            obj = self.try_request("POST", "/panel/api/inbounds/onlines")
        if obj is None:
            obj = self.try_request("GET", "/panel/api/inbounds/onlines")
        if obj is None:
            obj = self.try_request("GET", "/panel/api/clients/onlines")
        emails: Set[str] = set()
        if isinstance(obj, list):
            for item in obj:
                if isinstance(item, str):
                    emails.add(item)
                elif isinstance(item, dict) and item.get("email"):
                    emails.add(str(item["email"]))
        return emails

    def _normalize_expiry(self, exp_val: Any) -> int:
        val = as_int(exp_val)
        if val <= 0:
            return 0
        # 如果是秒级时间戳 (小于 10^11)，转为毫秒
        if val < 100_000_000_000:
            return val * 1000
        return val

    def _clients_from_inbounds(self, inbounds: List[dict], online: Set[str]):
        clients: List[dict] = []
        inbound_rows = []
        for inbound in inbounds:
            settings = maybe_json(inbound.get("settings")) or {}
            meta_by_email = {}
            raw_clients = settings.get("clients") if isinstance(settings, dict) else None
            if isinstance(raw_clients, list):
                for item in raw_clients:
                    if not isinstance(item, dict):
                        continue
                    email = str(item.get("email") or "")
                    if email:
                        meta_by_email[email] = item
            stats = inbound.get("clientStats") or inbound.get("client_stats") or []
            inbound_id = inbound.get("id")
            remark = inbound.get("remark") or ""
            protocol = inbound.get("protocol") or ""
            inbound_rows.append(
                {
                    "id": inbound_id,
                    "remark": remark,
                    "protocol": protocol,
                    "port": inbound.get("port"),
                    "enable": bool(inbound.get("enable", True)),
                    "up": as_int(inbound.get("up")),
                    "down": as_int(inbound.get("down")),
                    "total": as_int(inbound.get("total")),
                    "clientCount": len(stats) if isinstance(stats, list) else (len(raw_clients) if isinstance(raw_clients, list) else 0),
                }
            )
            if not isinstance(stats, list):
                continue
            for stat in stats:
                if not isinstance(stat, dict):
                    continue
                email = str(stat.get("email") or "")
                meta = meta_by_email.get(email) or {}
                up = as_int(stat.get("up"))
                down = as_int(stat.get("down"))
                total = as_int(stat.get("total"))
                if not total and meta.get("totalGB"):
                    total = as_int(meta.get("totalGB")) * (1024 ** 3)
                used = up + down
                exp = self._normalize_expiry(stat.get("expiryTime") or meta.get("expiryTime"))
                last_online = as_int(stat.get("lastOnline") or stat.get("last_online"))
                if last_online > 0 and last_online < 100_000_000_000:
                    last_online *= 1000
                clients.append(
                    {
                        "email": email,
                        "comment": meta.get("comment") or email,
                        "inboundId": inbound_id,
                        "inbound": remark or f"#{inbound_id}",
                        "protocol": protocol,
                        "up": up,
                        "down": down,
                        "used": used,
                        "total": total,
                        "allTime": as_int(stat.get("allTime") or stat.get("all_time")),
                        "percent": round(used * 100.0 / total, 2) if total else None,
                        "enable": bool(stat.get("enable", meta.get("enable", True))),
                        "expiryTime": exp,
                        "lastOnline": last_online,
                        "online": email in online,
                    }
                )
        return inbound_rows, clients

    def snapshot(self) -> dict:
        inbounds_obj = self.try_request("GET", "/panel/api/inbounds/list")
        if inbounds_obj is None:
            inbounds_obj = self.try_request("POST", "/panel/api/inbounds/list")
        if inbounds_obj is None:
            raise XUIError(self.last_error or "无法连接 3X-UI 面板，请检查地址与凭证")
        inbounds = inbounds_obj if isinstance(inbounds_obj, list) else []
        online = self.online_emails()
        inbound_rows, clients = self._clients_from_inbounds(inbounds, online)

        if not clients:
            modern = self.try_request("GET", "/panel/api/clients/")
            rows = None
            if isinstance(modern, list):
                rows = modern
            elif isinstance(modern, dict):
                rows = modern.get("clients") or modern.get("list") or modern.get("items")
            if isinstance(rows, list):
                for item in rows:
                    if not isinstance(item, dict):
                        continue
                    client = item.get("client") if isinstance(item.get("client"), dict) else item
                    email = str(client.get("email") or "")
                    up = as_int(client.get("up"))
                    down = as_int(client.get("down"))
                    total = as_int(client.get("total"))
                    used = up + down
                    inbound_ids = item.get("inboundIds") or client.get("inboundIds") or []
                    exp = self._normalize_expiry(client.get("expiryTime"))
                    last_online = as_int(client.get("lastOnline"))
                    if last_online > 0 and last_online < 100_000_000_000:
                        last_online *= 1000
                    clients.append(
                        {
                            "email": email,
                            "comment": client.get("comment") or email,
                            "inboundId": inbound_ids[0] if inbound_ids else None,
                            "inbound": "",
                            "protocol": "",
                            "up": up,
                            "down": down,
                            "used": used,
                            "total": total,
                            "allTime": as_int(client.get("allTime")),
                            "percent": round(used * 100.0 / total, 2) if total else None,
                            "enable": bool(client.get("enable", True)),
                            "expiryTime": exp,
                            "lastOnline": last_online,
                            "online": email in online,
                        }
                    )

        clients.sort(key=lambda row: row["used"], reverse=True)
        total_used = sum(row["used"] for row in clients)
        return {
            "server": self.server_status(),
            "inbounds": inbound_rows,
            "clients": clients,
            "onlineCount": sum(1 for row in clients if row["online"]),
            "clientCount": len(clients),
            "enabledCount": sum(1 for row in clients if row["enable"]),
            "clientUsedBytes": total_used,
        }


def test_xui_connection(
    base_url: str = "",
    token: str = "",
    username: str = "",
    password: str = "",
    two_factor: str = "",
    verify_ssl: Optional[bool] = None,
) -> dict:
    t0 = time.monotonic()
    client: Optional[XUIClient] = None
    try:
        client = XUIClient(
            base_url=base_url,
            token=token,
            username=username,
            password=password,
            two_factor=two_factor,
            verify_ssl=verify_ssl,
        )
        snap = client.snapshot()
        latency = int((time.monotonic() - t0) * 1000)
        server = snap.get("server") or {}
        return {
            "ok": True,
            "latencyMs": latency,
            "error": None,
            "xray": server.get("xray") or "ok",
            "xrayVersion": server.get("xrayVersion") or "",
            "inboundsCount": len(snap.get("inbounds") or []),
            "clientsCount": snap.get("clientCount") or 0,
            "onlineCount": snap.get("onlineCount") or 0,
        }
    except Exception as exc:
        latency = int((time.monotonic() - t0) * 1000)
        return {
            "ok": False,
            "latencyMs": latency,
            "error": str(exc),
        }
    finally:
        if client is not None:
            client.close()

