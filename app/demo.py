from __future__ import annotations

import time
from typing import List


def _now() -> int:
    return int(time.time())


def history() -> List[dict]:
    end = _now()
    points = []
    for i in range(72, -1, -1):
        ts = end - i * 3600
        wave = 1 + (i % 12) / 12
        points.append(
            {
                "t": ts,
                "in": int(18_000_000 * wave + (i % 7) * 2_000_000),
                "out": int(42_000_000 * wave + (i % 5) * 3_000_000),
                "cpu": round(8 + (i % 9) * 1.4, 1),
            }
        )
    return points


def overview() -> dict:
    reset_at = _now() + 11 * 86400
    quota = 1_099_511_627_776  # 1 TB
    used = 412_316_860_416
    clients = [
        {
            "email": "alice",
            "comment": "手机",
            "inboundId": 1,
            "inbound": "VLESS-Reality",
            "protocol": "vless",
            "up": 8_589_934_592,
            "down": 96_368_017_408,
            "used": 104_957_952_000,
            "total": 161_061_273_600,
            "allTime": 220_000_000_000,
            "percent": 65.17,
            "enable": True,
            "expiryTime": ( _now() + 20 * 86400 ) * 1000,
            "lastOnline": (_now() - 80) * 1000,
            "online": True,
        },
        {
            "email": "bob",
            "comment": "电脑",
            "inboundId": 1,
            "inbound": "VLESS-Reality",
            "protocol": "vless",
            "up": 3_221_225_472,
            "down": 58_720_026_624,
            "used": 61_941_252_096,
            "total": 107_374_182_400,
            "allTime": 90_000_000_000,
            "percent": 57.69,
            "enable": True,
            "expiryTime": 0,
            "lastOnline": (_now() - 3600) * 1000,
            "online": False,
        },
        {
            "email": "carol",
            "comment": "平板",
            "inboundId": 2,
            "inbound": "Hysteria2",
            "protocol": "hysteria2",
            "up": 1_073_741_824,
            "down": 36_700_000_000,
            "used": 37_773_741_824,
            "total": 53_687_091_200,
            "allTime": 40_000_000_000,
            "percent": 70.36,
            "enable": True,
            "expiryTime": (_now() + 3 * 86400) * 1000,
            "lastOnline": (_now() - 12) * 1000,
            "online": True,
        },
        {
            "email": "dave",
            "comment": "备用",
            "inboundId": 2,
            "inbound": "Hysteria2",
            "protocol": "hysteria2",
            "up": 210_000_000,
            "down": 1_800_000_000,
            "used": 2_010_000_000,
            "total": 0,
            "allTime": 12_000_000_000,
            "percent": None,
            "enable": True,
            "expiryTime": 0,
            "lastOnline": (_now() - 86400 * 4) * 1000,
            "online": False,
        },
        {
            "email": "erin",
            "comment": "已到期",
            "inboundId": 1,
            "inbound": "VLESS-Reality",
            "protocol": "vless",
            "up": 500_000_000,
            "down": 9_000_000_000,
            "used": 9_500_000_000,
            "total": 10_737_418_240,
            "allTime": 9_500_000_000,
            "percent": 88.48,
            "enable": False,
            "expiryTime": (_now() - 2 * 86400) * 1000,
            "lastOnline": (_now() - 86400 * 6) * 1000,
            "online": False,
        },
    ]
    return {
        "ok": True,
        "demo": True,
        "fetchedAt": int(time.time() * 1000),
        "bwh": {
            "configured": False,
            "error": None,
            "hostname": "demo.kiwivm.example",
            "ips": ["198.51.100.23"],
            "ip": "198.51.100.23",
            "location": "US, California",
            "node": "Node-LAX-12",
            "plan": "KVM-2G-1T",
            "os": "ubuntu-22.04-x86_64",
            "vmType": "kvm",
            "status": "running",
            "usedBytes": used,
            "quotaBytes": quota,
            "usedPercent": round(used * 100.0 / quota, 2),
            "resetAt": reset_at,
            "multiplier": 1.0,
            "ramBytes": 2_147_483_648,
            "swapBytes": 1_073_741_824,
            "diskBytes": 42_949_672_960,
            "diskUsedBytes": 12_884_901_888,
        },
        "budget": {
            "hasBudget": True,
            "daysLeft": 11.0,
            "daysPassed": 19.0,
            "timePercent": 63.3,
            "usedPercent": round(used * 100.0 / quota, 1),
            "remainingBytes": quota - used,
            "dailyBudgetBytes": int((quota - used) / 11.0),
            "currentDailyBytes": int(used / 19.0),
            "status": "healthy",
            "projectedDaysLeft": round((quota - used) / (used / 19.0), 1),
        },
        "bwhHistory": history(),
        "xui": {
            "configured": False,
            "error": None,
            "server": {
                "cpu": 14.6,
                "cpuCores": 2,
                "memUsed": 1_180_000_000,
                "memTotal": 2_147_483_648,
                "swapUsed": 0,
                "swapTotal": 1_073_741_824,
                "diskUsed": 12_884_901_888,
                "diskTotal": 42_949_672_960,
                "xray": "running",
                "xrayVersion": "25.3.6",
                "xrayError": "",
                "uptime": 86400 * 18 + 3600 * 4,
                "load1": 0.21,
                "load5": 0.18,
                "load15": 0.12,
                "tcp": 86,
                "udp": 14,
                "netIoUp": 2_400_000,
                "netIoDown": 8_100_000,
                "netSent": 80_000_000_000,
                "netRecv": 310_000_000_000,
            },
            "inbounds": [
                {
                    "id": 1,
                    "remark": "VLESS-Reality",
                    "protocol": "vless",
                    "port": 443,
                    "enable": True,
                    "up": 12_311_160_064,
                    "down": 164_088_044_032,
                    "total": 0,
                    "clientCount": 3,
                },
                {
                    "id": 2,
                    "remark": "Hysteria2",
                    "protocol": "hysteria2",
                    "port": 8443,
                    "enable": True,
                    "up": 1_283_741_824,
                    "down": 38_500_000_000,
                    "total": 0,
                    "clientCount": 2,
                },
            ],
            "clients": clients,
            "onlineCount": 2,
            "clientCount": 5,
            "enabledCount": 4,
            "clientUsedBytes": sum(c["used"] for c in clients),
        },
    }
