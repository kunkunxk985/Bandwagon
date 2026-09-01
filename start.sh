#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")"
if [ ! -d .venv ]; then
  python3 -m venv .venv
fi
# 依赖齐全时跳过安装，离线也能启动
if ! .venv/bin/python -c "import fastapi, uvicorn, httpx, dotenv, webview" >/dev/null 2>&1; then
  .venv/bin/pip install -q -r requirements.txt
fi
if [ ! -f .env ]; then
  cp .env.example .env
  echo "已创建 .env，当前会用演示数据。填入搬瓦工和 3X-UI 凭证后重启即可拉真实流量。"
fi
echo "启动瓦工台客户端…"
exec .venv/bin/python -m app.desktop
