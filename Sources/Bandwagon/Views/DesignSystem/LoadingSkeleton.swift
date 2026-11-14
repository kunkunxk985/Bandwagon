import SwiftUI

/// Placeholder blocks that mirror real panels while data is in flight. Motion stays
/// quiet: a soft opacity pulse, or nothing when Reduce Motion is on.
private struct SkeletonBlock: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dimmed = false

    var width: CGFloat? = nil
    var height: CGFloat = 12
    var cornerRadius: CGFloat = Theme.controlRadius

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Theme.fill)
            .frame(width: width, height: height)
            .opacity(reduceMotion ? 1 : (dimmed ? 0.42 : 0.88))
            .onAppear { beginPulse() }
            .accessibilityHidden(true)
    }

    private func beginPulse() {
        guard !reduceMotion else { return }
        withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
            dimmed = true
        }
    }
}

/// Ring and stat row shaped like `UsageHero`, for overview and VPS loading.
struct UsageHeroSkeleton: View {
    var body: some View {
        HStack(alignment: .center, spacing: 24) {
            Circle()
                .stroke(Theme.fill, lineWidth: 9)
                .frame(width: 112, height: 112)
                .overlay {
                    SkeletonBlock(width: 40, height: 14, cornerRadius: 4)
                }

            VStack(alignment: .leading, spacing: 8) {
                SkeletonBlock(width: 52, height: 10)
                SkeletonBlock(width: 120, height: 28, cornerRadius: 5)
                SkeletonBlock(width: 88, height: 11)
            }
            .layoutPriority(1)

            Spacer(minLength: 16)

            HStack(spacing: 0) {
                metricColumn
                StatDivider(height: 40)
                metricColumn
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("正在加载用量")
    }

    private var metricColumn: some View {
        VStack(alignment: .leading, spacing: 6) {
            SkeletonBlock(width: 36, height: 10)
            SkeletonBlock(width: 64, height: 20, cornerRadius: 5)
            SkeletonBlock(width: 48, height: 10)
        }
        .frame(minWidth: 96, alignment: .leading)
        .padding(.horizontal, 20)
    }
}

/// Overview body while Bandwagon is still answering.
struct OverviewLoadingSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.gap) {
            Panel(padding: 24) {
                UsageHeroSkeleton()
                SkeletonBlock(height: 36, cornerRadius: Theme.controlRadius)
                    .padding(.top, 4)
            }

            HStack(alignment: .top, spacing: Theme.gap) {
                miniPanel
                miniPanel
            }

            Panel(padding: 20) {
                VStack(alignment: .leading, spacing: 16) {
                    SkeletonBlock(width: 48, height: 13, cornerRadius: 4)
                    HStack(alignment: .top, spacing: 20) {
                        ForEach(0..<3, id: \.self) { _ in
                            VStack(alignment: .leading, spacing: 8) {
                                SkeletonBlock(width: 28, height: 10)
                                SkeletonBlock(width: 72, height: 18, cornerRadius: 5)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
        }
    }

    private var miniPanel: some View {
        Panel(padding: 20, fillsHeight: true) {
            VStack(alignment: .leading, spacing: 14) {
                SkeletonBlock(width: 88, height: 13, cornerRadius: 4)
                SkeletonBlock(height: 116, cornerRadius: Theme.controlRadius)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Clients list while 3X-UI is still answering.
struct ClientsLoadingSkeleton: View {
    private let rowCount = 9

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.gap) {
            Panel(padding: 18) {
                HStack(spacing: 20) {
                    ForEach(0..<4, id: \.self) { _ in
                        VStack(alignment: .leading, spacing: 6) {
                            SkeletonBlock(width: 40, height: 10)
                            SkeletonBlock(width: 36, height: 20, cornerRadius: 5)
                        }
                    }
                }
                CardDivider()
                    .padding(.vertical, 14)
                SkeletonBlock(height: 28, cornerRadius: Theme.controlRadius)
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.bottom, 2)

            Panel(padding: 0) {
                ClientColumnLayout {
                    SkeletonBlock(width: 28, height: 10, cornerRadius: 3)
                    SkeletonBlock(width: 48, height: 10, cornerRadius: 3)
                    SkeletonBlock(width: 56, height: 10, cornerRadius: 3)
                    SkeletonBlock(width: 28, height: 10, cornerRadius: 3)
                    SkeletonBlock(width: 28, height: 10, cornerRadius: 3)
                    SkeletonBlock(width: 36, height: 10, cornerRadius: 3)
                    Color.clear.frame(width: 24, height: 1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, CGFloat(ClientColumnShare.inset))
                .padding(.vertical, 11)
                .background(Theme.surface)
                .overlay(alignment: .bottom) { CardDivider() }

                VStack(spacing: 0) {
                    ForEach(0..<rowCount, id: \.self) { index in
                        if index > 0 {
                            CardDivider()
                                .padding(.leading, 18)
                        }
                        clientRow
                    }
                }
                .padding(.bottom, 6)
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous))
            .padding(.horizontal, Theme.pagePadding)
            .padding(.bottom, Theme.pagePadding)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("正在加载客户端列表")
    }

    private var clientRow: some View {
        ClientColumnLayout {
            SkeletonBlock(width: 44, height: 22, cornerRadius: Theme.controlRadius)
                .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: 5) {
                SkeletonBlock(width: 96, height: 12)
                SkeletonBlock(width: 72, height: 10)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            SkeletonBlock(width: 120, height: 11)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) {
                SkeletonBlock(height: 6, cornerRadius: 3)
                    .frame(minWidth: 28, maxWidth: .infinity)
                SkeletonBlock(width: 48, height: 12)
                SkeletonBlock(width: 40, height: 12)
                SkeletonBlock(width: 40, height: 12)
            }
            SkeletonBlock(width: 36, height: 12)
                .frame(maxWidth: .infinity, alignment: .leading)
            SkeletonBlock(width: 72, height: 12)
                .frame(maxWidth: .infinity, alignment: .leading)
            Color.clear.frame(width: 24, height: 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, CGFloat(ClientColumnShare.inset))
        .padding(.vertical, 11)
    }
}

/// VPS page while Bandwagon is still answering.
struct VPSLoadingSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.gap) {
            Panel(padding: 24) {
                UsageHeroSkeleton()
            }
            Panel(padding: 20) {
                VStack(alignment: .leading, spacing: 14) {
                    SkeletonBlock(width: 64, height: 13, cornerRadius: 4)
                    SkeletonBlock(height: 200, cornerRadius: Theme.controlRadius)
                }
            }
            systemSkeleton
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("正在加载服务器信息")
    }

    private var systemSkeleton: some View {
        Panel(padding: 0) {
            SkeletonBlock(width: 72, height: 13, cornerRadius: 4)
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 4)

            ForEach(0..<4, id: \.self) { index in
                if index > 0 {
                    CardDivider()
                        .padding(.horizontal, 20)
                }
                HStack(alignment: .top, spacing: 20) {
                    specCell
                    specCell
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
            }
        }
    }

    private var specCell: some View {
        VStack(alignment: .leading, spacing: 8) {
            SkeletonBlock(width: 36, height: 10)
            SkeletonBlock(width: 100, height: 16, cornerRadius: 4)
            SkeletonBlock(height: 4, cornerRadius: 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Subscription block in the client detail sheet while panel settings load.
struct SubscriptionLinkSkeleton: View {
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            SkeletonBlock(width: 120, height: 120, cornerRadius: Theme.controlRadius)
            VStack(alignment: .leading, spacing: 10) {
                SkeletonBlock(width: 160, height: 11)
                SkeletonBlock(height: 52, cornerRadius: Theme.controlRadius)
                SkeletonBlock(width: 72, height: 24, cornerRadius: Theme.controlRadius)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("正在加载订阅链接")
    }
}
