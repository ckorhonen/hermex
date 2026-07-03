import SwiftUI

private enum ChatAccessoryChrome {
    static let cornerRadius: CGFloat = 14
    static let insetCornerRadius: CGFloat = 12
    static let strokeWidth: CGFloat = 0.5
    static let increasedContrastStrokeWidth: CGFloat = 1

    static func fill(reduceTransparency: Bool) -> Color {
        reduceTransparency ? ZoraBrand.backgroundMid.opacity(0.90) : ZoraBrand.subtleFill
    }

    static func insetFill(reduceTransparency: Bool) -> Color {
        reduceTransparency ? ZoraBrand.backgroundMid.opacity(0.86) : ZoraBrand.paper.opacity(0.065)
    }

    static func stroke(colorSchemeContrast: ColorSchemeContrast) -> Color {
        colorSchemeContrast == .increased ? ZoraBrand.foreground.opacity(0.44) : ZoraBrand.surfaceHairline
    }

    static func insetStroke(colorSchemeContrast: ColorSchemeContrast) -> Color {
        colorSchemeContrast == .increased ? ZoraBrand.foreground.opacity(0.38) : ZoraBrand.surfaceHairline
    }

    static func lineWidth(colorSchemeContrast: ColorSchemeContrast) -> CGFloat {
        colorSchemeContrast == .increased ? increasedContrastStrokeWidth : strokeWidth
    }
}

private struct ChatAccessorySurfaceModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(
            cornerRadius: max(cornerRadius, ChatAccessoryChrome.cornerRadius),
            style: .continuous
        )

        content
            .background(ChatAccessoryChrome.fill(reduceTransparency: reduceTransparency), in: shape)
            .clipShape(shape)
            .overlay {
                shape
                    .stroke(
                        ChatAccessoryChrome.stroke(colorSchemeContrast: colorSchemeContrast),
                        lineWidth: ChatAccessoryChrome.lineWidth(colorSchemeContrast: colorSchemeContrast)
                    )
                    .allowsHitTesting(false)
            }
    }
}

private struct ChatAccessoryInsetModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: ChatAccessoryChrome.insetCornerRadius, style: .continuous)

        content
            .background(
                ChatAccessoryChrome.insetFill(reduceTransparency: reduceTransparency),
                in: shape
            )
            .overlay {
                shape
                    .stroke(
                        ChatAccessoryChrome.insetStroke(colorSchemeContrast: colorSchemeContrast),
                        lineWidth: ChatAccessoryChrome.lineWidth(colorSchemeContrast: colorSchemeContrast)
                    )
                    .allowsHitTesting(false)
            }
    }
}

extension View {
    func chatTimelineAccessorySurface(
        fallbackMaterial _: Material = .thinMaterial,
        cornerRadius: CGFloat = ChatAccessoryChrome.cornerRadius
    ) -> some View {
        modifier(ChatAccessorySurfaceModifier(
            cornerRadius: cornerRadius
        ))
    }

    func chatTimelineAccessoryInsetSurface() -> some View {
        modifier(ChatAccessoryInsetModifier())
    }
}
