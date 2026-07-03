import Foundation

struct CronJobsResponse: Decodable, Equatable {
    let jobs: [CronJob]?
}

struct CronMutationResponse: Decodable, Equatable {
    let ok: Bool?
    let job: CronJob?
    let error: String?
}

struct CronStatusResponse: Decodable, Equatable {
    let jobId: String?
    let running: Bool?
    let elapsed: Double?
    let runningJobs: [String: Double]?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case jobId
        case running
        case elapsed
        case error
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        jobId = try container.decodeIfPresent(String.self, forKey: .jobId)
        elapsed = try container.decodeFlexibleDoubleIfPresent(forKey: .elapsed)
        error = try container.decodeIfPresent(String.self, forKey: .error)

        running = (try? container.decodeIfPresent(Bool.self, forKey: .running)) ?? nil
        runningJobs = (try? container.decodeIfPresent([String: Double].self, forKey: .running)) ?? nil
    }
}

struct CronRecentResponse: Decodable, Equatable {
    let completions: [CronRecentCompletion]?
    let since: Double?
}

struct CronRecentCompletion: Decodable, Equatable, Identifiable {
    var id: String {
        "\(jobId ?? "completion")-\(completedAt ?? 0)"
    }

    let jobId: String?
    let name: String?
    let status: String?
    let completedAt: Double?
    let toastNotifications: Bool?
    let sessionId: String?
    let messageCount: Int?

    enum CodingKeys: String, CodingKey {
        case jobId
        case name
        case status
        case completedAt
        case toastNotifications
        case sessionId
        case messageCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        jobId = container.decodeLossyStringIfPresent(forKey: .jobId)
        name = container.decodeLossyStringIfPresent(forKey: .name)
        status = container.decodeLossyStringIfPresent(forKey: .status)
        completedAt = container.decodeLossyDoubleIfPresent(forKey: .completedAt)
        toastNotifications = container.decodeLossyBoolIfPresent(forKey: .toastNotifications)
        sessionId = container.decodeLossyStringIfPresent(forKey: .sessionId)
        messageCount = container.decodeLossyIntIfPresent(forKey: .messageCount)
    }

    var relatedSession: CronRelatedSession? {
        CronRelatedSession(sessionId: sessionId, title: name, messageCount: messageCount)
    }
}

struct CronRunHistoryResponse: Decodable, Equatable {
    let jobId: String?
    let runs: [CronRunHistoryItem]?
    let total: Int?
    let offset: Int?

    enum CodingKeys: String, CodingKey {
        case jobId
        case runs
        case total
        case offset
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        jobId = container.decodeLossyStringIfPresent(forKey: .jobId)
        runs = (try? container.decodeIfPresent([CronRunHistoryItem].self, forKey: .runs)) ?? nil
        total = container.decodeLossyIntIfPresent(forKey: .total)
        offset = container.decodeLossyIntIfPresent(forKey: .offset)
    }
}

struct CronRunHistoryItem: Decodable, Equatable, Identifiable {
    var id: String {
        if let filename, !filename.isEmpty {
            return filename
        }

        return "run-\(modified.map { String($0) } ?? "unknown")-\(size.map { String($0) } ?? "unknown")"
    }

    let filename: String?
    let size: Int?
    let modified: Double?
    let usage: CronRunUsage?

    enum CodingKeys: String, CodingKey {
        case filename
        case size
        case modified
        case usage
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        filename = container.decodeLossyStringIfPresent(forKey: .filename)
        size = container.decodeLossyIntIfPresent(forKey: .size)
        modified = container.decodeLossyDoubleIfPresent(forKey: .modified)
        usage = (try? container.decodeIfPresent(CronRunUsage.self, forKey: .usage)) ?? nil
    }
}

struct CronRunUsage: Decodable, Equatable {
    let inputTokens: Int?
    let outputTokens: Int?
    let totalTokens: Int?
    let estimatedCostUSD: Double?
    let durationSeconds: Double?
    let model: String?
    let provider: String?

    enum CodingKeys: String, CodingKey {
        case inputTokens
        case outputTokens
        case totalTokens
        case estimatedCostUSD = "estimatedCostUsd"
        case estimatedCostUSDSnake = "estimated_cost_usd"
        case durationSeconds
        case model
        case provider
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        inputTokens = container.decodeLossyIntIfPresent(forKey: .inputTokens)
        outputTokens = container.decodeLossyIntIfPresent(forKey: .outputTokens)
        totalTokens = container.decodeLossyIntIfPresent(forKey: .totalTokens)
        estimatedCostUSD = container.decodeLossyDoubleIfPresent(forKey: .estimatedCostUSD)
            ?? container.decodeLossyDoubleIfPresent(forKey: .estimatedCostUSDSnake)
        durationSeconds = container.decodeLossyDoubleIfPresent(forKey: .durationSeconds)
        model = container.decodeLossyStringIfPresent(forKey: .model)
        provider = container.decodeLossyStringIfPresent(forKey: .provider)
    }
}

struct CronRelatedSession: Equatable, Identifiable {
    var id: String { sessionId }

    let sessionId: String
    let title: String?
    let messageCount: Int?

    init?(sessionId: String?, title: String?, messageCount: Int?) {
        let trimmedSessionId = sessionId?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmedSessionId, !trimmedSessionId.isEmpty else { return nil }
        self.sessionId = trimmedSessionId
        self.title = Self.nonEmpty(title)
        self.messageCount = messageCount
    }

    var displayTitle: String {
        title ?? String(localized: "Related Chat")
    }

    func sessionSummary(profile: String? = nil) -> SessionSummary {
        SessionSummary(
            sessionId: sessionId,
            title: displayTitle,
            messageCount: messageCount,
            profile: profile,
            sourceTag: "cron",
            sessionSource: "cron",
            sourceLabel: "cron"
        )
    }

    private static func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}

struct CronJob: Decodable, Equatable, Identifiable {
    var id: String {
        jobId ?? name ?? UUID().uuidString
    }

    let jobId: String?
    let name: String?
    let prompt: String?
    let schedule: CronSchedule?
    let scheduleDisplay: String?
    let enabled: Bool?
    let state: String?
    let nextRunAt: CronDateValue?
    let lastRunAt: CronDateValue?
    let lastStatus: String?
    let lastError: String?
    let lastDeliveryError: String?
    let repeatInfo: CronRepeat?
    let deliver: String?
    let skills: [String]?
    let model: String?
    let provider: String?
    let profile: String?
    let ownerProfile: String?
    let readOnly: Bool?
    let noAgent: Bool?
    let script: String?
    let workdir: String?
    let toastNotifications: Bool?
    let relatedSessionId: String?
    let relatedSessionTitle: String?
    let relatedSessionMessageCount: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case jobId
        case name
        case prompt
        case schedule
        case scheduleDisplay
        case enabled
        case state
        case nextRunAt
        case lastRunAt
        case lastStatus
        case lastError
        case lastDeliveryError
        case repeatInfo = "repeat"
        case deliver
        case skills
        case model
        case provider
        case profile
        case ownerProfile
        case readOnly
        case noAgent
        case script
        case workdir
        case toastNotifications
        case sessionId
        case latestSessionId
        case lastSessionId
        case relatedSessionId
        case sessionTitle
        case latestSessionTitle
        case lastSessionTitle
        case relatedSessionTitle
        case messageCount
        case latestSessionMessageCount
        case lastSessionMessageCount
        case relatedSessionMessageCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        jobId = container.decodeLossyStringIfPresent(forKey: .id)
            ?? container.decodeLossyStringIfPresent(forKey: .jobId)
        name = container.decodeLossyStringIfPresent(forKey: .name)
        prompt = container.decodeLossyStringIfPresent(forKey: .prompt)
        schedule = (try? container.decodeIfPresent(CronSchedule.self, forKey: .schedule)) ?? nil
        scheduleDisplay = container.decodeLossyStringIfPresent(forKey: .scheduleDisplay)
        enabled = container.decodeLossyBoolIfPresent(forKey: .enabled)
        state = container.decodeLossyStringIfPresent(forKey: .state)
        nextRunAt = (try? container.decodeIfPresent(CronDateValue.self, forKey: .nextRunAt)) ?? nil
        lastRunAt = (try? container.decodeIfPresent(CronDateValue.self, forKey: .lastRunAt)) ?? nil
        lastStatus = container.decodeLossyStringIfPresent(forKey: .lastStatus)
        lastError = container.decodeLossyStringIfPresent(forKey: .lastError)
        lastDeliveryError = container.decodeLossyStringIfPresent(forKey: .lastDeliveryError)
        repeatInfo = (try? container.decodeIfPresent(CronRepeat.self, forKey: .repeatInfo)) ?? nil
        deliver = container.decodeLossyStringIfPresent(forKey: .deliver)
        skills = (try? container.decodeIfPresent([String].self, forKey: .skills)) ?? nil
        model = container.decodeLossyStringIfPresent(forKey: .model)
        provider = container.decodeLossyStringIfPresent(forKey: .provider)
        profile = container.decodeLossyStringIfPresent(forKey: .profile)
        ownerProfile = container.decodeLossyStringIfPresent(forKey: .ownerProfile)
        readOnly = container.decodeLossyBoolIfPresent(forKey: .readOnly)
        noAgent = container.decodeLossyBoolIfPresent(forKey: .noAgent)
        script = container.decodeLossyStringIfPresent(forKey: .script)
        workdir = container.decodeLossyStringIfPresent(forKey: .workdir)
        toastNotifications = container.decodeLossyBoolIfPresent(forKey: .toastNotifications)
        relatedSessionId = container.decodeLossyStringIfPresent(forKey: .relatedSessionId)
            ?? container.decodeLossyStringIfPresent(forKey: .sessionId)
            ?? container.decodeLossyStringIfPresent(forKey: .latestSessionId)
            ?? container.decodeLossyStringIfPresent(forKey: .lastSessionId)
        relatedSessionTitle = container.decodeLossyStringIfPresent(forKey: .relatedSessionTitle)
            ?? container.decodeLossyStringIfPresent(forKey: .sessionTitle)
            ?? container.decodeLossyStringIfPresent(forKey: .latestSessionTitle)
            ?? container.decodeLossyStringIfPresent(forKey: .lastSessionTitle)
        relatedSessionMessageCount = container.decodeLossyIntIfPresent(forKey: .relatedSessionMessageCount)
            ?? container.decodeLossyIntIfPresent(forKey: .messageCount)
            ?? container.decodeLossyIntIfPresent(forKey: .latestSessionMessageCount)
            ?? container.decodeLossyIntIfPresent(forKey: .lastSessionMessageCount)
    }

    var displayName: String {
        if let name, !name.isEmpty {
            return name
        }

        if let scheduleText, !scheduleText.isEmpty {
            return scheduleText
        }

        return String(localized: "Untitled Task")
    }

    var scheduleText: String? {
        scheduleDisplay ?? schedule?.displayText
    }

    var relatedSession: CronRelatedSession? {
        CronRelatedSession(
            sessionId: relatedSessionId,
            title: relatedSessionTitle,
            messageCount: relatedSessionMessageCount
        )
    }

    var editableScheduleText: String? {
        schedule?.expression ?? schedule?.expr ?? schedule?.runAt ?? schedule?.every ?? scheduleDisplay
    }

    var status: CronJobStatus {
        if isRecurring,
           repeatInfo?.times == nil,
           enabled == false,
           state == "completed",
           nextRunAt == nil {
            return .needsAttention
        }

        if isRecurring,
           nextRunAt == nil,
           state == "error" || lastStatus == "error" {
            return .needsAttention
        }

        if state == "paused" {
            return .paused
        }

        if enabled == false {
            return .off
        }

        if lastStatus == "error" {
            return .error
        }

        return .active
    }

    private var isRecurring: Bool {
        schedule?.kind == "cron" || schedule?.kind == "interval"
    }
}

struct CronSchedule: Decodable, Equatable {
    let kind: String?
    let expression: String?
    let expr: String?
    let runAt: String?
    let every: String?

    enum CodingKeys: String, CodingKey {
        case kind
        case expression
        case expr
        case runAt
        case every
    }

    init(from decoder: Decoder) throws {
        if let container = try? decoder.singleValueContainer(),
           let value = try? container.decode(String.self) {
            kind = nil
            expression = value
            expr = nil
            runAt = nil
            every = nil
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = container.decodeLossyStringIfPresent(forKey: .kind)
        expression = container.decodeLossyStringIfPresent(forKey: .expression)
        expr = container.decodeLossyStringIfPresent(forKey: .expr)
        runAt = container.decodeLossyStringIfPresent(forKey: .runAt)
        every = container.decodeLossyStringIfPresent(forKey: .every)
    }

    var displayText: String? {
        expression ?? expr ?? runAt ?? every ?? kind
    }
}

struct CronRepeat: Decodable, Equatable {
    let times: Int?
    let completed: Int?
}

struct CronOutputResponse: Decodable, Equatable {
    let jobId: String?
    let outputs: [CronOutputItem]?

    enum CodingKeys: String, CodingKey {
        case jobId
        case outputs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        jobId = try container.decodeIfPresent(String.self, forKey: .jobId)
        outputs = (try? container.decodeIfPresent([CronOutputItem].self, forKey: .outputs)) ?? nil
    }
}

struct CronOutputItem: Decodable, Equatable, Identifiable {
    var id: String { filename ?? UUID().uuidString }

    let filename: String?
    let content: String?

    enum CodingKeys: String, CodingKey {
        case filename
        case content
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        filename = try container.decodeIfPresent(String.self, forKey: .filename)
        content = try container.decodeIfPresent(String.self, forKey: .content)
    }
}

struct CronRunListItem: Equatable, Identifiable {
    let id: String
    let filename: String?
    let modified: Double?
    let size: Int?
    let usage: CronRunUsage?
    let outputContent: String?

    var displayTitle: String {
        CronOutputItem.normalizedFilename(filename) ?? String(localized: "Untitled run")
    }

    var hasOutputContent: Bool {
        CronOutputItem.normalizedFilename(outputContent) != nil
    }

    static func items(
        runs: [CronRunHistoryItem],
        outputs: [CronOutputItem]
    ) -> [CronRunListItem] {
        var matchedOutputFilenames = Set<String>()

        var runItems: [CronRunListItem] = []
        for (index, run) in runs.enumerated() {
            let output = outputs.output(matching: run)
            if let filename = CronOutputItem.normalizedFilename(output?.filename ?? run.filename) {
                matchedOutputFilenames.insert(filename)
            }

            let identitySuffix = CronOutputItem.normalizedFilename(run.filename)
                ?? run.modified.map { String($0) }
                ?? "unknown"

            runItems.append(CronRunListItem(
                id: "run-\(index)-\(identitySuffix)",
                filename: run.filename,
                modified: run.modified,
                size: run.size,
                usage: run.usage,
                outputContent: output?.content
            ))
        }

        var outputOnlyItems: [CronRunListItem] = []
        for (index, output) in outputs.enumerated() {
            let filename = CronOutputItem.normalizedFilename(output.filename)
            if let filename, matchedOutputFilenames.contains(filename) {
                continue
            }

            let identitySuffix = filename ?? "untitled"

            outputOnlyItems.append(CronRunListItem(
                id: "output-\(index)-\(identitySuffix)",
                filename: output.filename,
                modified: nil,
                size: nil,
                usage: nil,
                outputContent: output.content
            ))
        }

        return runItems + outputOnlyItems
    }
}

extension CronRunHistoryItem {
    var displayTitle: String {
        CronOutputItem.normalizedFilename(filename) ?? String(localized: "Untitled run")
    }
}

extension CronOutputItem {
    var displayTitle: String {
        Self.normalizedFilename(filename) ?? String(localized: "Untitled output")
    }

    func matches(run: CronRunHistoryItem) -> Bool {
        guard let outputFilename = Self.normalizedFilename(filename),
              let runFilename = Self.normalizedFilename(run.filename)
        else {
            return false
        }

        return outputFilename == runFilename
    }

    static func normalizedFilename(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}

extension Array where Element == CronOutputItem {
    func output(matching run: CronRunHistoryItem) -> CronOutputItem? {
        first { $0.matches(run: run) }
    }
}

enum CronJobStatus: Equatable {
    case active
    case paused
    case off
    case error
    case needsAttention

    var label: String {
        switch self {
        case .active:
            return String(localized: "Active")
        case .paused:
            return String(localized: "Paused")
        case .off:
            return String(localized: "Off")
        case .error:
            return String(localized: "Error")
        case .needsAttention:
            return String(localized: "Needs Attention")
        }
    }
}

struct CronJobEditorDraft: Equatable {
    var name: String
    var prompt: String
    var schedule: String
    var deliver: String
    var skillsText: String
    var model: String
    var profile: String
    var toastNotifications: Bool

    init(
        name: String = "",
        prompt: String = "",
        schedule: String = "",
        deliver: String = "local",
        skillsText: String = "",
        model: String = "",
        profile: String = "",
        toastNotifications: Bool = true
    ) {
        self.name = name
        self.prompt = prompt
        self.schedule = schedule
        self.deliver = deliver
        self.skillsText = skillsText
        self.model = model
        self.profile = profile
        self.toastNotifications = toastNotifications
    }

    init(job: CronJob) {
        self.init(
            name: job.name ?? "",
            prompt: job.prompt ?? "",
            schedule: job.editableScheduleText ?? "",
            deliver: job.deliver ?? "local",
            skillsText: job.skills?.joined(separator: ", ") ?? "",
            model: job.model ?? "",
            profile: job.profile ?? "",
            toastNotifications: job.toastNotifications ?? true
        )
    }

    var trimmedName: String? {
        Self.nonEmpty(name)
    }

    var trimmedPrompt: String {
        prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedSchedule: String {
        schedule.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedDeliver: String? {
        Self.nonEmpty(deliver)
    }

    var trimmedModel: String? {
        Self.nonEmpty(model)
    }

    var trimmedProfile: String? {
        Self.nonEmpty(profile)
    }

    var skills: [String] {
        skillsText
            .split { character in
                character == "," || character == "\n"
            }
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var validationMessage: String? {
        if trimmedPrompt.isEmpty {
            return String(localized: "Prompt is required.")
        }

        if trimmedSchedule.isEmpty {
            return String(localized: "Schedule is required.")
        }

        return nil
    }

    private static func nonEmpty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct CronJobDraftSuggestion: Equatable {
    let descriptor: String
    let draft: CronJobEditorDraft
    let summary: String
}

enum CronJobDraftSuggester {
    static func suggest(from descriptor: String) -> CronJobDraftSuggestion {
        let normalized = normalize(descriptor)
        let schedule = scheduleExpression(from: normalized)
        let name = suggestedName(from: normalized)
        let draft = CronJobEditorDraft(
            name: name,
            prompt: normalized,
            schedule: normalized.isEmpty ? "" : schedule,
            deliver: "local",
            toastNotifications: true
        )

        return CronJobDraftSuggestion(
            descriptor: normalized,
            draft: draft,
            summary: summary(for: schedule)
        )
    }

    private static func normalize(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .joined(separator: " ")
    }

    private static func scheduleExpression(from descriptor: String) -> String {
        guard !descriptor.isEmpty else { return "" }

        if let interval = intervalExpression(from: descriptor) {
            return interval
        }

        let lowercased = descriptor.lowercased()
        let time = timeExpression(from: descriptor) ?? (hour: 9, minute: 0)

        if lowercased.contains("weekday") || lowercased.contains("week day") {
            return "\(time.minute) \(time.hour) * * 1-5"
        }

        if let weekday = weekdayNumber(in: lowercased) {
            return "\(time.minute) \(time.hour) * * \(weekday)"
        }

        if lowercased.contains("hourly") {
            return "@hourly"
        }

        if lowercased.contains("daily") || lowercased.contains("every day") || lowercased.contains("each day") {
            return "\(time.minute) \(time.hour) * * *"
        }

        return "@daily"
    }

    private static func intervalExpression(from descriptor: String) -> String? {
        let patterns: [(String, String)] = [
            (#"\bevery\s+(\d+)\s*(?:minutes?|mins?|m)\b"#, "m"),
            (#"\bevery\s+(\d+)\s*(?:hours?|hrs?|h)\b"#, "h"),
            (#"\bevery\s+(\d+)\s*(?:days?|d)\b"#, "d")
        ]

        for (pattern, suffix) in patterns {
            guard let match = firstMatch(pattern: pattern, in: descriptor),
                  match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: descriptor),
                  let amount = Int(descriptor[range]),
                  amount > 0
            else {
                continue
            }

            if suffix == "d", amount == 1 {
                return "@daily"
            }
            return "every \(amount)\(suffix)"
        }

        return nil
    }

    private static func timeExpression(from descriptor: String) -> (hour: Int, minute: Int)? {
        guard let match = firstMatch(
            pattern: #"\bat\s+(\d{1,2})(?::(\d{2}))?\s*(am|pm)?\b"#,
            in: descriptor
        ), match.numberOfRanges >= 2,
           let hourRange = Range(match.range(at: 1), in: descriptor),
           var hour = Int(descriptor[hourRange])
        else {
            return nil
        }

        var minute = 0
        if match.numberOfRanges > 2,
           let minuteRange = Range(match.range(at: 2), in: descriptor) {
            minute = Int(descriptor[minuteRange]) ?? 0
        }

        if match.numberOfRanges > 3,
           let meridiemRange = Range(match.range(at: 3), in: descriptor) {
            let meridiem = descriptor[meridiemRange].lowercased()
            if meridiem == "pm", hour < 12 {
                hour += 12
            } else if meridiem == "am", hour == 12 {
                hour = 0
            }
        }

        guard (0...23).contains(hour), (0...59).contains(minute) else {
            return nil
        }

        return (hour, minute)
    }

    private static func weekdayNumber(in lowercasedDescriptor: String) -> Int? {
        let days: [(String, Int)] = [
            ("sunday", 0),
            ("monday", 1),
            ("tuesday", 2),
            ("wednesday", 3),
            ("thursday", 4),
            ("friday", 5),
            ("saturday", 6)
        ]
        return days.first { lowercasedDescriptor.contains($0.0) }?.1
    }

    private static func suggestedName(from descriptor: String) -> String {
        guard !descriptor.isEmpty else { return "" }

        let patterns = [
            #"\s+every\s+\d+\s*(?:minutes?|mins?|m|hours?|hrs?|h|days?|d)\b.*$"#,
            #"\s+every\s+weekdays?\b.*$"#,
            #"\s+on\s+(?:mondays?|tuesdays?|wednesdays?|thursdays?|fridays?|saturdays?|sundays?)\b.*$"#,
            #"\s+(?:daily|hourly)\b.*$"#,
            #"\s+every\s+day\b.*$"#
        ]

        var candidate = descriptor
        for pattern in patterns {
            candidate = candidate.replacingOccurrences(
                of: pattern,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
        }

        candidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        if candidate.isEmpty {
            candidate = descriptor
        }

        if candidate.count > 56 {
            let limited = candidate.prefix(56)
            if let lastSpace = limited.lastIndex(where: { $0.isWhitespace }) {
                candidate = String(limited[..<lastSpace])
            } else {
                candidate = String(limited)
            }
        }

        return candidate
    }

    private static func summary(for schedule: String) -> String {
        if schedule.isEmpty {
            return String(localized: "Describe what the task should do and when it should run.")
        }

        return String(localized: "Suggested schedule: \(schedule). Review all fields before creating.")
    }

    private static func firstMatch(pattern: String, in value: String) -> NSTextCheckingResult? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return regex.firstMatch(in: value, range: range)
    }
}

struct CronDateValue: Decodable, Equatable {
    let date: Date

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let timestamp = try? container.decode(Double.self) {
            date = Date(timeIntervalSince1970: timestamp)
            return
        }

        let stringValue = try container.decode(String.self)
        if let timestamp = Double(stringValue) {
            date = Date(timeIntervalSince1970: timestamp)
            return
        }

        if let parsed = Self.isoFormatter.date(from: stringValue)
            ?? Self.fractionalISOFormatter.date(from: stringValue) {
            date = parsed
            return
        }

        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Unsupported cron date value"
        )
    }

    var formatted: String {
        Self.displayFormatter.string(from: date)
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let fractionalISOFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let displayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

extension KeyedDecodingContainer {
    func decodeFlexibleDoubleIfPresent(forKey key: Key) throws -> Double? {
        if let value = try? decodeIfPresent(Double.self, forKey: key) {
            return value
        }

        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return Double(value)
        }

        if let stringValue = try? decodeIfPresent(String.self, forKey: key) {
            return Double(stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        return nil
    }
}
