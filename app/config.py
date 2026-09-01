from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Any, Dict

from dotenv import load_dotenv

ROOT = Path(__file__).resolve().parent.parent
load_dotenv(ROOT / ".env")

SETTINGS_DIR = Path.home() / "Library/Application Support/WagongDeck"
SETTINGS_FILE = SETTINGS_DIR / "settings.json"

STRING_KEYS = (
    "BWH_VEID",
    "BWH_API_KEY",
    "BWH_API_BASE",
    "XUI_BASE_URL",
    "XUI_API_TOKEN",
    "XUI_USERNAME",
    "XUI_PASSWORD",
    "XUI_TWO_FACTOR",
    "DASHBOARD_PASSWORD",
    "HOST",
    "PORT",
    "REFRESH_INTERVAL",
    "THEME",
)
BOOL_KEYS = ("XUI_VERIFY_SSL", "DEMO")
SECRET_KEYS = {"BWH_API_KEY", "XUI_API_TOKEN", "XUI_PASSWORD", "DASHBOARD_PASSWORD", "XUI_TWO_FACTOR"}

BWH_VEID = ""
BWH_API_KEY = ""
BWH_API_BASE = "https://api.64clouds.com/v1"
XUI_BASE_URL = ""
XUI_API_TOKEN = ""
XUI_USERNAME = ""
XUI_PASSWORD = ""
XUI_VERIFY_SSL = True
XUI_TWO_FACTOR = ""
DASHBOARD_PASSWORD = ""
FORCE_DEMO = False
HOST = "127.0.0.1"
PORT = 8787
REFRESH_INTERVAL = 20
THEME = "dark"
BWH_CONFIGURED = False
XUI_CONFIGURED = False
DEMO = True


def _as_bool(value: Any, default: bool = False) -> bool:
    if value is None or value == "":
        return default
    if isinstance(value, bool):
        return value
    return str(value).strip().lower() in ("1", "true", "yes", "on")


def _read_file() -> Dict[str, Any]:
    if not SETTINGS_FILE.exists():
        return {}
    try:
        data = json.loads(SETTINGS_FILE.read_text(encoding="utf-8"))
        return data if isinstance(data, dict) else {}
    except (OSError, json.JSONDecodeError):
        return {}


def _merged() -> Dict[str, Any]:
    data: Dict[str, Any] = {
        "BWH_VEID": "",
        "BWH_API_KEY": "",
        "BWH_API_BASE": "https://api.64clouds.com/v1",
        "XUI_BASE_URL": "",
        "XUI_API_TOKEN": "",
        "XUI_USERNAME": "",
        "XUI_PASSWORD": "",
        "XUI_TWO_FACTOR": "",
        "DASHBOARD_PASSWORD": "",
        "HOST": "127.0.0.1",
        "PORT": "8787",
        "REFRESH_INTERVAL": "20",
        "THEME": "dark",
        "XUI_VERIFY_SSL": True,
        "DEMO": False,
    }
    for key in STRING_KEYS:
        env = os.getenv(key)
        if env is not None and str(env).strip() != "":
            data[key] = env.strip()
    for key in BOOL_KEYS:
        if os.getenv(key) is not None:
            data[key] = _as_bool(os.getenv(key), bool(data[key]))
    data.update(_read_file())
    return data


def reload() -> None:
    global BWH_VEID, BWH_API_KEY, BWH_API_BASE
    global XUI_BASE_URL, XUI_API_TOKEN, XUI_USERNAME, XUI_PASSWORD
    global XUI_VERIFY_SSL, XUI_TWO_FACTOR, DASHBOARD_PASSWORD, FORCE_DEMO
    global HOST, PORT, REFRESH_INTERVAL, THEME, BWH_CONFIGURED, XUI_CONFIGURED, DEMO

    data = _merged()
    BWH_VEID = str(data.get("BWH_VEID") or "").strip()
    BWH_API_KEY = str(data.get("BWH_API_KEY") or "").strip()
    BWH_API_BASE = str(data.get("BWH_API_BASE") or "https://api.64clouds.com/v1").strip().rstrip("/")
    XUI_BASE_URL = str(data.get("XUI_BASE_URL") or "").strip().rstrip("/")
    XUI_API_TOKEN = str(data.get("XUI_API_TOKEN") or "").strip()
    XUI_USERNAME = str(data.get("XUI_USERNAME") or "").strip()
    XUI_PASSWORD = str(data.get("XUI_PASSWORD") or "").strip()
    XUI_TWO_FACTOR = str(data.get("XUI_TWO_FACTOR") or "").strip()
    DASHBOARD_PASSWORD = str(data.get("DASHBOARD_PASSWORD") or "").strip()
    FORCE_DEMO = _as_bool(data.get("DEMO"), False)
    HOST = str(data.get("HOST") or "127.0.0.1").strip()
    try:
        PORT = int(str(data.get("PORT") or "8787"))
    except ValueError:
        PORT = 8787
    try:
        REFRESH_INTERVAL = max(5, int(str(data.get("REFRESH_INTERVAL") or "20")))
    except ValueError:
        REFRESH_INTERVAL = 20
    THEME = str(data.get("THEME") or "dark").strip()

    XUI_VERIFY_SSL = _as_bool(data.get("XUI_VERIFY_SSL"), True)
    BWH_CONFIGURED = bool(BWH_VEID and BWH_API_KEY)
    XUI_CONFIGURED = bool(XUI_BASE_URL and (XUI_API_TOKEN or (XUI_USERNAME and XUI_PASSWORD)))
    DEMO = FORCE_DEMO or not (BWH_CONFIGURED or XUI_CONFIGURED)


def public_settings() -> Dict[str, Any]:
    return {
        "bwhVeid": BWH_VEID,
        "bwhApiKeySet": bool(BWH_API_KEY),
        "bwhApiBase": BWH_API_BASE,
        "xuiBaseUrl": XUI_BASE_URL,
        "xuiApiTokenSet": bool(XUI_API_TOKEN),
        "xuiUsername": XUI_USERNAME,
        "xuiPasswordSet": bool(XUI_PASSWORD),
        "xuiVerifySsl": XUI_VERIFY_SSL,
        "xuiTwoFactorSet": bool(XUI_TWO_FACTOR),
        "refreshInterval": REFRESH_INTERVAL,
        "theme": THEME,
        "settingsPath": str(SETTINGS_FILE),
        "demo": DEMO,
        "bwhConfigured": BWH_CONFIGURED,
        "xuiConfigured": XUI_CONFIGURED,
    }


def save_settings(incoming: Dict[str, Any]) -> Dict[str, Any]:
    current = _read_file()
    mapping = {
        "bwhVeid": "BWH_VEID",
        "bwhApiKey": "BWH_API_KEY",
        "bwhApiBase": "BWH_API_BASE",
        "xuiBaseUrl": "XUI_BASE_URL",
        "xuiApiToken": "XUI_API_TOKEN",
        "xuiUsername": "XUI_USERNAME",
        "xuiPassword": "XUI_PASSWORD",
        "xuiTwoFactor": "XUI_TWO_FACTOR",
        "xuiVerifySsl": "XUI_VERIFY_SSL",
        "refreshInterval": "REFRESH_INTERVAL",
        "theme": "THEME",
    }
    for field, key in mapping.items():
        if field not in incoming:
            continue
        value = incoming[field]
        # 密钥字段：显式传空字符串 = 清除；不传或 None = 保持不变
        if key in SECRET_KEYS and value is None:
            continue
        if key == "XUI_VERIFY_SSL":
            current[key] = _as_bool(value, True)
        else:
            current[key] = str(value).strip() if value is not None else ""
    SETTINGS_DIR.mkdir(parents=True, exist_ok=True)
    try:
        SETTINGS_DIR.chmod(0o700)
    except OSError:
        pass
    SETTINGS_FILE.write_text(json.dumps(current, ensure_ascii=False, indent=2), encoding="utf-8")
    try:
        SETTINGS_FILE.chmod(0o600)
    except OSError:
        pass
    reload()
    return public_settings()


reload()
