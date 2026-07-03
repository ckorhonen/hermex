import SwiftUI

private struct ChatTimelineAccessorySurfaceModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    let fallbackMaterial: Material
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: max(cornerRadius, 16), style: .continuous)

        content
            .background(backgroundFill, in: shape)
            .adaptiveGlass(
                .regular,
                isInteractive: false,
                fallbackMaterial: fallbackMaterial,
                in: shape
            )
            .clipShape(shape)
            .overlay {
                shape
                    .stroke(strokeColor, lineWidth: colorSchemeContrast == .increased ? 1 : 0.8)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(ZoraBrand.accessoryAccent)
                    .frame(width: 3)
                    .padding(.vertical, 11)
                    .padding(.leading, 7)
                    .allowsHitTesting(false)
            }
    }

    private var backgroundFill: Color {
        reduceTransparency ? ZoraBrand.backgroundMid.opacity(0.90) : ZoraBrand.accessoryFill
    }

    private var strokeColor: Color {
        colorSchemeContrast == .increased ? ZoraBrand.foreground.opacity(0.44) : ZoraBrand.accessoryStroke
    }
}

private struct ChatTimelineAccessoryInsetSurfaceModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    private var backgroundColor: Color {
        if reduceTransparency {
            return ZoraBrand.backgroundMid.opacity(0.86)
        }

        return ZoraBrand.accessoryFillInset
    }

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)

        content
            .background(
                backgroundColor,
                in: shape
            )
            .overlay {
                shape
                    .stroke(
                        colorSchemeContrast == .increased ? ZoraBrand.foreground.opacity(0.38) : ZoraBrand.surfaceHairline,
                        lineWidth: colorSchemeContrast == .increased ? 1 : 0.65
                    )
                    .allowsHitTesting(false)
            }
    }
}

extension View {
    func chatTimelineAccessorySurface(
        fallbackMaterial: Material,
        cornerRadius: CGFloat
    ) -> some View {
        modifier(ChatTimelineAccessorySurfaceModifier(
            fallbackMaterial: fallbackMaterial,
            cornerRadius: cornerRadius
        ))
    }

    func chatTimelineAccessoryInsetSurface() -> some View {
        modifier(ChatTimelineAccessoryInsetSurfaceModifier())
    }
}
