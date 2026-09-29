import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bwhOpen = false
    @State private var xuiOpen = false
    @State private var draft = AppSettings()
    @State private var saved = false
    @State private var saving = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
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
                }
                .padding(28)
                .frame(maxWidth: 700)
                .frame(maxWidth: .infinity, alignment: .center)
            }

            saveBar
        }
        .navigationTitle("设置")
        .onAppear { draft = model.settings }
    }

    private var saveBar: some View {
        HStack(spacing: 12) {
            if saved {
                Label("已保存", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color(red: 0.20, green: 0.66, blue: 0.39))
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
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 14)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
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
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 32, height: 32)
                        .background(
                            Theme.accent.opacity(0.11),
                            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                        )

                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)

                    Spacer()

                    HStack(spacing: 6) {
                        Circle()
                            .fill(configured ? Color.green : Color.secondary.opacity(0.45))
                            .frame(width: 7, height: 7)
                        Text(configured ? "已配置" : "未配置")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }

                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isOpen.wrappedValue ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isOpen.wrappedValue {
                Divider()
                    .padding(.top, 16)

                VStack(alignment: .leading, spacing: 14) {
                    content()
                }
                .padding(.top, 16)
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    /// App-wide preference, deliberately not a third collapsible credentials
    /// section — the two sections above are about connecting, this is about cadence.
    private var refreshCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 32, height: 32)
                .background(
                    Theme.accent.opacity(0.11),
                    in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text("自动刷新")
                    .font(.system(size: 16, weight: .semibold))
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
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
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
            ? "只在手动刷新时重新读取面板"
            : "每 \(refreshLabel(draft.refreshSeconds))重新读取；切回窗口时数据过期也会刷新"
    }

    private func inlineError(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(.primary)
                .lineLimit(3)
            Spacer()
        }
        .padding(14)
        .background(.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func field(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
            TextField(title, text: text)
                .textFieldStyle(.roundedBorder)
                .frame(minHeight: 34)
        }
    }

    private func credential(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
            RomanCredentialField(title, text: text)
                .frame(minHeight: 34)
        }
    }

    private func secret(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
            RomanCredentialField(title, text: text, isSecure: true)
                .frame(minHeight: 34)
        }
    }
}
