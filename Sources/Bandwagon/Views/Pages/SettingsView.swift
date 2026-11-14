import AppKit
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bwhOpen = false
    @State private var xuiOpen = false
    @State private var advancedOpen = false
    @State private var draft = AppSettings()
    @State private var saved = false
    @State private var saveFailed = false
    @State private var saving = false
    @AppStorage(MenuBarPreference.key) private var showMenuBar = true
    @ObservedObject private var updateCenter = AppUpdateCenter.shared
    @State private var manualFallbackDMG: URL?
    @State private var manualFallbackBusy = false

    private var isDirty: Bool { draft != model.settings }

    private var bandwagonSectionDirty: Bool {
        draft.bwhVeid != model.settings.bwhVeid
            || draft.bwhApiKey != model.settings.bwhApiKey
            || draft.bwhApiBase != model.settings.bwhApiBase
    }

    private var xuiSectionDirty: Bool {
        draft.xuiBaseUrl != model.settings.xuiBaseUrl
            || draft.xuiUsername != model.settings.xuiUsername
            || draft.xuiPassword != model.settings.xuiPassword
    }

    private var bandwagonInlineSaveEnabled: Bool {
        bandwagonSectionDirty
            || (!model.settings.bwhReady && (!draft.bwhVeid.isEmpty || !draft.bwhApiKey.isEmpty))
    }

    private var xuiInlineSaveEnabled: Bool {
        xuiSectionDirty
            || (!model.settings.xuiReady
                && (!draft.xuiBaseUrl.isEmpty || !draft.xuiUsername.isEmpty || !draft.xuiPassword.isEmpty))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                PageHeader(title: "设置", subtitle: "日常维护连接与偏好。凭据写入 ~/Library/Application Support/Bandwagon/settings.json（目录 700、文件 600）。")
                    .padding(.bottom, 6)

                if let error = model.error {
                    inlineError(error)
                }

                if let warning = model.credentialAccessWarning {
                    inlineError(warning)
                }

                if saveFailed {
                    settingsSaveFailedBanner
                } else if saved {
                    settingsSavedBanner
                } else if isDirty {
                    unsavedChangesBanner
                }

                blockHeading("连接")

                settingsSection("Bandwagon",
                        icon: "server.rack",
                        isOpen: $bwhOpen,
                        configured: draft.bwhReady
                ) {
                    ConnectionFields.bandwagon(
                        draft: $draft,
                        showApiKeyHint: true,
                        inlineSave: performSave,
                        saving: saving,
                        saveButtonTitle: "确认并连接",
                        inlineSaveEnabled: bandwagonInlineSaveEnabled
                    )
                }

                settingsSection("3X-UI",
                    icon: "person.2.fill",
                    isOpen: $xuiOpen,
                    configured: draft.xuiReady
                ) {
                    ConnectionFields.xui(
                        draft: $draft,
                        showCredentialHint: true,
                        inlineSave: performSave,
                        saving: saving,
                        saveButtonTitle: "确认并连接",
                        inlineSaveEnabled: xuiInlineSaveEnabled
                    )
                }

                blockHeading("偏好")

                refreshCard
                menuBarCard

                settingsSection("高级",
                    icon: "slider.horizontal.3",
                    isOpen: $advancedOpen,
                    configured: true,
                    hideStatusPill: true
                ) {
                    trafficResetSyncRow
                    CardDivider()
                        .padding(.vertical, 4)
                    softwareUpdateCard
                }
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.top, 4)
            .padding(.bottom, Theme.pagePadding)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .navigationTitle("设置")
        .background {
            Button("保存设置", action: performSave)
                .keyboardShortcut("s", modifiers: .command)
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
        .onAppear { draft = model.settings }
        .onChange(of: model.settings) { _, latest in
            guard !isDirty else { return }
            draft = latest
        }
        .onChange(of: draft.refreshSeconds) { _, newValue in
            guard newValue != model.settings.refreshSeconds else { return }
            performSave()
        }
        .onChange(of: draft.syncClientResetWithServer) { _, newValue in
            guard newValue != model.settings.syncClientResetWithServer else { return }
            performSave()
        }
    }

    private func blockHeading(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(.none)
            .padding(.top, 6)
            .padding(.leading, 2)
    }

    private var unsavedChangesBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "pencil.circle.fill")
                .foregroundStyle(Theme.accent)
            Text("有未保存的更改")
                .font(.system(size: 13, weight: .medium))
            Spacer(minLength: 8)
            Text("⌘S")
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(Theme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous)
                .strokeBorder(Theme.accent.opacity(0.28), lineWidth: 1)
        )
        .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
    }

    private var settingsSaveFailedBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.warning)
            Text("设置未能写入 settings.json，请检查 ~/Library/Application Support/Bandwagon/ 权限后重试")
                .font(.system(size: 13, weight: .medium))
            Spacer(minLength: 8)
        }
        .padding(14)
        .background(Theme.warning.opacity(0.09), in: RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous))
        .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
    }

    private var settingsSavedBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Theme.success)
            Text("已保存")
                .font(.system(size: 13, weight: .medium))
            Spacer(minLength: 8)
        }
        .padding(14)
        .background(Theme.success.opacity(0.08), in: RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous))
        .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
    }

    private func performSave() {
        guard !saving else { return }
        saving = true
        Task {
            draft.xuiApiToken = ""
            draft.xuiTwoFactor = ""
            let didSave = await model.saveSettings(draft)
            saving = false
            saveFailed = !didSave
            if didSave {
                draft = model.settings
                draft.xuiTwoFactor = ""
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { saved = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { saved = false }
                }
            }
        }
    }

    private func settingsSection<Content: View>(
        _ title: String,
        icon: String,
        isOpen: Binding<Bool>,
        configured: Bool,
        hideStatusPill: Bool = false,
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

                    if !hideStatusPill {
                        StatusPill(
                            title: configured ? "已配置" : "未配置",
                            tint: configured ? Theme.success : .secondary
                        )
                    }

                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isOpen.wrappedValue ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 0) {
                CardDivider()
                    .padding(.top, 16)

                VStack(alignment: .leading, spacing: 14) {
                    content()
                }
                .padding(.top, 16)
            }
            .frame(maxHeight: isOpen.wrappedValue ? .infinity : 0, alignment: .top)
            .clipped()
            .opacity(isOpen.wrappedValue ? 1 : 0)
            .allowsHitTesting(isOpen.wrappedValue)
            .accessibilityHidden(!isOpen.wrappedValue)
        }
        .padding(18)
        .panelSurface()
        .compositingGroup()
        .clipShape(RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous))
    }

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

    private var trafficResetSyncRow: some View {
        HStack(spacing: 12) {
            SettingsIcon(systemName: "clock.arrow.2.circlepath")

            VStack(alignment: .leading, spacing: 2) {
                Text("流量重置与服务器同步")
                    .font(.system(size: 14, weight: .semibold))
                Text("在搬瓦工流量周期重置时，自动清零所有 3X-UI 客户端用量，并将面板内置重置设为「从不」。")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Toggle("流量重置与服务器同步", isOn: $draft.syncClientResetWithServer)
                .labelsHidden()
                .toggleStyle(.switch)
        }
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

                if updateCenter.isBusy {
                    ProgressView()
                        .controlSize(.small)
                } else if case .available = updateCenter.phase {
                    Button(updatePrimaryTitle, action: { updateCenter.checkOrInstall() })
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.accent)
                } else {
                    Button(updatePrimaryTitle, action: { updateCenter.checkOrInstall() })
                        .buttonStyle(.bordered)
                }
            }

            if case .available(let version, _) = updateCenter.phase {
                Text("新版本 \(version)")
                    .font(.system(size: 12, weight: .medium))
            }

            if case .failed = updateCenter.phase {
                fallbackUpdateActions
            }
        }
    }

    @ViewBuilder
    private var fallbackUpdateActions: some View {
        HStack(spacing: 12) {
            if manualFallbackBusy {
                ProgressView()
                    .controlSize(.small)
            }
            Spacer()
            if let dmg = manualFallbackDMG {
                Button("在访达中显示") {
                    NSWorkspace.shared.activateFileViewerSelecting([dmg])
                }
                .buttonStyle(.bordered)
            } else if let info = updateCenter.fallbackUpdate {
                Button(manualFallbackBusy ? "下载中…" : "手动下载安装包") {
                    downloadFallbackDMG(info)
                }
                .buttonStyle(.bordered)
                .disabled(manualFallbackBusy)
            }
        }
    }

    private var updatePrimaryTitle: String {
        switch updateCenter.phase {
        case .available:
            return "安装更新并重启"
        case .checking:
            return "正在检查…"
        case .downloading:
            return "正在下载…"
        case .installing:
            return "正在安装…"
        case .idle, .upToDate, .failed:
            return "检查更新"
        }
    }

    private var updateStatusText: String {
        switch updateCenter.phase {
        case .idle:
            return "尚未检查 GitHub 上的最新发布。"
        case .checking:
            return "正在检查更新…"
        case .upToDate:
            return "已是最新版本。"
        case .available:
            return "发现新版本，可一键安装。"
        case .downloading:
            return "正在下载…"
        case .installing:
            return "正在安装…"
        case .failed(let message):
            return message
        }
    }

    private var updateStatusColor: Color {
        switch updateCenter.phase {
        case .upToDate:
            return Theme.success
        case .available, .downloading, .installing:
            return Theme.accent
        case .failed:
            return Theme.warning
        default:
            return .secondary
        }
    }

    private func downloadFallbackDMG(_ info: ReleaseUpdateInfo) {
        guard !manualFallbackBusy else { return }
        manualFallbackBusy = true
        Task {
            defer { manualFallbackBusy = false }
            do {
                let fileURL = try await ReleaseUpdateClient.downloadRelease(
                    dmgURL: info.dmgDownloadURL,
                    version: info.version
                )
                manualFallbackDMG = fileURL
                NSWorkspace.shared.activateFileViewerSelecting([fileURL])
            } catch {
                // Optional fallback; main error line stays visible.
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
