#!/usr/bin/env python3
"""Local synthetic server; never reads stored credentials or contacts a panel."""
import http.server
import json
import subprocess
import threading
import sys
import time
import urllib.parse

class Handler(http.server.BaseHTTPRequestHandler):
    mode = "success"
    login_count = 0
    def log_message(self, format, *args): pass
    def send(self, status, payload, cookie=None):
        data = payload.encode() if isinstance(payload, str) else json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Length", str(len(data)))
        if cookie: self.send_header("Set-Cookie", cookie)
        self.end_headers()
        self.wfile.write(data)
    def do_GET(self):
        if self.path.startswith("/private/panel/api/clients/get/"):
            self.handle_write()
        elif self.path == "/private/":
            self.send(200, '<meta name="csrf-token" content="fixture-csrf">', 'csrf=fixture; Path=/private/')
        elif self.path == "/private/panel/api/inbounds/list":
            if "session=authenticated" not in self.headers.get("Cookie", ""):
                self.send(401, {})
            elif self.mode == "403": self.send(403, "")
            elif self.mode == "invalid": self.send(200, {"success": True, "obj": {"unexpected": []}})
            else:
                self.send(200, {"success": True, "obj": [{"remark": "fixture", "protocol": "vless", "settings": json.dumps({"clients": [{"email": "fixture", "id": "uuid-1", "subId": "sub-fixture", "flow": "xtls-rprx-vision", "enable": True, "totalGB": 0, "expiryTime": 0}]}), "clientStats": [{"email": "fixture", "up": 2, "down": 3}]}]})
        else: self.send(404, "")
    def do_POST(self):
        if self.path.startswith("/bwh/"):
            if self.mode == "bwh-auth":
                self.send(200, {"error": 1, "message": "Invalid API credentials"})
            else:
                time.sleep(2)
                self.send(500, {})
            return
        if self.path == "/private/login":
            Handler.login_count += 1
            raw = self.rfile.read(int(self.headers.get("Content-Length", 0)))
            content_type = self.headers.get("Content-Type", "").lower()
            if content_type.startswith("application/x-www-form-urlencoded"):
                parsed = urllib.parse.parse_qs(raw.decode(), keep_blank_values=True)
                body = {key: values[-1] for key, values in parsed.items()}
            else:
                body = json.loads(raw)
            valid = (
                self.headers.get("X-CSRF-Token") == "fixture-csrf"
                and self.headers.get("X-Requested-With") == "XMLHttpRequest"
                and "csrf=fixture" in self.headers.get("Cookie", "")
                and body == {"username": "fixture", "password": "p&+= fixture", "twoFactorCode": "123456"}
            )
            if not valid: self.send(403, "")
            elif self.mode == "auth": self.send(200, {"success": False, "msg": "fixture rejected"})
            elif self.mode == "unauthorized": self.send(401, {})
            else: self.send(200, {"success": True}, 'session=authenticated; Path=/private/')
        elif self.path.startswith("/private/panel/api/clients/") and not self.path.endswith("/onlines") \
                or self.path == "/private/panel/api/setting/defaultSettings":
            self.handle_write()
        elif self.path.endswith("/onlines"):
            if self.headers.get("X-CSRF-Token") != "fixture-csrf": self.send(403, "")
            else: self.send(200, {"success": True, "obj": ["fixture"]})
        elif self.mode == "403": self.send(403, "")
        else: self.send(404, "")

RECORD = {
    "id": 12, "email": "fixture", "uuid": "uuid-1", "subId": "sub-fixture",
    "password": "", "auth": "", "flow": "xtls-rprx-vision", "security": "auto",
    "reverse": json.dumps({"tag": "r1"}), "privateKey": "", "publicKey": "",
    "allowedIPs": "", "preSharedKey": "", "keepAlive": 0, "forwardedPorts": "",
    "secret": "", "adTag": "", "limitIp": 2, "limitHwid": 1, "totalGB": 0,
    "expiryTime": 0, "enable": True, "tgId": 0, "group": "g", "comment": "c",
    "reset": 0, "resetDay": 0, "resetWeekday": 0, "resetMax": 0,
    "trafficReset": "never", "trafficResetDay": 1, "createdAt": 1, "updatedAt": 2,
}

# What the panel's own ClientRecord.ToClient produces from RECORD, plus the edit.
EXPECTED_UPDATE = {
    "id": "uuid-1", "email": "fixture", "subId": "sub-fixture", "password": "",
    "auth": "", "flow": "xtls-rprx-vision", "security": "auto", "reverse": {"tag": "r1"},
    "privateKey": "", "publicKey": "", "preSharedKey": "", "forwardedPorts": "",
    "secret": "", "adTag": "", "limitIp": 2, "limitHwid": 1,
    "totalGB": 53687091200, "expiryTime": 1893456000000, "enable": True, "tgId": 0,
    "group": "g", "comment": "c", "reset": 0, "resetDay": 0, "resetWeekday": 0,
    "resetMax": 0, "trafficReset": "never", "trafficResetDay": 1,
}

def _write_ok(self):
    return (
        "session=authenticated" in self.headers.get("Cookie", "")
        and self.headers.get("X-CSRF-Token") == "fixture-csrf"
    )

def handle_write(self):
    raw = self.rfile.read(int(self.headers.get("Content-Length", 0) or 0))
    if not self._write_ok():
        self.send(401, {}); return
    path = self.path
    if self.command == "GET" and path == "/private/panel/api/clients/get/fixture":
        self.send(200, {"success": True, "obj": {"client": RECORD, "inboundIds": [7]}}); return
    if path == "/private/panel/api/setting/defaultSettings":
        self.send(200, {"success": True, "obj": {"subEnable": True, "subURI": "https://sub.example/sub/", "subClashEnable": True, "subClashURI": "https://sub.example/clash/", "subJsonEnable": False, "subJsonURI": ""}}); return
    if path == "/private/panel/api/clients/resetTraffic/fixture":
        self.send(200, {"success": True, "obj": None}); return
    if path in ("/private/panel/api/clients/bulkDisable", "/private/panel/api/clients/bulkEnable"):
        if json.loads(raw or b"{}") != {"emails": ["fixture"]}:
            self.send(200, {"success": False, "msg": "unexpected bulk body"}); return
        if self.mode == "write-reject":
            self.send(200, {"success": True, "obj": {"changed": 0, "skipped": [{"email": "fixture", "reason": "fixture refused"}]}})
        else:
            self.send(200, {"success": True, "obj": {"changed": 1}})
        return
    if path == "/private/panel/api/clients/update/fixture":
        ok = self.headers.get("Content-Type", "").startswith("application/json") and json.loads(raw or b"{}") == EXPECTED_UPDATE
        if ok:
            self.send(200, {"success": True, "obj": None})
        else:
            self.send(200, {"success": False, "msg": "unexpected payload " + raw.decode()})
        return
    self.send(404, "")

Handler._write_ok = _write_ok
Handler.handle_write = handle_write

server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
threading.Thread(target=server.serve_forever, daemon=True).start()
try:
    for mode, expected in [
        ("success", "success"),
        ("403", "403"),
        ("auth", "HTTP 200"),
        ("invalid", "无法识别"),
        ("auth", "routing-auth"),
        ("unauthorized", "routing-401"),
        ("bwh-auth", "bwh-routing"),
        ("success", "concurrency"),
        ("success", "writes"),
        ("write-reject", "write-reject"),
    ]:
        Handler.mode = mode
        Handler.login_count = 0
        result = subprocess.run([sys.argv[1], str(server.server_port), expected])
        if result.returncode: sys.exit(result.returncode)
        expected_login_count = {"bwh-routing": 0, "writes": 5, "write-reject": 2}.get(expected, 1)
        assert Handler.login_count == expected_login_count, "duplicate login detected"
    print("PASS exactly one login per refresh (including concurrent callers)")
finally: server.shutdown()
