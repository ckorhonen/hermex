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
            ZoraLoadingStateView(title: "Loading analytics...")
        } else if let errorMessage = viewModel.errorMessage, !viewModel.hasLoadedAnalytics {
            ZoraUnavailableStateView(
                title: "Could Not Load Analytics",
                systemImage: "exclamationmark.triangle",
                message: errorMessage,
                actionTitle: "Try Again"
            ) {
                Task { await loadInsights() }
            }
        } else if !viewModel.hasLoadedAnalytics {
            ZoraUnavailableStateView(
                title: "No Data",
                systemImage: "chart.bar",
                message: "Session usage data will appear here once you have conversations."
            )
        } else {
            ZoraScrollContent(spacing: 24) {
                timeframeControl

                AnalyticsSection(title: viewModel.periodTitle) {
                    LazyVGrid(columns: metricColumns, alignment: .leading, spacing: 12) {
                        ZoraMetricCard(
                            title: String(localized: "Sessions"),
                            value: "\(viewModel.sessionCount)",
                            systemImage: "bubble.left.and.bubble.right",
                            tint: ZoraBrand.selectionAccent
                        )
                        ZoraMetricCard(
                            title: String(localized: "Messages"),
                            value: formatTokens(viewModel.totalMessages),
                            systemImage: "text.bubble",
                            tint: ZoraBrand.foreground
                        )
                        ZoraMetricCard(
                            title: String(localized: "Input Tokens"),
                            value: formatTokens(viewModel.totalInputTokens),
                            systemImage: "arrow.down.circle",
                            tint: ZoraBrand.selectionAccent
                        )
                        ZoraMetricCard(
                            title: String(localized: "Output Tokens"),
                            value: formatTokens(viewModel.totalOutputTokens),
                            systemImage: "arrow.up.circle",
                            tint: ZoraBrand.foreground
                        )
                        ZoraMetricCard(
                            title: String(localized: "Total Tokens"),
                            value: formatTokens(viewModel.totalTokens),
                            systemImage: "sum",
                            tint: ZoraBrand.selectionAccent
                        )
                        ZoraMetricCard(
                            title: String(localized: "Estimated Cost"),
                            value: viewModel.estimatedCost.formattedCost(collapsingZeroCents: true),
                            systemImage: "dollarsign.circle",
                            tint: ZoraBrand.foreground
                        )
                    }
                }

                if !viewModel.modelBreakdowns.isEmpty {
                    AnalyticsSection(title: String(localized: "Models")) {
                        VStack(spacing: 0) {
                            ForEach(
                                Array(viewModel.modelBreakdowns.prefix(10).enumerated()),
                                id: \.offset
                            ) { index, model in
                                ModelBreakdownRow(model: model)
                                    .padding(.vertical, 10)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                if index < min(viewModel.modelBreakdowns.count, 10) - 1 {
                                    ZoraDivider()
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
                                    ZoraDivider()
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
                                ZoraDivider()
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
                            ForEach(
                                Array(viewModel.topSessions.prefix(10).enumerated()),
                                id: \.offset
                            ) { index, session in
                                topSessionRow(session)
                                    .padding(.vertical, 10)

                                if index < min(viewModel.topSessions.count, 10) - 1 {
                                    ZoraDivider()
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
            .refreshable {
                await loadInsights()
            }
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
            ZoraSectionHeader(title)

            content
        }
    }
}
