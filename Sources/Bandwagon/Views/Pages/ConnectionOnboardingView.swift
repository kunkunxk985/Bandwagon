import SwiftUI

struct ConnectionOnboardingView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var onFinished: () -> Void

    @State private var step: Step = .bandwagon
    @State private var draft = AppSettings()
    @State private var saving = false
    @State private var saveFailed = false

    enum Step: Int, CaseIterable {
        case bandwagon = 1
        case xui = 2

        var title: String {
            switch self {
            case .bandwagon: "连接搬瓦工"
            case .xui: "连接 3X-UI（可选）"
            }
        }

        var subtitle: String {
            switch self {
            case .bandwagon:
                "填写 VEID 与 API Key，完成后即可在总览查看套餐流量。"
            case .xui:
                "配置面板后可管理客户端；也可稍后在设置中填写。"
            }
        }
    }

    var body: some View {
        ZStack {
            Theme.canvas
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                Spacer(minLength: 24)
                content
                    .frame(maxWidth: 520)
                    .padding(.horizontal, Theme.pagePadding)
                Spacer(minLength: 24)
                footer
                    .padding(.horizontal, Theme.pagePadding)
                    .padding(.bottom, 28)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { draft = model.settings }
    }

    private var header: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                BrandMark(size: 32)
                Text("Bandwagon")
                    .font(.system(size: 18, weight: .semibold))
            }
            .padding(.top, 40)

            Text("首次连接")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                ForEach(Step.allCases, id: \.rawValue) { item in
                    Capsule()
                        .fill(item.rawValue <= step.rawValue ? Theme.accent : Theme.fill)
                        .frame(width: item == step ? 28 : 20, height: 4)
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: step)
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text(step.title)
                    .font(.system(size: 20, weight: .semibold))
                Text(step.subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if saveFailed {
                Label("未能保存设置，请检查 ~/Library/Application Support/Bandwagon/ 权限", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.warning)
            }

            Group {
                switch step {
                case .bandwagon:
                    ConnectionFields.bandwagon(
                        draft: $draft,
                        showApiKeyHint: true,
                        inlineSave: nil
                    )
                case .xui:
                    ConnectionFields.xui(
                        draft: $draft,
                        showCredentialHint: true,
                        inlineSave: nil
                    )
                }
            }
            .padding(20)
            .panelSurface()
        }
        .frame(maxWidth: .infinity)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if step == .xui {
                Button("跳过") {
                    Task { await finish(skippedXUI: true) }
                }
                .buttonStyle(.bordered)
                .disabled(saving)
            }

            Spacer()

            if step == .bandwagon {
                Button(primaryTitle) {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                        step = .xui
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .controlSize(.large)
                .disabled(!draft.bwhReady || saving)
            } else {
                Button(primaryTitle) {
                    Task { await finish(skippedXUI: false) }
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .controlSize(.large)
                .disabled(saving || !canFinishXUIStep)
            }
        }
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity)
    }

    private var primaryTitle: String {
        if saving { return "连接中…" }
        switch step {
        case .bandwagon: return "继续"
        case .xui: return draft.xuiReady ? "保存并进入" : "进入应用"
        }
    }

    private var canFinishXUIStep: Bool {
        draft.xuiBaseUrl.isEmpty ||
            (draft.xuiReady) ||
            (draft.xuiUsername.isEmpty && draft.xuiPassword.isEmpty)
    }

    private func finish(skippedXUI: Bool) async {
        guard !saving else { return }
        saving = true
        saveFailed = false
        if skippedXUI {
            draft.xuiBaseUrl = ""
            draft.xuiUsername = ""
            draft.xuiPassword = ""
        }
        draft.xuiApiToken = ""
        draft.xuiTwoFactor = ""
        let didSave = await model.saveSettings(draft)
        saving = false
        guard didSave else {
            saveFailed = true
            return
        }
        LaunchOnboarding.markCompleted()
        await model.start()
        onFinished()
    }
}
