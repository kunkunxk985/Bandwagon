// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Bandwagon",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "Bandwagon", targets: ["Bandwagon"]),
        .executable(name: "BandwagonCredentialBridge", targets: ["BandwagonCredentialBridge"])
    ],
    targets: [
        .executableTarget(
            name: "Bandwagon",
            path: "Sources/Bandwagon",
            // 实验：SwiftPM 链接出来的产物把 LC_BUILD_VERSION.sdk 记成了 15.0，
            // 而编译实际用的是 27.0 SDK。macOS 26 按这个字段判定新旧设计语言，
            // 记录成 15.0 会让系统按旧外观绘制窗口按钮等系统控件。
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-platform_version", "-Xlinker", "macos",
                              "-Xlinker", "15.0", "-Xlinker", "27.0"])
            ]
        ),
        // 声明在这里是为了让清单与磁盘上的内容一致，`swift build` 能覆盖整个工程。
        //
        // 但它只是开发期便利：真正安装的辅助程序是 ReleaseAssets/ 里那份冻结的二进制，
        // 摘要被 scripts/credential-bridge.sha256、verify-credential-bridge.sh 与
        // KeychainCredentialStore.helperSHA256 三处共同锁定。从源码构建出来的产物摘要
        // 不同，会被 verify-credential-bridge.sh 拒绝，因此不可能悄悄顶替已安装的版本。
        .executableTarget(
            name: "BandwagonCredentialBridge",
            path: "Sources/BandwagonCredentialBridge"
        )
    ]
)
