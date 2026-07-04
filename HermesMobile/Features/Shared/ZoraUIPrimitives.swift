import SwiftUI

struct ZoraLoadingStateView: View {
    let title: String

    var body: some View {
        ProgressView {
            Text(title)
                .font(AppFont.subheadline())
                .foregroundStyle(ZoraBrand.secondaryForeground)
        }
        .tint(ZoraBrand.foreground)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel(title)
    }
}

struct ZoraUnavailableStateView: View {
    let title: String
    let systemImage: String
    let message: String
    let actionTitle: String?
    let action: (() -> Void)?

    init(
        title: String,
        systemImage: String,
        message: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.title = title
        self.systemImage = systemImage
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(message)
        } actions: {
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(ZoraSecondaryButtonStyle(cornerRadius: ZoraRadius.control))
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .foregroundStyle(ZoraBrand.foreground, ZoraBrand.secondaryForeground)
        .tint(ZoraBrand.foreground)
    }
}

struct ZoraScrollContent<Content: View>: View {
    let role: ZoraAdaptiveContentRole
    let alignment: HorizontalAlignment
    let spacing: CGFloat
    let horizontalPadding: CGFloat
    let topPadding: CGFloat
    let bottomPadding: CGFloat

    @ViewBuilder let content: Content

    init(
        role: ZoraAdaptiveContentRole = .readablePage,
        alignment: HorizontalAlignment = .leading,
        spacing: CGFloat = ZoraSpacing.lg,
        horizontalPadding: CGFloat = 20,
        topPadding: CGFloat = 18,
        bottomPadding: CGFloat = 32,
        @ViewBuilder content: () -> Content
    ) {
        self.role = role
        self.alignment = alignment
        self.spacing = spacing
        self.horizontalPadding = horizontalPadding
        self.topPadding = topPadding
        self.bottomPadding = bottomPadding
        self.content = content()
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: alignment, spacing: spacing) {
                content
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.top, topPadding)
            .padding(.bottom, bottomPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .zoraAdaptiveContentFrame(role)
        }
        .background(Color.clear)
    }
}

struct ZoraSectionHeader: View {
    let title: String
    let systemImage: String?
    let horizontalPadding: CGFloat

    init(_ title: String, systemImage: String? = nil, horizontalPadding: CGFloat = 4) {
        self.title = title
        self.systemImage = systemImage
        self.horizontalPadding = horizontalPadding
    }

    var body: some View {
        Group {
            if let systemImage {
                Label(title, systemImage: systemImage)
            } else {
                Text(title)
            }
        }
        .textCase(.uppercase)
        .font(AppFont.caption(weight: .semibold))
        .foregroundStyle(ZoraBrand.secondaryForeground)
        .padding(.horizontal, horizontalPadding)
        .accessibilityAddTraits(.isHeader)
    }
}

struct ZoraDivider: View {
    let leadingPadding: CGFloat
    let strength: ZoraDividerStrength

    init(leadingPadding: CGFloat = 0, strength: ZoraDividerStrength = .standard) {
        self.leadingPadding = leadingPadding
        self.strength = strength
    }

    var body: some View {
        Rectangle()
            .fill(strength.color)
            .frame(height: strength.height)
            .padding(.leading, leadingPadding)
            .allowsHitTesting(false)
    }
}

enum ZoraDividerStrength {
    case standard
    case strong

    var color: Color {
        switch self {
        case .standard:
            ZoraBrand.listDivider
        case .strong:
            ZoraBrand.listDividerStrong
        }
    }

    var height: CGFloat {
        switch self {
        case .standard:
            0.65
        case .strong:
            1
        }
    }
}

enum ZoraStatusTone {
    case accent
    case success
    case warning
    case danger
    case neutral
    case custom(Color)

    var color: Color {
        switch self {
        case .accent:
            ZoraBrand.selectionAccent
        case .success:
            ZoraBrand.success
        case .warning:
            ZoraBrand.warning
        case .danger:
            ZoraBrand.danger
        case .neutral:
            ZoraBrand.secondaryForeground
        case let .custom(color):
            color
        }
    }
}

struct ZoraStatusPill: View {
    let text: String
    let tone: ZoraStatusTone

    init(_ text: String, tone: ZoraStatusTone = .neutral) {
        self.text = text
        self.tone = tone
    }

    init(text: String, color: Color) {
        self.text = text
        self.tone = .custom(color)
    }

    var body: some View {
        let color = tone.color

        Text(text)
            .font(AppFont.caption2(weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.12), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(color.opacity(0.20), lineWidth: 0.5)
                    .allowsHitTesting(false)
            }
            .lineLimit(1)
            .accessibilityLabel(text)
    }
}

struct StatusBadge: View {
    let text: String
    let color: Color

    var body: some View {
        ZoraStatusPill(text: text, color: color)
    }
}

struct ZoraCard<Content: View>: View {
    let level: ZoraSurfaceLevel
    let cornerRadius: CGFloat
    let padding: CGFloat
    let minHeight: CGFloat?

    @ViewBuilder let content: Content

    init(
        level: ZoraSurfaceLevel = .subtle,
        cornerRadius: CGFloat = 18,
        padding: CGFloat = 14,
        minHeight: CGFloat? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.level = level
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.minHeight = minHeight
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
            .zoraSurface(level, cornerRadius: cornerRadius)
    }
}

struct ZoraMetricCard: View {
    let title: String
    let value: String
    let systemImage: String
    let tint: Color

    var body: some View {
        ZoraCard(minHeight: 128) {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: systemImage)
                    .font(AppFont.title3(weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 36, height: 36)
                    .background(tint.opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(AppFont.caption())
                        .foregroundStyle(ZoraBrand.secondaryForeground)
                        .lineLimit(2)

                    Text(value)
                        .font(AppFont.title3(weight: .semibold))
                        .foregroundStyle(ZoraBrand.foreground)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
