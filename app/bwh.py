from __future__ import annotations

import time
from typing import Any, Dict, List, Optional

import httpx

from . import config
from .util import as_float, as_int, downsample

__all__ = ["BandwagonError", "fetch_history", "fetch_service", "parse_usage_row", "test_bwh_connection"]

_client_pool: Optional[httpx.Client] = None


def _get_client() -> httpx.Client:
    global _client_pool
    if _client_pool is None or _client_pool.is_closed:
        _client_pool = httpx.Client(
            timeout=25.0,
            follow_redirects=True,
            limits=httpx.Limits(max_keepalive_connections=5, max_connections=10, keepalive_expiry=30.0),
        )
    return _client_pool


class BandwagonError(RuntimeError):
    pass


def _call(command: str, timeout: float = 25.0, custom_veid: str = "", custom_key: str = "", custom_base: str = "") -> Dict[str, Any]:
    veid = custom_veid or config.BWH_VEID
    key = custom_key or config.BWH_API_KEY
    base = (custom_base or config.BWH_API_BASE).rstrip("/")
    if not veid or not key:
        raise BandwagonError("搬瓦工 VEID 或 API Key 未配置")
    url = f"{base}/{command}"
    client = _get_client()
    try:
        response = client.post(
            url,
            data={"veid": veid, "api_key": key},
            timeout=timeout,
        )
        response.raise_for_status()
        payload = response.json()
    except httpx.HTTPStatusError as exc:
        raise BandwagonError(f"HTTP 请求失败 ({exc.response.status_code})") from exc
    except (httpx.RequestError, ValueError) as exc:
        raise BandwagonError(f"无法连接 KiwiVM 接口: {exc}") from exc

    if as_int(payload.get("error")) != 0:
        msg = str(payload.get("message") or payload.get("error") or "KiwiVM 调用失败")
        raise BandwagonError(msg)
    return payload


def _traffic_bytes(raw: Any, multiplier: float) -> int:
    return int(as_int(raw) * (multiplier if multiplier > 0 else 1.0))


def test_bwh_connection(veid: str = "", api_key: str = "", api_base: str = "") -> dict:
    t0 = time.monotonic()
    try:
        info = _call("getServiceInfo", timeout=12.0, custom_veid=veid, custom_key=api_key, custom_base=api_base)
        latency = int((time.monotonic() - t0) * 1000)
        multiplier = as_float(info.get("monthly_data_multiplier"), 1.0) or 1.0
        used = _traffic_bytes(info.get("data_counter"), multiplier)
        quota = _traffic_bytes(info.get("plan_monthly_data"), multiplier)
        ips = info.get("ip_addresses") or []
        if not isinstance(ips, list):
            ips = [str(ips)]
        return {
            "ok": True,
            "latencyMs": latency,
            "error": None,
            "hostname": info.get("hostname") or "",
            "ip": str(ips[0]) if ips else "",
            "location": info.get("node_location") or info.get("node_location_id") or "",
            "plan": info.get("plan") or "",
            "status": info.get("ve_status") or info.get("status") or "running",
            "usedBytes": used,
            "quotaBytes": quota,
        }
    except Exception as exc:
        latency = int((time.monotonic() - t0) * 1000)
        return {
            "ok": False,
            "latencyMs": latency,
            "error": str(exc),
        }


def parse_usage_row(row: Any) -> Optional[dict]:
    if isinstance(row, dict):
        ts = as_int(row.get("timestamp") or row.get("time") or row.get("t"))
        if ts > 1_000_000_000_000:
            ts //= 1000
        if ts <= 0:
            return None
        return {
            "t": ts,
            "in": as_int(row.get("network_in_bytes") or row.get("net_in") or row.get("network_in")),
            "out": as_int(row.get("network_out_bytes") or row.get("net_out") or row.get("network_out")),
            "cpu": as_float(row.get("cpu") or row.get("cpu_usage")),
        }
    if isinstance(row, (list, tuple)) and len(row) >= 3:
        ts = as_int(row[0])
        if ts > 1_000_000_000_000:
            ts //= 1000
        # KiwiVM 二维数组常见顺序: timestamp, cpu, ..., network
        cpu = as_float(row[1])
        net_in = as_int(row[-2]) if len(row) >= 4 else 0
        net_out = as_int(row[-1]) if len(row) >= 4 else as_int(row[2])
        if ts <= 0:
            return None
        return {"t": ts, "in": net_in, "out": net_out, "cpu": cpu}
    return None


def fetch_service() -> dict:
    info = _call("getServiceInfo")
    multiplier = as_float(info.get("monthly_data_multiplier"), 1.0) or 1.0
    used = _traffic_bytes(info.get("data_counter"), multiplier)
    quota = _traffic_bytes(info.get("plan_monthly_data"), multiplier)
    ips = info.get("ip_addresses") or []
    if not isinstance(ips, list):
        ips = [str(ips)]
    reset_at = as_int(info.get("data_next_reset"))
    return {
        "hostname": info.get("hostname") or "",
        "ips": [str(ip) for ip in ips],
        "ip": str(ips[0]) if ips else "",
        "location": info.get("node_location") or info.get("node_location_id") or "",
        "node": info.get("node_alias") or "",
        "plan": info.get("plan") or "",
        "os": info.get("os") or "",
        "vmType": info.get("vm_type") or "",
        "status": info.get("ve_status") or info.get("status") or "running",
        "sshPort": as_int(info.get("ssh_port")),
        "usedBytes": used,
        "quotaBytes": quota,
        "usedPercent": round(used * 100.0 / quota, 2) if quota else 0.0,
        "resetAt": reset_at,
        "multiplier": multiplier,
        "ramBytes": as_int(info.get("plan_ram")),
        "swapBytes": as_int(info.get("plan_swap")),
        "diskBytes": as_int(info.get("plan_disk")),
        "diskUsedBytes": as_int(info.get("ve_used_disk_space_b") or info.get("used_disk_space")),
    }


def fetch_history(max_points: int = 800) -> List[dict]:
    payload = _call("getRawUsageStats", timeout=40.0)
    rows = payload.get("data") or payload.get("array") or []
    if isinstance(rows, dict):
        rows = list(rows.values())
    points = []
    for row in rows:
        parsed = parse_usage_row(row)
        if parsed:
            points.append(parsed)
    points.sort(key=lambda item: item["t"])
    return downsample(points, max_points)
