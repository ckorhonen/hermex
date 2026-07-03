import SwiftUI

struct InsightsView: View {
    let server: URL
    let onAPIError: (Error) -> Void

    @State private var viewModel: InsightsViewModel

    init(server: URL, onAPIError: @escaping (Error) -> Void) {
        self.server = server
        self.onAPIError = onAPIError
        _viewModel = State(initialValue: InsightsViewModel(server: server))
    }

    var body: some View {
        content
            .navigationTitle("Usage Analytics")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await loadInsights() }
                    } label: {
                        if viewModel.isLoading {
                            ProgressView()
                        } else {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                    }
                    .disabled(viewModel.isLoading)
                }
            }
            .task(id: viewModel.selectedTimeframe) {
                await loadInsights()
            }
            .zoraBrandedScreen()
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && !viewModel.hasLoadedAnalytics {
            ProgressView("Loading analytics...")
        } else if let errorMessage = viewModel.errorMessage, !viewModel.hasLoadedAnalytics {
            ContentUnavailableView {
                Label("Could Not Load Analytics", systemImage: "exclamationmark.triangle")
            } description: {
                Text(errorMessage)
            } actions: {
                Button("Try Again") {
                    Task { await loadInsights() }
                }
            }
        } else if !viewModel.hasLoadedAnalytics {
            ContentUnavailableView {
                Label("No Data", systemImage: "chart.bar")
            } description: {
                Text("Session usage data will appear here once you have conversations.")
            }
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    timeframeControl

                    AnalyticsSection(title: viewModel.periodTitle) {
                        LazyVGrid(columns: metricColumns, alignment: .leading, spacing: 12) {
                            AnalyticsCard(title: String(localized: "Sessions"), value: "\(viewModel.sessionCount)", icon: "bubble.left.and.bubble.right", color: ZoraBrand.selectionAccent)
                            AnalyticsCard(title: String(localized: "Messages"), value: formatTokens(viewModel.totalMessages), icon: "text.bubble", color: ZoraBrand.foreground)
                            AnalyticsCard(title: String(localized: "Input Tokens"), value: formatTokens(viewModel.totalInputTokens), icon: "arrow.down.circle", color: ZoraBrand.selectionAccent)
                            AnalyticsCard(title: String(localized: "Output Tokens"), value: formatTokens(viewModel.totalOutputTokens), icon: "arrow.up.circle", color: ZoraBrand.foreground)
                            AnalyticsCard(title: String(localized: "Total Tokens"), value: formatTokens(viewModel.totalTokens), icon: "sum", color: ZoraBrand.selectionAccent)
                            AnalyticsCard(title: String(localized: "Estimated Cost"), value: viewModel.estimatedCost.formattedCost(collapsingZeroCents: true), icon: "dollarsign.circle", color: ZoraBrand.foreground)
                        }
                    }

                    if !viewModel.modelBreakdowns.isEmpty {
                        AnalyticsSection(title: String(localized: "Models")) {
                            VStack(spacing: 0) {
                                ForEach(Array(viewModel.modelBreakdowns.prefix(10).enumerated()), id: \.offset) { index, model in
                                    ModelBreakdownRow(model: model)
                                        .padding(.vertical, 10)
                                        .frame(maxWidth: .infinity, alignment: .leading)

                                    if index < min(viewModel.modelBreakdowns.count, 10) - 1 {
                                        Divider().overlay(ZoraBrand.listDivider)
                                    }
                                }
                            }
                        }
                    }

                    if !viewModel.recentDailyTokens.isEmpty {
                        AnalyticsSection(title: String(localized: "Recent Daily Tokens")) {
                            VStack(spacing: 0) {
                                ForEach(Array(viewModel.recentDailyTokens.enumerated()), id: \.offset) { index, day in
                                    DailyTokenRow(day: day)
                                        .padding(.vertical, 10)
                                        .frame(maxWidth: .infinity, alignment: .leading)

                                    if index < viewModel.recentDailyTokens.count - 1 {
                                        Divider().overlay(ZoraBrand.listDivider)
                                    }
                                }
                            }
                        }
                    }

                    if viewModel.peakDay != nil || viewModel.peakHour != nil {
                        AnalyticsSection(title: String(localized: "Activity")) {
                            VStack(spacing: 0) {
                                if let peakDay = viewModel.peakDay {
                                    ActivitySummaryRow(
                                        icon: "calendar",
                                        title: String(localized: "Peak Day"),
                                        value: peakDay.day ?? String(localized: "Unknown"),
                                        detail: String(localized: "\(peakDay.sessions ?? 0) sessions")
                                    )
                                    .padding(.vertical, 10)
                                }

                                if viewModel.peakDay != nil, viewModel.peakHour != nil {
                                    Divider().overlay(ZoraBrand.listDivider)
                                }

                                if let peakHour = viewModel.peakHour {
                                    ActivitySummaryRow(
                                        icon: "clock",
                                        title: String(localized: "Peak Hour"),
                                        value: formatHour(peakHour.hour),
                                        detail: String(localized: "\(peakHour.sessions ?? 0) sessions")
                                    )
                                    .padding(.vertical, 10)
                                }
                            }
                        }
                    }

                    if !viewModel.topSessions.isEmpty {
                        AnalyticsSection(title: String(localized: "Top Sessions")) {
                            VStack(spacing: 0) {
                                ForEach(Array(viewModel.topSessions.prefix(10).enumerated()), id: \.offset) { index, session in
                                    topSessionRow(session)
                                        .padding(.vertical, 10)

                                    if index < min(viewModel.topSessions.count, 10) - 1 {
                                        Divider().overlay(ZoraBrand.listDivider)
                                    }
                                }
                            }
                        }
                    }

                    Text(viewModel.sourceDescription)
                        .font(AppFont.caption())
                        .foregroundStyle(ZoraBrand.secondaryForeground)
                        .padding(.horizontal, 4)
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 32)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .refreshable {
                await loadInsights()
            }
            .background(Color.clear)
        }
    }

    private var metricColumns: [GridItem] {
        [
            GridItem(.flexible(), spacing: 12, alignment: .top),
            GridItem(.flexible(), spacing: 12, alignment: .top)
        ]
    }

    private var timeframeControl: some View {
        Picker("Timeframe", selection: $viewModel.selectedTimeframe) {
            ForEach(AnalyticsTimeframe.allCases) { timeframe in
                Text(timeframe.title).tag(timeframe)
            }
        }
        .pickerStyle(.segmented)
        .padding(4)
        .background(ZoraBrand.subtleFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(ZoraBrand.surfaceHairline, lineWidth: 0.75)
                .allowsHitTesting(false)
        }
    }

    private func topSessionRow(_ session: SessionSummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(session.title ?? String(localized: "Untitled Session"))
                .font(AppFont.subheadline(weight: .medium))
                .foregroundStyle(ZoraBrand.foreground)
                .lineLimit(1)

            HStack(spacing: 12) {
                let input = session.inputTokens ?? 0
                let output = session.outputTokens ?? 0
                let total = input + output

                Text("\(formatTokens(total)) tokens")
                    .font(AppFont.caption(weight: .semibold))
                    .foregroundStyle(ZoraBrand.secondaryForeground)

                if let cost = session.estimatedCost, cost > 0 {
                    Text(cost.formattedCost())
                        .font(AppFont.caption())
                        .foregroundStyle(ZoraBrand.secondaryForeground)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func loadInsights() async {
        await viewModel.load()

        if let lastError = viewModel.lastError {
            onAPIError(lastError)
        }
    }

    private func formatTokens(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private func formatHour(_ value: Int?) -> String {
        guard let value else { return String(localized: "Unknown") }
        return "\(String(format: "%02d", value)):00"
    }
}

private struct AnalyticsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .textCase(.uppercase)
                .font(AppFont.caption(weight: .semibold))
                .foregroundStyle(ZoraBrand.secondaryForeground)
                .padding(.horizontal, 4)

            content
        }
    }
}

private struct AnalyticsCard: View {
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)

        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: icon)
                .font(AppFont.title3(weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 36, height: 36)
                .background(color.opacity(0.12), in: Circle())

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
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 128, alignment: .topLeading)
        .background(ZoraBrand.subtleFill, in: shape)
        .overlay {
            shape
                .stroke(
                    colorSchemeContrast == .increased ? ZoraBrand.foreground.opacity(0.34) : ZoraBrand.surfaceHairline,
                    lineWidth: colorSchemeContrast == .increased ? 1 : 0.75
                )
                .allowsHitTesting(false)
        }
        .accessibilityElement(children: .combine)
    }
}
