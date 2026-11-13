import AppKit
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bwhOpen = false
    @State private var xuiOpen = false
    @State private var draft = AppSettings()
    @State private var saved = false
    @State private var saveFailed = false
    @State private var saving = false
    @AppStorage(MenuBarPreference.key) private var showMenuBar = true
    @State private var updatePhase: SoftwareUpdatePhase = .idle
    @State private var pendingUpdate: ReleaseUpdateInfo?
    @State private var downloadingUpdate = false
    @State private var downloadedDMG: URL?

    private enum SoftwareUpdatePhase: Equatable {
        case idle
        case checking
        case upToDate
        case updateAvailable
        case error(String)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    PageHeader(title: "设置", subtitle: "连接两个数据源。凭据只保存在钥匙串，不写入设置文件。")
                        .padding(.bottom, 6)

                    if let error = model.error {
                        inlineError(error)
                    }

                    settingsSection("Bandwagon",
                        icon: "server.rack",
                        isOpen: $bwhOpen,
                        configured: draft.bwhReady
                    ) {
                        field("VEID", text: $draft.bwhVeid)
                        secret("API Key", text: $draft.bwhApiKey)
                        field("API 地址", text: $draft.bwhApiBase)
                    }

                    settingsSection("3X-UI",
                        icon: "person.2.fill",
                        isOpen: $xuiOpen,
                        configured: draft.xuiReady
                    ) {
                        field("面板地址", text: $draft.xuiBaseUrl)

                        LazyVGrid(
                            columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())],
                            spacing: 12
                        ) {
                            credential("用户名", text: $draft.xuiUsername)
                            secret("密码", text: $draft.xuiPassword)
                        }

                        secret("API Token", text: $draft.xuiApiToken)
                        secret("当前双重验证码（如启用）", text: $draft.xuiTwoFactor)
                    }

                    refreshCard
                    menuBarCard
                    softwareUpdateCard
                }
                .padding(.horizontal, Theme.pagePadding)
                .padding(.top, 4)
                .padding(.bottom, Theme.pagePadding)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity, alignment: .center)
            }

            saveBar
        }
        .navigationTitle("设置")
        .onAppear { draft = model.settings }
    }

    private var saveBar: some View {
        HStack(spacing: 12) {
            if saveFailed {
                Label("凭据未写入钥匙串，请把应用放进「应用程序」后重试", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.warning)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom)))
            } else if saved {
                Label("已保存", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.success)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom)))
            }

            Spacer()

            Button {
                guard !saving else { return }
                saving = true
                Task {
                    let didSave = await model.saveSettings(draft)
                    draft.xuiTwoFactor = ""
                    saving = false
                    saveFailed = !didSave
                    if didSave {
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { saved = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { saved = false }
                        }
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    if saving {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(saving ? "连接中…" : "保存并刷新")
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .controlSize(.large)
            .disabled(saving)
            .keyboardShortcut("s", modifiers: .command)
        }
        .padding(.horizontal, Theme.pagePadding)
        .padding(.vertical, 12)
        .background(Theme.surface)
        .overlay(alignment: .top) { CardDivider() }
    }

    private func settingsSection<Content: View>(
        _ title: String,
        icon: String,
        isOpen: Binding<Bool>,
        configured: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(reduceMotion ? nil : .interactiveSpring(response: 0.24, dampingFraction: 0.9)) {
                    isOpen.wrappedValue.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    SettingsIcon(systemName: icon)

                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)

                    Spacer()

                    StatusPill(
                        title: configured ? "已配置" : "未配置",
                        tint: configured ? Theme.success : .secondary
                    )

                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isOpen.wrappedValue ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isOpen.wrappedValue {
                CardDivider()
                    .padding(.top, 16)

                VStack(alignment: .leading, spacing: 14) {
                    content()
                }
                .padding(.top, 16)
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(18)
        .panelSurface()
    }

    /// App-wide preference, deliberately not a third collapsible credentials
    /// section — the two sections above are about connecting, this is about cadence.
    private var refreshCard: some View {
        HStack(spacing: 12) {
            SettingsIcon(systemName: "arrow.triangle.2.circlepath")

            VStack(alignment: .leading, spacing: 2) {
                Text("自动刷新")
                    .font(.system(size: 14, weight: .semibold))
                Text(refreshHint)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            Picker("自动刷新", selection: $draft.refreshSeconds) {
                ForEach(AppSettings.refreshChoices, id: \.self) { seconds in
                    Text(refreshLabel(seconds)).tag(seconds)
                }
            }
            .labelsHidden()
            .frame(width: 132)
        }
        .padding(18)
        .panelSurface()
    }

    /// Takes effect at once rather than on save: it is about this Mac, not about
    /// the connections the save button commits.
    private var menuBarCard: some View {
        HStack(spacing: 12) {
            SettingsIcon(systemName: "menubar.rectangle")

            VStack(alignment: .leading, spacing: 2) {
                Text("菜单栏")
                    .font(.system(size: 14, weight: .semibold))
                Text("在系统菜单栏显示套餐用量与预测")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            Toggle("在菜单栏显示", isOn: $showMenuBar)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .padding(18)
        .panelSurface()
    }

    private var softwareUpdateCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                SettingsIcon(systemName: "arrow.down.circle")

                VStack(alignment: .leading, spacing: 4) {
                    Text("软件更新")
                        .font(.system(size: 14, weight: .semibold))
                    Text("当前版本 \(ReleaseUpdateClient.installedVersion)")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Text(updateStatusText)
                        .font(.system(size: 12))
                        .foregroundStyle(updateStatusColor)
                }

                Spacer(minLength: 12)

                if updatePhase == .checking || downloadingUpdate {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Button("检查更新", action: checkForUpdate)
                        .buttonStyle(.bordered)
                        .disabled(downloadingUpdate)
                }
            }

            secret("GitHub 更新令牌", text: $draft.githubUpdateToken)
            Text("私有仓库需 Personal Access Token：classic 勾选 repo，或 fine-grained 对本仓库只读。")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            if case .updateAvailable = updatePhase, let info = pendingUpdate {
                HStack(spacing: 12) {
                    Text("新版本 \(info.version)")
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    Button(downloadingUpdate ? "下载中…" : "下载更新包") {
                        downloadUpdate(info)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .disabled(downloadingUpdate)
                }
            }

            if let dmg = downloadedDMG {
                HStack(spacing: 12) {
                    Text("安装包已下载")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("在访达中显示") {
                        NSWorkspace.shared.activateFileViewerSelecting([dmg])
                    }
                    .buttonStyle(.bordered)
                    Button("打开安装包") {
                        NSWorkspace.shared.open(dmg)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                }
            }
        }
        .padding(18)
        .panelSurface()
    }

    private var updateStatusText: String {
        switch updatePhase {
        case .idle:
            return "尚未检查 GitHub 上的最新发布。"
        case .checking:
            return "正在检查更新…"
        case .upToDate:
            return "已是最新版本。"
        case .updateAvailable:
            return "发现新版本，可下载安装包。"
        case .error(let message):
            return message
        }
    }

    private var updateStatusColor: Color {
        switch updatePhase {
        case .upToDate:
            return Theme.success
        case .updateAvailable:
            return Theme.accent
        case .error:
            return Theme.warning
        default:
            return .secondary
        }
    }

    private func checkForUpdate() {
        guard updatePhase != .checking, !downloadingUpdate else { return }
        updatePhase = .checking
        pendingUpdate = nil
        Task {
            do {
                let outcome = try await ReleaseUpdateClient.checkForUpdate(
                    githubToken: draft.githubUpdateToken
                )
                switch outcome {
                case .upToDate:
                    updatePhase = .upToDate
                case .updateAvailable(let info):
                    pendingUpdate = info
                    updatePhase = .updateAvailable
                }
            } catch let error as ReleaseUpdateError {
                updatePhase = .error(error.localizedDescription)
            } catch {
                updatePhase = .error(error.localizedDescription)
            }
        }
    }

    private func downloadUpdate(_ info: ReleaseUpdateInfo) {
        guard !downloadingUpdate else { return }
        downloadingUpdate = true
        Task {
            defer { downloadingUpdate = false }
            do {
                let fileURL = try await ReleaseUpdateClient.downloadRelease(
                    dmgURL: info.dmgDownloadURL,
                    version: info.version,
                    githubToken: draft.githubUpdateToken
                )
                downloadedDMG = fileURL
                NSWorkspace.shared.activateFileViewerSelecting([fileURL])
                updatePhase = .upToDate
                pendingUpdate = nil
            } catch {
                updatePhase = .error(error.localizedDescription)
            }
        }
    }

    private func refreshLabel(_ seconds: Int) -> String {
        switch seconds {
        case 0: return "仅手动"
        case 60: return "1 分钟"
        case 300: return "5 分钟"
        case 900: return "15 分钟"
        case 1800: return "30 分钟"
        default: return "\(max(1, seconds / 60)) 分钟"
        }
    }

    private var refreshHint: String {
        draft.refreshSeconds == 0
            ? "只在手动刷新时重新读取数据"
            : "每 \(refreshLabel(draft.refreshSeconds))自动重新读取"
    }

    private func inlineError(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.warning)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(.primary)
                .lineLimit(3)
            Spacer()
        }
        .padding(14)
        .background(Theme.warning.opacity(0.09), in: RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous))
    }

    private func field(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            TextField(title, text: text)
                .textFieldStyle(.roundedBorder)
                .frame(minHeight: 34)
        }
    }

    private func credential(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            RomanCredentialField(title, text: text)
                .frame(minHeight: 34)
        }
    }

    private func secret(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            RomanCredentialField(title, text: text, isSecure: true)
                .frame(minHeight: 34)
        }
    }
}

/// Monochrome glyph on a neutral square, the one icon treatment on this page.
private struct SettingsIcon: View {
    var systemName: String

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(width: 30, height: 30)
            .background(Theme.fill, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
    }
}
