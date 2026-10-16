# 项目结构

每个目录与文件的职责。**改动前先看这里**，避免把开发工具当测试、或把历史遗留当现役代码。

## 顶层

```
Bandwagon/
├── .impeccable.md      设计上下文与五条设计原则。改 UI 前必读。
├── README.md           构建、运行、数据位置。
├── .gitignore          Swift 构建产物、Python 缓存、凭据。
└── swift/              全部源码与资产。工程自包含，不引用目录外任何东西。
```

## swift/

```
swift/
├── Package.swift                 SwiftPM 清单，声明主应用与凭据辅助程序两个可执行目标
├── Sources/
│   ├── Bandwagon/                主应用（Models / Services / Views）
│   └── BandwagonCredentialBridge/ 凭据辅助程序（独立可执行文件）
├── Tests/                        回归测试与夹具
├── DevTools/                     手动排查脚本，不参与自动测试
├── scripts/                      构建、打包、验证
├── packaging/macos/              App 图标资源
├── ReleaseAssets/                凭据辅助程序发布件
└── Docs/                         文档
```

### Sources/Bandwagon/ —— 主应用

| 文件 | 职责 |
| --- | --- |
| `BandwagonApp.swift` | `@main` 入口。主窗口 WindowGroup（id `main`）与菜单栏 `MenuBarExtra`；两者都调用幂等的 `model.start()`；⌘R 刷新；开着菜单栏时窗口进后台也继续轮询 |

**Models/**

| 文件 | 职责 |
| --- | --- |
| `APIModels.swift` | 两个数据源的响应模型；`Client` 与其 `state`/`expiryWarning`；`ByteFormat`（字节格式化）；`DateFormats`（带锁的格式化器缓存）；`UsageThreshold`（0.7/0.9 阈值，全应用唯一来源） |
| `TrafficChartData.swift` | 原始采样 → 采样点/小时桶/日桶的派生；区间裁剪；`TrafficSummary` 汇总；`TrafficSampleCache` 供图表与迷你卡共用 |
| `TrafficForecast.swift` | 用最近 7 天实测燃尽速率对比距重置天数，给出 safe/tight/over 结论。缺配额或历史时返回 nil，不猜 |

**Services/**

| 文件 | 职责 |
| --- | --- |
| `AppModel.swift` | `@Observable` 全局状态。后台加载设置、并发拉取两个数据源、保留上次成功数据、按间隔轮询、保存设置 |
| `BWHClient.swift` | 搬瓦工 KiwiVM API（套餐、用量、重置日、流量历史） |
| `XUIClient.swift` | 3X-UI 面板客户端。Cookie 会话、CSRF、表单登录、2FA、API Token；读取客户端列表；写操作（启用/停用、改配额与到期、重置流量）与订阅地址。写操作按 **3X-UI v3** 的 `/panel/api/clients/*` 接口实现，见下方「3X-UI 写操作」 |
| `XUIError.swift` | 把底层错误翻译成不含敏感信息的用户可读文案，并标记是否需要改设置 |
| `SecureURLPolicy.swift` | 面板地址校验（仅 HTTPS 或环回 HTTP）与 TLS 校验策略 |
| `JSONValue.swift` | JSON 值的安全强制转换，避免 `as?` 满天飞 |
| `SettingsStore.swift` | `settings.json` 的读写。凭据不入文件，只存 VEID、地址、刷新间隔 |
| `KeychainCredentialStore.swift` | 凭据读写入口。实际通过辅助程序完成，并在首次运行时做一次性 v2→v3 迁移 |
| `CredentialBridgeClient.swift` | 与辅助程序的 IPC 客户端。发请求前校验辅助程序文件的 SHA-256 与签名，并校验**正在运行的子进程**身份 |

**Views/** —— 按职责分四个子目录

`Shell/`（窗口外壳）

| 文件 | 职责 |
| --- | --- |
| `ContentView.swift` | 外壳：侧栏、工具栏（更新时间 + 刷新）、标签路由、错误提示 |
| `WindowChrome.swift` | 窗口管道：`VisualEffectView`（侧栏材质）与 `WindowChrome`（透明标题栏、隐藏窗口标题、全尺寸内容视图） |
| `MenuBarPanel.swift` | 菜单栏图标（符号随预测变化 + 已用百分比）与下拉面板：用量环、预测结论、在线数、需要注意的客户端、打开主窗口 / 退出 |
| `DevSnapshot.swift` | 开发辅助：设置 `BANDWAGON_SNAPSHOT_DIR` 启动时把四个页面（含滚到底部的长页）、菜单栏面板、首个客户端的详情弹窗渲染成 PNG 后退出。不设该变量时完全不生效 |

`Pages/`（四个页面）

| 文件 | 职责 |
| --- | --- |
| `OverviewView.swift` | 总览：页头（主机、运行状态、在线数）、用量 hero、近 7 天流量、用量最高的客户端、服务器 |
| `VPSView.swift` | VPS：用量 hero、系统概况规格表、流量趋势图 |
| `ClientsView.swift` | 客户端：统计条、筛选/排序/搜索、带固定表头的客户端表格 |
| `SettingsView.swift` | 设置：两个凭据区块 + 自动刷新 + 菜单栏开关（即时生效）+ 底部保存栏（⌘S） |
| `ClientDetailSheet.swift` | 客户端详情弹窗：用量、订阅链接与二维码、启用开关、配额与到期编辑、重置流量。每个写操作先确认、完成后刷新 |

`Components/`（跨页复用的组件）

| 文件 | 职责 |
| --- | --- |
| `Components.swift` | `ForecastStrip`、`CardDivider`、`SummaryTile`、`UsageBar`、`UsageTint`、`UsageRing`（随用量与预测变色）、`StatusPill`、`InfoCell`、`HeroChip` |
| `StatusViews.swift` | 状态呈现：`StatusCard`（整页）、`StatusBanner`（有数据时的内联提示）、`CenterWhenShort` |
| `MiniTrafficCard.swift` | 总览的「近 7 天流量」柱状卡 |
| `TrafficHistoryChart.swift` | VPS 的流量趋势图（Swift Charts）与汇总指标 |
| `RomanCredentialField.swift` | 强制凭据输入走罗马输入源，避免中文输入法吞掉 ASCII 字符 |

`DesignSystem/`（设计令牌与基础构件）

| 文件 | 职责 |
| --- | --- |
| `Theme.swift` | 设计令牌（颜色含深浅两套值、圆角、间距、字号）与基础构件：`Panel`、`PanelHeader`、`PanelLink`、`PageHeader`、`RingMeter`、`UsageHero`、`StatDivider` |
| `ModelPresentation.swift` | 模型类型的展示规则：健康色/文案、预测结论色/图标、`ClientState` 配色，以及 `ServiceFailure`（三页共用的失败呈现与恢复动作） |

**视觉语言**（2026-10-16 起）：精致数据面板。中性画布 + 白色面板，只用 1px 细边框区分层级，不用毛玻璃、渐变和阴影；层级靠字号与字重（大号等宽数字 + 小号次要标签）；每页有页内大标题，工具栏只留更新时间与刷新；状态用圆点 + 文字，不用彩色胶囊。新增 UI 一律从 `Theme` 取色与尺寸，不在页面里写死颜色。

### Sources/BandwagonCredentialBridge/ —— 凭据辅助程序

| 文件 | 职责 |
| --- | --- |
| `main.swift` | 独立可执行文件。拥有钥匙串条目，只接受父进程满足 `identifier "com.kun.bandwagon" and certificate root = H"53b7…"` 的请求；不满足直接 `exit(77)` |

**为什么单独拆出来**：主应用每次重新打包签名都会变，钥匙串 ACL 随之失效。辅助程序装在 `.app` 之外、发布后永不重建，ACL 绑定的是它的 cdhash，因此重新打包不再影响凭据读取。

⚠️ 它在 `Package.swift` 里声明为第二个目标，`swift build` 会编译它，但那只是开发期便利：**真正安装的是 `ReleaseAssets/BandwagonCredentialBridge-v1` 这份冻结件**，摘要被三处锁定，从源码构建的产物会被 `verify-credential-bridge.sh` 拒绝。要出新版本用 `scripts/build-credential-bridge.sh`（见下）。

### Tests/ —— 回归测试

全部由 `scripts/test.sh` 驱动，每条打印一行 `PASS`，失败即退出。

| 文件 | 覆盖 |
| --- | --- |
| `HTTPRegression.swift` | 配合 `http_fixture.py`：Cookie 会话、CSRF、表单登录、2FA、认证失败保留错误而非假空列表 |
| `StateRegression.swift` | 地址策略、并发刷新、只登录一次、连接失败不清空数据、保存失败不覆盖当前设置 |
| `SecurityRegression.swift` | 传输层、钥匙串、TLS 校验、2FA 临时性（源码级断言） |
| `UsagePolicyRegression.swift` | 阈值口径：`Client.state` 与 `UsageTint` 必须共用同一套阈值 |
| `InputPolicyRegression.swift` | 凭据输入框强制罗马字符 |
| `TrafficChartRegression.swift` | 区间裁剪、汇总、悬停、单位、缓存失效、稳定标识、逐帧成本 |
| `ForecastRegression.swift` | 超额预测的三档判定、边界、措辞、以及「该不该给结论」 |
| `UICompositionRegression.swift` | 源码级 UI 断言：卡片统一、错误降级、主环取色、减弱动效、格式化器缓存等 |
| `CredentialBridgeFixtureRegression.swift` | 临时签名一份辅助程序与父进程，跑完整协议、摘要锁定、ACL 分区 |
| `CredentialHelperRegression.swift` | 已安装的辅助程序必须拒绝非 Bandwagon 调用者 |
| `LiveFetch.swift` | 只在 `--live` 时运行，打一次真实面板 |
| `http_fixture.py` | 上述 HTTP 测试用的本地夹具服务器 |

### DevTools/ —— 手动排查脚本

**不是测试，不被 `test.sh` 调用**，需要时手动编译运行。

| 文件 | 用途 |
| --- | --- |
| `Probe.swift` | 直接打 3X-UI 接口，看原始响应 |
| `UIState.swift` | 打印应用进程数与辅助功能授权状态 |
| `UIVerify.swift` | 用辅助功能接口读界面、切页面 |
| `protocol_probe.py` | 裸协议探测 |

### scripts/

| 文件 | 用途 |
| --- | --- |
| `package-app.sh` | 构建 release、组装 `.app`、生成图标、签名、装到 `~/Desktop`。构建前会先校验辅助程序 |
| `test.sh` | 离线回归套件。`--live` 追加真实面板测试 |
| `install-credential-bridge.sh` | 安装辅助程序。已有 v3 钥匙串条目时**拒绝替换**，防止覆盖掉正在使用的凭据 |
| `build-credential-bridge.sh` | 从源码产出新的辅助程序发布件：编译、签名、写入 `ReleaseAssets/`、打印需同步的三处摘要。`--update-pin` 可一并改写摘要锁定。**绝不触碰已安装的辅助程序** |
| `verify-credential-bridge.sh` | 校验辅助程序的 SHA-256 与代码签名要求 |
| `verify-credential-bridge-acl.py` | 只读钥匙串元数据，确认 v3 条目的 ACL 绑定在辅助程序的 cdhash 上，且旧条目仍在 |
| `test-credential-bridge.sh` | 凭据辅助程序的完整验证：夹具协议 + 拒绝未签名调用者 + ACL 校验 |
| `credential-bridge.sha256` | 辅助程序发布件的摘要，被代码、脚本、验证三处共同引用 |

### 其他

| 路径 | 说明 |
| --- | --- |
| `packaging/macos/icon.iconset/` | App 图标源文件，`package-app.sh` 用 `iconutil` 转成 `.icns`。生成脚本 `make_icon.py` 已在 Python 时代删除，**所以这些 PNG 不可再生** |
| `ReleaseAssets/BandwagonCredentialBridge-v1` | 已签名的辅助程序发布件。摘要与 `scripts/credential-bridge.sha256`、`KeychainCredentialStore.helperSHA256` 三处必须一致 |
| `Docs/3X-UI-verification.md` | 历史记录：当初 3X-UI 认证失败的排查过程与结论。**不是当前状态**，仅存档 |

## 3X-UI 写操作

按 3X-UI v3（React 前端、客户端独立成记录并可挂到多个入站）实现，接口与上游 v3.10.2 源码逐一核对过：

| 动作 | 接口 | 说明 |
| --- | --- | --- |
| 启用 / 停用 | `POST /panel/api/clients/bulkEnable` · `bulkDisable`，`{"emails":[…]}` | 只改启用状态；面板拒绝时原因在成功响应的 `skipped` 里，会转成错误提示 |
| 改配额 / 到期 | `GET /clients/get/{email}` → `POST /clients/update/{email}` | `update` 整条替换，所以先读记录，再按面板自己的 `ClientRecord.ToClient` 转换后只改这两项送回。`totalGB` 单位是**字节**，`expiryTime` 是毫秒，负数表示「首次使用后 N 天」 |
| 重置流量 | `POST /clients/resetTraffic/{email}` | v3 会同时**重新启用**已停用的客户端，界面已说明 |
| 订阅链接 | `POST /panel/api/setting/defaultSettings` → `subURI` + 客户端 `subId` | 与面板自己的二维码弹窗同源，不读含密钥的 `setting/all` |

v2 的 `/panel/api/inbounds/updateClient`、`resetClientTraffic` 和 `/panel/setting/*` 在 v3 已不存在。回归测试 `HTTPRegression` 的 `writes` / `write-reject` 两组在本地夹具上逐字节校验以上请求体。

## 已知的结构问题

1. **测试不是 SwiftPM 测试目标**，而是 `scripts/test.sh` 逐个用 `swiftc` 编译出来的独立可执行文件。没有 `swift test`，每个用例都要重新编译一遍 Models + Services，新增测试要手工加进脚本。
2. **辅助程序的发布件不是逐字节可复现的**。`scripts/build-credential-bridge.sh` 能从源码产出并签名新版本，但原始 v1 的确切构建命令已不可考（同一份源码、同一个 SDK，重建出来的机器码仍与 v1 不同），加上签名本身每次不同，所以产物摘要必然变化。采用新版本要同步三处摘要，并重新输入一次凭据。
3. **状态未知时仍显示"运行中"**。`getLiveServiceInfo` 失败时回退到硬编码的 `"running"`，沿用部署版一直以来的行为。更诚实的做法是显示"未知"，但那会改变现有观感，未擅自改动。

## 已解决

- **磁盘占用条从不显示**（原第 7 条）：根因是代码从 `getServiceInfo` 读 `ve_used_disk_space_b`，而该字段属于 **`getLiveServiceInfo`**，且只在 KVM 机型下返回。同一个错误还导致状态胶囊里的"运行中"一直是硬编码兜底值而非真实状态。已改为并发补调 `getLiveServiceInfo`，磁盘条与真实运行状态同时恢复。
- **`swift/` 未被 git 跟踪**（原第 1 条）：曾是完全无版本控制。已分两次提交纳入：先移除被取代的 Python 应用，再跟踪 Swift 工程（73 个文件）。
- **`.env` / `.env.example` 是死配置**（原第 2 条）：描述的是已删除的 Web 服务，凭据字段全为空。已删除。
- **辅助程序无法从源码重建**（原第 3 条）：新增 `scripts/build-credential-bridge.sh`，编译、签名、产出带版本号的发布件、打印需要同步的三处摘要，并明确警告替换安装件会使钥匙串 ACL 失效。它绝不触碰已安装的辅助程序。
- **`Package.swift` 与磁盘不符**：曾只声明一个目标，而 `Sources/` 下有两个可执行目录，`swift build` 完全忽略凭据辅助程序。已补全。
- **`Theme.swift` 是杂物抽屉**：422 行里混了色板、窗口管道、11 个组件和 3 个模型扩展。已按职责拆成 `Theme.swift`（216 行）、`WindowChrome.swift`、`StatusViews.swift`、`ModelPresentation.swift`。
- **失败呈现逻辑抄了三份**：`OverviewView` 与 `ClientsView` 各有 4 个逐字相同的函数，`VPSView` 内联了同一套判断，而且三页对同一个失败的中文措辞还不一致。已收敛到 `ServiceFailure`，三页共用。
- **死代码**：`SettingsPayload`、`SettingsSaveResponse`、`refreshInterval`、`ColorToken`、`ClientState.color`、`overview.demo` 已删。
- **图标不可再生**：曾同时被 `.gitignore` 排除且生成脚本已删。已去掉排除项并纳入版本控制。


