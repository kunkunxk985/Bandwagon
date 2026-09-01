from __future__ import annotations

import socket
import sys
import threading
import time

import uvicorn

from .main import app


def _free_port() -> int:
    sock = socket.socket()
    sock.bind(("127.0.0.1", 0))
    port = sock.getsockname()[1]
    sock.close()
    return port


def _main_screen_size() -> tuple[int, int]:
    try:
        from AppKit import NSScreen

        frame = NSScreen.mainScreen().frame()
        return int(frame.size.width), int(frame.size.height)
    except Exception:
        return (0, 0)


def main() -> None:
    try:
        import webview
    except ImportError:
        print("缺少 pywebview。请在项目目录执行：")
        print("  .venv/bin/pip install pywebview")
        sys.exit(1)

    port = _free_port()
    config = uvicorn.Config(
        app,
        host="127.0.0.1",
        port=port,
        log_level="warning",
        access_log=False,
    )
    server = uvicorn.Server(config)
    thread = threading.Thread(target=server.run, daemon=True)
    thread.start()
    deadline = time.time() + 8
    while not server.started:
        if time.time() > deadline:
            print("本地服务启动超时")
            sys.exit(1)
        time.sleep(0.05)

    window = webview.create_window(
        "瓦工台",
        f"http://127.0.0.1:{port}/",
        width=1440,
        height=880,
        min_size=(960, 600),
        background_color="#090c11",
        text_select=True,
    )

    def refresh():
        window.evaluate_js("typeof load === 'function' && load(true)")

    def settings():
        window.evaluate_js("typeof openSettings === 'function' && openSettings()")

    menu = None
    try:
        from webview.menu import Menu, MenuAction, MenuSeparator

        menu = [
            Menu(
                "瓦工台",
                [
                    MenuAction("刷新 (Cmd+R)", refresh),
                    MenuAction("偏好设置… (Cmd+,)", settings),
                    MenuSeparator(),
                    MenuAction("退出", window.destroy),
                ],
            )
        ]
    except Exception:
        menu = None

    if menu:
        webview.start(menu=menu)
    else:
        webview.start()
    server.should_exit = True


if __name__ == "__main__":
    main()
