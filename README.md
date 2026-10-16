# Bandwagon 瓦工台

macOS 本地客户端，用来看三件事：**搬瓦工套餐流量会不会超额、VPS 是否健康、哪个 3X-UI 客户端需要处理**。

纯 SwiftUI，无第三方依赖，无后台服务。

## 构建与运行

```bash
./swift/scripts/package-app.sh    # 构建 + 签名，产物在 ~/Desktop/Bandwagon.app
open ~/Desktop/Bandwagon.app
```

需要 Xcode（脚本会显式使用 `/Applications/Xcode.app` 的工具链和 macOS SDK，不用 CLT SDK）。

跑测试：

```bash
./swift/scripts/test.sh           # 离线回归，24 项断言
./swift/scripts/test.sh --live    # 额外打一次真实 3X-UI 面板
```

检查界面改动（无需屏幕录制权限，应用自己把四个页面渲染成 PNG 后退出）：

```bash
open -n --env BANDWAGON_SNAPSHOT_DIR=/tmp/bandwagon-shots ~/Desktop/Bandwagon.app
```

加 `--env BANDWAGON_SNAPSHOT_APPEARANCE=dark` 渲染深色模式。

## 数据放在哪

| 内容 | 位置 |
| --- | --- |
| 凭据（API Key、面板账号密码） | 登录钥匙串，经独立的凭据辅助程序读写 |
| 非敏感设置（VEID、面板地址、刷新间隔） | `~/Library/Application Support/WagongDeck/settings.json` |
| 凭据辅助程序 | `~/Library/Application Support/Bandwagon/BandwagonCredentialBridge` |

仓库根目录只有设计文档、本 README 和 `swift/`。曾经存在的 `.env` / `.env.example` 描述的是已删除的旧 Web 服务，已于本次整理中移除。

## 目录结构

```
swift/
├── Sources/            应用与凭据辅助程序源码（Views 下分 Shell / Pages / Components / DesignSystem）
├── Tests/              回归测试与夹具
├── DevTools/           手动排查用的脚本，不属于测试
├── scripts/            构建、打包、凭据辅助程序的验证脚本
├── packaging/          App 图标资源
├── ReleaseAssets/      固定不动的凭据辅助程序发布件
└── Docs/               结构与历史文档
```

每个文件的职责见 [`swift/Docs/STRUCTURE.md`](swift/Docs/STRUCTURE.md)。

## 设计约束

界面遵循 [`.impeccable.md`](.impeccable.md)：浅色优先、单一蓝色主行动色、少量语义状态色，明确避免信息过密和霓虹感。改 UI 前请先读那五条原则。

视觉上是「精致数据面板」：白色面板 + 1px 细边框，不用毛玻璃、渐变和阴影，层级靠字号。颜色、圆角、间距都在 `swift/Sources/Bandwagon/Views/DesignSystem/Theme.swift`，深浅两套值。
