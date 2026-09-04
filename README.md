# Bandwagon

macOS 本地客户端：看搬瓦工 **本月套餐流量**，以及 3X-UI 里 **每个客户端** 的已用/配额/在线。

双击 **桌面上的「Bandwagon」** 即可。密钥写在应用内「设置」，存在本机：

`~/Library/Application Support/WagongDeck/settings.json`

没填密钥时显示演示数据。

## 启动

双击 `~/Desktop/Bandwagon.app`，或：

```bash
cd ~/Desktop/Bandwagon
./start.sh
```

## 接真实数据

打开应用后点右上角 **设置**，或继续用 `.env`（设置里的值优先）：

### 搬瓦工

1. 打开 [KiwiVM](https://kiwivm.64clouds.com/)
2. 左侧 **API**
3. 记下 **VEID**，点 **Show API Key**
4. 填入：

```env
BWH_VEID=你的VEID
BWH_API_KEY=你的API_KEY
```

已用流量会乘上 `monthly_data_multiplier`（和 KiwiVM 面板一致）。这是套餐计费流量，用满会停机。

### 3X-UI

面板地址含自定义路径，不要末尾斜杠，也不要带上 `/panel`（3X-UI v3 会自动拼接）：

```env
XUI_BASE_URL=http://127.0.0.1:2053
```

如果面板有路径前缀，写成：

```env
XUI_BASE_URL=https://你的域名:2053/secret
```

认证二选一：

1. **推荐** 面板里：设置 → 安全 → API Token（v3 支持作用域，且不受登录限流影响）

```env
XUI_API_TOKEN=你的token
```

2. 或账号密码（v3 登录需要 CSRF token，应用已自动处理；密码输错会在界面顶部显示面板的报错）：

```env
XUI_USERNAME=admin
XUI_PASSWORD=你的密码
```

自签证书：

```env
XUI_VERIFY_SSL=0
```

3X-UI 若只监听本机，在笔记本上可先做隧道：

```bash
ssh -L 2053:127.0.0.1:2053 root@你的VPS
```

然后 `XUI_BASE_URL=http://127.0.0.1:2053`

应用内保存后会立刻重拉数据；勾选「清除已保存的密钥」可以删掉已存的 API Key / Token / 密码。`.env` 改完后重新打开应用。

## 界面会显示什么

- 搬瓦工：本月已用 / 额度 / 剩余 / 重置日、IP、机房、套餐
- 近几天入站/出站曲线（KiwiVM `getRawUsageStats`）
- 3X-UI：CPU / 内存 / 磁盘 / Xray 状态、各入站合计
- 客户端表：上传、下载、配额占比、到期、是否在线

搬瓦工统计的是 **整机** 流量；3X-UI 只统计 **节点客户端**。两者本来就不会相等。

## 安全

这是本机窗口应用，不要把接口端口映射到公网。若必须外网访问（不推荐），设置：

```env
DASHBOARD_PASSWORD=一个长密码
HOST=0.0.0.0
```

密钥保存在本机 `settings.json`（权限 600，仅当前用户可读）。后台每 30 秒轮询一次数据源，连续 5 分钟没有前端访问会自动暂停，避免白白消耗 KiwiVM 的 API 配额。

## Docker（可装在 VPS 本机）

```bash
docker build -t wagong-deck .
docker run --rm -p 8787:8787 --env-file .env wagong-deck
```

和 3X-UI 同机时，`XUI_BASE_URL` 用 `http://127.0.0.1:2053`（注意容器网络要用 `host` 或容器网关访问宿主机）。
