import SwiftUI

/// Connection fields shared 1:1 between Settings「连接」and the first-launch wizard.
@MainActor
enum ConnectionFields {
    @ViewBuilder
    static func bandwagon(
        draft: Binding<AppSettings>,
        showApiKeyHint: Bool,
        inlineSave: (() -> Void)? = nil,
        saving: Bool = false,
        saveButtonTitle: String = "保存并连接",
        inlineSaveEnabled: Bool = true
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            labeledField("VEID", text: draft.bwhVeid)
            labeledSecret("API Key", text: draft.bwhApiKey)
            labeledField("API 地址", text: draft.bwhApiBase)
            if showApiKeyHint, !draft.wrappedValue.bwhVeid.isEmpty, draft.wrappedValue.bwhApiKey.isEmpty {
                Text("填写 API Key 后点保存")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            if let inlineSave {
                inlineSaveButton(
                    action: inlineSave,
                    saving: saving,
                    title: saveButtonTitle,
                    enabled: inlineSaveEnabled
                )
            }
        }
    }

    @ViewBuilder
    static func xui(
        draft: Binding<AppSettings>,
        showCredentialHint: Bool,
        inlineSave: (() -> Void)? = nil,
        saving: Bool = false,
        saveButtonTitle: String = "保存并连接",
        inlineSaveEnabled: Bool = true
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            labeledField("面板地址", text: draft.xuiBaseUrl)

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())],
                spacing: 12
            ) {
                labeledCredential("用户名", text: draft.xuiUsername)
                labeledSecret("密码", text: draft.xuiPassword)
            }

            Text("使用面板 Web 登录的用户名与密码；不在此填写 API Token 或双重验证码。")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if showCredentialHint,
               !draft.wrappedValue.xuiBaseUrl.isEmpty,
               draft.wrappedValue.xuiUsername.isEmpty || draft.wrappedValue.xuiPassword.isEmpty {
                Text("填写用户名与密码后点保存")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            if let inlineSave {
                inlineSaveButton(
                    action: inlineSave,
                    saving: saving,
                    title: saveButtonTitle,
                    enabled: inlineSaveEnabled
                )
            }
        }
    }

    private static func labeledField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            TextField(title, text: text)
                .textFieldStyle(.roundedBorder)
                .frame(minHeight: 34)
        }
    }

    private static func labeledCredential(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            RomanCredentialField(title, text: text)
                .frame(minHeight: 34)
        }
    }

    private static func labeledSecret(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            RomanCredentialField(title, text: text, isSecure: true)
                .frame(minHeight: 34)
        }
    }

    private static func inlineSaveButton(
        action: @escaping () -> Void,
        saving: Bool,
        title: String,
        enabled: Bool
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if saving {
                    ProgressView()
                        .controlSize(.small)
                }
                Text(saving ? "连接中…" : title)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(Theme.accent)
        .controlSize(.large)
        .disabled(saving || !enabled)
        .padding(.top, 4)
    }
}
