# Bandwagon 瓦工台

macOS 本地客户端，用来看三件事：**搬瓦工套餐流量会不会超额、VPS 是否健康、哪个 3X-UI 客户端需要处理**。

- 总览：用量环、超额预测与时间轴、近 7 天流量、用量最高的客户端
- 菜单栏常驻：不开窗口也能看到已用百分比和超额预测
- 客户端管理（3X-UI v3）：订阅链接（通用 / Clash）与二维码、启用 / 停用、改配额与到期、重置流量；每次写操作都先确认
- 连不上搬瓦工时，自动判断是不是本地代理（fake-ip）的问题

纯 SwiftUI，无第三方依赖，无后台服务。

## 构建与运行

```bash
./scripts/package-app.sh    # 构建 + 签名，产物在 ~/Desktop/Bandwagon.app
open ~/Desktop/Bandwagon.app
```

需要 Xcode（脚本显式使用 `/Applications/Xcode.app` 的工具链和 macOS SDK，不用 CLT SDK）。

```bash
./scripts/test.sh           # 离线回归测试
./scripts/make-icon.sh      # 改了 packaging/MakeIcon.swift 后重新生成图标
```

检查界面改动（不需要屏幕录制权限，应用自己把各页面渲染成 PNG 后退出）：

```bash
open -n --env BANDWAGON_SNAPSHOT_DIR=/tmp/bandwagon-shots ~/Desktop/Bandwagon.app
```

可再加 `--env BANDWAGON_SNAPSHOT_APPEARANCE=dark`（深色）或 `--env BANDWAGON_SNAPSHOT_WIDTH=1700`（宽窗口）。

## 数据放在哪

| 内容 | 位置 |
| --- | --- |
| 凭据（API Key、面板账号密码） | 登录钥匙串，经独立的凭据辅助程序读写 |
| 非敏感设置（VEID、面板地址、刷新间隔） | `~/Library/Application Support/Bandwagon/settings.json` |
| 凭据辅助程序 | `~/Library/Application Support/Bandwagon/BandwagonCredentialBridge` |

旧版本把设置放在 `~/Library/Application Support/WagongDeck/`，启动时会自动搬过来。

## 目录结构

```
Bandwagon/
├── Package.swift       SwiftPM 清单：主应用 + 凭据辅助程序
├── Sources/
│   ├── Bandwagon/      主应用（Models / Services / Views）
│   └── BandwagonCredentialBridge/
├── Tests/              回归测试与本地夹具
├── scripts/            构建、打包、测试、图标、凭据辅助程序
├── packaging/          图标源码与生成的 iconset
├── ReleaseAssets/      冻结的凭据辅助程序发布件
└── Docs/               设计、决策、结构、排查
```

| 文档 | 内容 |
| --- | --- |
| [`Docs/DESIGN.md`](Docs/DESIGN.md) | 设计原则与无障碍基线，改 UI 前先读 |
| [`Docs/DECISIONS.md`](Docs/DECISIONS.md) | 已定的取舍、改 UI 的流程、踩过的坑 |
| [`Docs/STRUCTURE.md`](Docs/STRUCTURE.md) | 每个文件的职责、3X-UI 接口、已知问题 |
| [`Docs/TROUBLESHOOTING.md`](Docs/TROUBLESHOOTING.md) | 连不上搬瓦工时怎么排查 |
