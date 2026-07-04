import SwiftUI

struct ContextWindowIndicatorView: View {
    let snapshot: ContextWindowSnapshot?

    @Environment(\.colorScheme) private var colorScheme
    @State private var showPopover = false
    private let ringSize: CGFloat = 30
    private let tapTargetSize: CGFloat = 44

    var body: some View {
        if let snapshot, let percentage = snapshot.percentage {
            Button(action: { showPopover = true }) {
                ZStack {
                    Circle()
                        .stroke(trackColor, lineWidth: 3)
                        .frame(width: ringSize, height: ringSize)

                    Circle()
                        .trim(from: 0, to: CGFloat(min(percentage, 1.0)))
                        .stroke(
                            progressColor,
                            style: StrokeStyle(lineWidth: 3, lineCap: .round)
                        )
                        .frame(width: ringSize, height: ringSize)
                        .rotationEffect(.degrees(-90))

                    Text("\(Int(percentage * 100))")
                        .font(AppFont.monoDigit(style: .caption2, weight: .semibold))
                        .minimumScaleFactor(0.55)
                        .foregroundStyle(.primary)
                }
                .frame(width: ringSize, height: ringSize)
                .adaptiveGlass(
                    .regular,
                    isInteractive: true,
                    fallbackMaterial: .ultraThinMaterial,
                    in: Circle()
                )
                .frame(width: tapTargetSize, height: tapTargetSize)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showPopover) {
                ContextWindowPopover(snapshot: snapshot)
                    .presentationCompactAdaptation(.none)
                    .presentationBackground(.clear)
            }
        }
    }

    private var trackColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.16) : Color.black.opacity(0.12)
    }

    private var progressColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.92) : Color.black.opacity(0.82)
    }
}

private struct ContextWindowPopover: View {
    let snapshot: ContextWindowSnapshot
    private let popoverCornerRadius: CGFloat = 18

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(ContextWindowFormatter.tokensLabel(from: snapshot))
                .font(AppFont.monoDigit(style: .subheadline, weight: .semibold))

            Divider()

            ContextWindowInfoRow(
                label: String(localized: "Input"),
                value: ContextWindowFormatter.inputTokensLabel(from: snapshot)
            )
            ContextWindowInfoRow(
                label: String(localized: "Output"),
                value: ContextWindowFormatter.outputTokensLabel(from: snapshot)
            )
            ContextWindowInfoRow(
                label: String(localized: "Threshold"),
                value: ContextWindowFormatter.thresholdLabel(from: snapshot)
            )
            ContextWindowInfoRow(
                label: String(localized: "Cost"),
                value: ContextWindowFormatter.costLabel(from: snapshot)
            )
        }
        .padding()
        .frame(width: 220)
        .adaptiveGlass(
            .regular,
            fallbackMaterial: .regularMaterial,
            in: RoundedRectangle(cornerRadius: popoverCornerRadius, style: .continuous)
        )
        .clipShape(RoundedRectangle(cornerRadius: popoverCornerRadius, style: .continuous))
    }
}

private struct ContextWindowInfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(AppFont.caption())
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(AppFont.monoDigit(style: .caption, weight: .medium))
        }
    }
}
