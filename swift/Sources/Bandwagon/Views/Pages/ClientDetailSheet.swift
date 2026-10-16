import AppKit
import CoreImage.CIFilterBuiltins
import SwiftUI

/// One client in full: usage, the subscription link with its QR code, and the
/// actions that change the client on the panel. Every write is confirmed first and
/// followed by a refresh, so the sheet always shows what the panel now holds.
struct ClientDetailSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let clientID: String

    @State private var link: LinkState = .loading
    @State private var linkCopied = false
    @State private var working = false
    @State private var errorMessage: String?
    @State private var notice: String?
    @State private var pending: PendingAction?

    @State private var editing = false
    @State private var form = LimitsForm()
    @State private var formStart = LimitsForm()

    private enum LinkState: Equatable {
        case loading
        case ready(String)
        case unavailable(String)
    }

    private struct PendingAction: Identifiable {
        enum Kind { case enable(Bool), reset, save(ClientChanges) }
        let id = UUID()
        let kind: Kind
        let title: String
        let message: String
        let confirm: String
        let destructive: Bool
    }

    var body: some View {
        Group {
            if let client = model.overview.xui?.clients?.first(where: { $0.id == clientID }) {
                content(client)
            } else {
                missing
            }
        }
        .frame(width: 540)
        .background(Theme.surface)
        .confirmationDialog(
            pending?.title ?? "",
            isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
            presenting: pending
        ) { action in
            Button(action.confirm, role: action.destructive ? .destructive : nil) {
                run(action)
            }
            Button("取消", role: .cancel) {}
        } message: { action in
            Text(action.message)
        }
    }

    // MARK: - Layout

    private func content(_ client: Client) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header(client)
                .padding(20)
            CardDivider()

            VStack(alignment: .leading, spacing: 22) {
                stats(client)
                subscription(client)
                management(client)
                if let errorMessage {
                    StatusBanner(
                        title: "操作没有完成",
                        message: errorMessage,
                        icon: "exclamationmark.triangle.fill",
                        tint: Theme.warning
                    )
                } else if let notice {
                    Label(notice, systemImage: "checkmark.circle.fill")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Theme.success)
                }
            }
            .padding(20)

            CardDivider()
            HStack {
                if working {
                    ProgressView()
                        .controlSize(.small)
                    Text("正在提交到面板…")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("完成") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .task(id: client.subId) { await loadLink(client) }
        .onAppear {
            resetForm(client)
            // Snapshot runs show the editor too, so its layout gets checked.
            if DevSnapshot.directory != nil { editing = true }
        }
    }

    private func header(_ client: Client) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(client.name)
                    .font(.system(size: 17, weight: .semibold))
                    .lineLimit(1)
                Text(subtitle(client))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 12)
            StatusPill(title: client.state.title, tint: client.state.swiftColor)
        }
    }

    private func stats(_ client: Client) -> some View {
        HStack(alignment: .top, spacing: 20) {
            detailStat(
                title: "已用",
                value: ByteFormat.string(client.used),
                detail: "↑ \(ByteFormat.string(client.up))  ↓ \(ByteFormat.string(client.down))"
            )
            StatDivider(height: 44)
            detailStat(
                title: "配额",
                value: (client.total ?? 0) > 0 ? ByteFormat.string(client.total) : "不限",
                detail: client.percent.map { "已用 \(Int($0.rounded()))%" }
            )
            StatDivider(height: 44)
            detailStat(title: "到期", value: expiryText(client), detail: client.expiryWarning)
        }
    }

    private func detailStat(title: String, value: String, detail: String?) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(Theme.label)
                .foregroundStyle(.secondary)
            Text(value)
                .font(Theme.number(19))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(detail ?? " ")
                .font(Theme.label)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 订阅

    private func subscription(_ client: Client) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("订阅")
            switch link {
            case .loading:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("正在读取面板的订阅设置…")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                }
                .frame(height: 40)
            case .unavailable(let reason):
                Text(reason)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            case .ready(let url):
                HStack(alignment: .top, spacing: 16) {
                    QRCodeView(text: url)
                        .frame(width: 120, height: 120)
                    VStack(alignment: .leading, spacing: 10) {
                        Text(url)
                            .font(.system(size: 12, design: .monospaced))
                            .textSelection(.enabled)
                            .lineLimit(4)
                            .fixedSize(horizontal: false, vertical: true)
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(url, forType: .string)
                            linkCopied = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { linkCopied = false }
                        } label: {
                            Label(linkCopied ? "已复制" : "复制订阅链接", systemImage: linkCopied ? "checkmark" : "doc.on.doc")
                        }
                        .controlSize(.small)
                    }
                }
            }
        }
    }

    private func loadLink(_ client: Client) async {
        guard client.subId?.isEmpty == false else {
            link = .unavailable("这个客户端没有订阅 ID，面板里为它生成一个后才会有订阅链接。")
            return
        }
        do {
            if let url = try await model.subscriptionLink(for: client) {
                link = .ready(url)
            } else {
                link = .unavailable("面板没有开启订阅服务。在 3X-UI 的「面板设置 → 订阅」里启用后即可在这里取得链接。")
            }
        } catch {
            link = .unavailable("读取订阅设置失败：\(XUIError.safeMessage(error))")
        }
    }

    // MARK: - 管理

    private func management(_ client: Client) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionTitle("管理")
                .padding(.bottom, 4)

            actionRow(title: "启用", detail: "停用后该客户端立即无法连接，数据与配额保留。") {
                Toggle("启用", isOn: Binding(
                    get: { client.enable != false },
                    set: { newValue in askToggle(client, enable: newValue) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .disabled(working)
            }

            CardDivider()

            actionRow(title: "配额与到期", detail: editing ? nil : limitsSummary(client)) {
                if !editing {
                    Button("编辑") {
                        resetForm(client)
                        editing = true
                    }
                    .controlSize(.small)
                    .disabled(working)
                }
            }
            if editing {
                limitsEditor(client)
                    .padding(.bottom, 12)
            }

            CardDivider()

            actionRow(title: "重置流量", detail: "把已用的上传与下载清零，配额和到期日不变；已停用的客户端会被面板自动重新启用。") {
                Button("重置…", role: .destructive) { askReset(client) }
                    .controlSize(.small)
                    .disabled(working)
            }
        }
    }

    private func actionRow<Trailing: View>(
        title: String,
        detail: String?,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                if let detail {
                    Text(detail)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            trailing()
        }
        .padding(.vertical, 10)
    }

    private func limitsEditor(_ client: Client) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text("配额")
                        .font(Theme.label)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        TextField("配额", value: $form.quotaGB, format: .number.precision(.fractionLength(0...2)))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 96)
                            .disabled(form.unlimited)
                            .multilineTextAlignment(.trailing)
                        Text("GB")
                            .font(.system(size: 12.5))
                            .foregroundStyle(.secondary)
                        Toggle("不限", isOn: $form.unlimited)
                            .toggleStyle(.checkbox)
                            .padding(.leading, 6)
                    }
                }
                GridRow {
                    Text("到期")
                        .font(Theme.label)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        DatePicker("到期日", selection: $form.expiry, displayedComponents: .date)
                            .labelsHidden()
                            .datePickerStyle(.field)
                            .disabled(form.neverExpires)
                        Toggle("永不过期", isOn: $form.neverExpires)
                            .toggleStyle(.checkbox)
                            .padding(.leading, 6)
                    }
                }
            }
            if let days = client.delayedStartDays {
                Text("当前设置为「首次使用后 \(days) 天到期」。只改配额不会影响它；改到期日会替换它。")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button("取消") {
                    editing = false
                    resetForm(client)
                }
                .controlSize(.small)
                Button("保存…") { askSave(client) }
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .disabled(working || changes(for: client).isEmpty || (!form.unlimited && form.quotaGB <= 0))
            }
        }
        .padding(14)
        .background(Theme.fill.opacity(0.6), in: RoundedRectangle(cornerRadius: Theme.controlRadius + 1, style: .continuous))
    }

    // MARK: - Confirmation

    private func askToggle(_ client: Client, enable: Bool) {
        pending = PendingAction(
            kind: .enable(enable),
            title: enable ? "启用「\(client.name)」？" : "停用「\(client.name)」？",
            message: enable
                ? "该客户端将恢复连接。"
                : "该客户端会立即断开且无法再连接，直到重新启用。已用流量和配额不受影响。",
            confirm: enable ? "启用" : "停用",
            destructive: !enable
        )
    }

    private func askReset(_ client: Client) {
        pending = PendingAction(
            kind: .reset,
            title: "重置「\(client.name)」的流量？",
            message: client.enable == false
                ? "已用的 \(ByteFormat.string(client.used)) 会清零，此操作无法撤销。面板会同时重新启用这个客户端。"
                : "已用的 \(ByteFormat.string(client.used)) 会清零，此操作无法撤销。",
            confirm: "重置流量",
            destructive: true
        )
    }

    private func askSave(_ client: Client) {
        let changes = changes(for: client)
        var lines: [String] = []
        if let total = changes.totalBytes {
            lines.append("配额：\(quotaText(client.total ?? 0)) → \(quotaText(total))")
        }
        if let expiry = changes.expiryTime {
            lines.append("到期：\(expiryText(client)) → \(expiry == 0 ? "永不过期" : DateFormats.string("yyyy年M月d日", Date(timeIntervalSince1970: Double(expiry) / 1000)))")
        }
        pending = PendingAction(
            kind: .save(changes),
            title: "修改「\(client.name)」？",
            message: lines.joined(separator: "\n"),
            confirm: "保存到面板",
            destructive: false
        )
    }

    private func run(_ action: PendingAction) {
        guard let client = model.overview.xui?.clients?.first(where: { $0.id == clientID }) else { return }
        working = true
        errorMessage = nil
        notice = nil
        Task {
            do {
                switch action.kind {
                case .enable(let enable):
                    try await model.updateClient(client, changes: ClientChanges(enable: enable))
                    notice = enable ? "已启用" : "已停用"
                case .reset:
                    try await model.resetTraffic(client)
                    notice = "流量已重置"
                case .save(let changes):
                    try await model.updateClient(client, changes: changes)
                    editing = false
                    notice = "已保存到面板"
                }
                if let updated = model.overview.xui?.clients?.first(where: { $0.id == clientID }) {
                    resetForm(updated)
                }
            } catch {
                errorMessage = XUIError.safeMessage(error)
            }
            working = false
        }
    }

    // MARK: - Form

    private struct LimitsForm: Equatable {
        var quotaGB: Double = 0
        var unlimited = true
        var expiry = Date()
        var neverExpires = true
    }

    private static let gib = 1_073_741_824.0

    private func resetForm(_ client: Client) {
        var next = LimitsForm()
        let total = client.total ?? 0
        next.unlimited = total <= 0
        next.quotaGB = total > 0 ? (Double(total) / Self.gib * 100).rounded() / 100 : 100
        if let date = client.expiryDate {
            next.expiry = date
            next.neverExpires = false
        } else {
            next.expiry = Calendar.current.date(byAdding: .day, value: 30, to: Date()) ?? Date()
            next.neverExpires = client.delayedStartDays == nil
        }
        form = next
        formStart = next
    }

    /// Only the fields the user actually touched, so saving a new quota never
    /// rewrites an expiry it only displayed.
    private func changes(for client: Client) -> ClientChanges {
        var changes = ClientChanges()
        if form.unlimited != formStart.unlimited || (!form.unlimited && form.quotaGB != formStart.quotaGB) {
            changes.totalBytes = form.unlimited ? 0 : Int((form.quotaGB * Self.gib).rounded())
        }
        let sameDay = Calendar.current.isDate(form.expiry, inSameDayAs: formStart.expiry)
        if form.neverExpires != formStart.neverExpires || (!form.neverExpires && !sameDay) {
            if form.neverExpires {
                changes.expiryTime = 0
            } else {
                // The end of the chosen day: "到期 11月30日" should still work on the 30th.
                let start = Calendar.current.startOfDay(for: form.expiry)
                let end = Calendar.current.date(byAdding: DateComponents(day: 1, second: -1), to: start) ?? form.expiry
                changes.expiryTime = Int(end.timeIntervalSince1970 * 1000)
            }
        }
        return changes
    }

    // MARK: - Text

    private func subtitle(_ client: Client) -> String {
        var parts: [String] = []
        if let email = client.email, !email.isEmpty, email != client.name { parts.append(email) }
        if let inbound = client.inbound, !inbound.isEmpty { parts.append(inbound) }
        if let proto = client.protocol, !proto.isEmpty { parts.append(proto.uppercased()) }
        return parts.joined(separator: " · ")
    }

    private func quotaText(_ bytes: Int) -> String {
        bytes > 0 ? ByteFormat.string(bytes) : "不限"
    }

    private func expiryText(_ client: Client) -> String {
        if let date = client.expiryDate { return DateFormats.string("yyyy年M月d日", date) }
        if let days = client.delayedStartDays { return "首次使用后 \(days) 天" }
        return "永不过期"
    }

    private func limitsSummary(_ client: Client) -> String {
        "配额 \(quotaText(client.total ?? 0)) · 到期 \(expiryText(client))"
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(Theme.heading)
    }

    private var missing: some View {
        VStack(spacing: 12) {
            Text("这个客户端已不在面板的列表中。")
                .font(Theme.body)
                .foregroundStyle(.secondary)
            Button("完成") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(40)
        .frame(maxWidth: .infinity)
    }
}

/// QR code for a link, drawn crisp at any size and always dark-on-white so a phone
/// camera reads it in dark mode too.
struct QRCodeView: View {
    let text: String

    var body: some View {
        Group {
            if let image = Self.image(for: text) {
                Image(nsImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .padding(8)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                            .strokeBorder(Theme.border, lineWidth: 1)
                    )
                    .accessibilityLabel("订阅链接二维码")
            } else {
                Theme.fill
            }
        }
    }

    private static func image(for text: String) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage,
              let cgImage = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: output.extent.width, height: output.extent.height))
    }
}
