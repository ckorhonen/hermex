import SwiftUI
import SwiftData
import UIKit
import UserNotifications

/// A Settings section a deep link can scroll to when the screen opens — the
/// avatar long-press "Manage Servers" shortcut lands on the Servers card (#283).
enum SettingsScrollAnchor: Hashable {
    case servers
}

struct SettingsView: View {
    @Bindable var authManager: AuthManager
    let server: URL
    /// When set, Settings scrolls to this section once on first appear (#283).
    let initialScrollTarget: SettingsScrollAnchor?
    let onAPIError: (Error) -> Void

    init(
        authManager: AuthManager,
        server: URL,
        initialScrollTarget: SettingsScrollAnchor? = nil,
        onAPIError: @escaping (Error) -> Void = { _ in }
    ) {
        self.authManager = authManager
        self.server = server
        self.initialScrollTarget = initialScrollTarget
        self.onAPIError = onAPIError
        _updateController = State(initialValue: ServerUpdateController(server: server, authManager: authManager))
    }

    @ScaledMetric(relativeTo: .body) private var settingsCardSpacing: CGFloat = 18
    @State private var isConfirmingReconfigure = false
    @State private var didScrollToInitialTarget = false
    @State private var isPresentingAddServer = false
    @State private var isConfirmingClearCache = false
    @State private var isClearingCache = false
    @State private var cacheStatusMessage: String?
    @State private var updateController: ServerUpdateController
    @State private var isConfirmingUpdate = false
    @State private var showDefaultModelPicker = false
    @State private var showDefaultProfilePicker = false
    @State private var notificationPermissionStatus: UNAuthorizationStatus?
    @State private var notificationStatusMessage: String?
    @AppStorage(AppTheme.storageKey) private var appThemeRawValue = AppTheme.system.rawValue
    @AppStorage(AppHaptics.isEnabledKey) private var isHapticsEnabled = true
    @AppStorage(ResponseCompletionNotifications.isEnabledKey) private var isResponseCompletionNotificationsEnabled = false
    @AppStorage(ResponseCompletionNotifications.hasRequestedPermissionKey) private var hasRequestedResponseCompletionNotificationPermission = false
    @AppStorage(AgentRunLiveActivityPrivacy.showsResponseExcerptsKey) private var showsLiveActivityResponseExcerpts = false
    @AppStorage(SessionRowDisplaySettings.showMessageCountKey) private var showsSessionMessageCount = true
    @AppStorage(SessionRowDisplaySettings.showWorkspaceKey) private var showsSessionWorkspace = true
    @AppStorage(SessionRowDisplaySettings.showCronSessionsKey) private var showsCronSessions = true
    @AppStorage(SessionRowDisplaySettings.showCliSessionsKey) private var showsCliSessions = true
    @AppStorage(StreamingSendBehavior.storageKey) private var streamingSendBehaviorRawValue = StreamingSendBehavior.steer.rawValue
    @AppStorage(ChatTranscriptDisplaySettings.showsThinkingAndToolCardsKey) private var showsThinkingAndToolCards = true
    @AppStorage(ChatTranscriptDisplaySettings.thinkingCardsStartExpandedKey) private var thinkingCardsStartExpanded = false
    @AppStorage(ChatTranscriptDisplaySettings.toolCardsStartExpandedKey) private var toolCardsStartExpanded = false
    @AppStorage(ChatTranscriptDisplaySettings.hidesAttachmentPathsKey) private var hidesAttachmentPaths = true
    @AppStorage(ChatTranscriptDisplaySettings.showsAssistantTurnTimestampsKey) private var showsAssistantTurnTimestamps = false
    @AppStorage(ChatTranscriptDisplaySettings.wrapsCodeBlockLinesKey) private var wrapsCodeBlockLines = false
    @AppStorage(ChatTranscriptDisplaySettings.rtlChatLayoutEnabledKey) private var rtlChatLayoutEnabled = ChatTranscriptDisplaySettings.rtlChatLayoutDefaultEnabled
    @AppStorage(StreamedTextAnimationSettings.isEnabledKey) private var isStreamedTextAnimationEnabled = true
    @AppStorage(HeaderLogoColor.storageKey) private var headerLogoColorHex = HeaderLogoColor.defaultHex
    @AppStorage(PrimaryActionTintSettings.isEnabledKey) private var tintsPrimaryActions = false
    @AppStorage(SessionIdentitySettings.displayNameKey) private var identityDisplayName = ""
    @AppStorage(SessionIdentitySettings.initialsKey) private var identityInitials = ""
    @AppStorage(SessionAvatarStyle.storageKey) private var avatarStyleRawValue = SessionAvatarStyle.defaultValue.rawValue
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(spacing: settingsCardSpacing) {
                SettingsCard(title: String(localized: "Identity")) {
                    SessionIdentitySettingsEditor(
                        displayName: $identityDisplayName,
                        initials: identityInitialsBinding,
                        avatarStyleRawValue: $avatarStyleRawValue,
                        previewInitials: identityPreviewInitials,
                        previewStyle: SessionAvatarStyle.storedValue(avatarStyleRawValue),
                        previewColor: HeaderLogoColor.color(for: headerLogoColorHex),
                        previewForeground: HeaderLogoColor.prefersDarkForeground(for: headerLogoColorHex) ? .black : .white
                    )
                }

                SettingsCard(title: String(localized: "Archived Sessions")) {
                    NavigationLink {
                        ArchivedSessionsView(server: server)
                    } label: {
                        SettingsAccessoryRow(title: String(localized: "Archived Sessions"), systemImage: "archivebox")
                    }
                    .buttonStyle(.plain)
                }

                SettingsCard(title: String(localized: "Tools")) {
                    NavigationLink {
                        SkillsView(server: server, onAPIError: onAPIError)
                    } label: {
                        SettingsAccessoryRow(title: String(localized: "Skills"), systemImage: "wrench.and.screwdriver")
                    }
                    .buttonStyle(.plain)

                    SettingsDivider()

                    NavigationLink {
                        MemoryView(server: server, onAPIError: onAPIError)
                    } label: {
                        SettingsAccessoryRow(title: String(localized: "Memory"), systemImage: "brain.head.profile")
                    }
                    .buttonStyle(.plain)

                    SettingsDivider()

                    NavigationLink {
                        InsightsView(server: server, onAPIError: onAPIError)
                    } label: {
                        SettingsAccessoryRow(title: String(localized: "Insights"), systemImage: "chart.bar.xaxis")
                    }
                    .buttonStyle(.plain)
                }

                SettingsCard(title: String(localized: "Appearance")) {
                    SettingsPickerRow(
                        title: String(localized: "Theme"),
                        systemImage: "circle.lefthalf.filled",
                        selection: $appThemeRawValue
                    ) {
                        ForEach(AppTheme.allCases) { theme in
                            Text(theme.title).tag(theme.rawValue)
                        }
                    }

                    SettingsDivider()

                    HeaderLogoColorSettings(
                        selectedHex: $headerLogoColorHex,
                        customColor: headerLogoColorBinding
                    )

                    SettingsDivider()

                    SettingsToggleRow(
                        title: String(localized: "Tint New Chat & Send"),
                        systemImage: "paintbrush.pointed",
                        isOn: $tintsPrimaryActions
                    )

                    SettingsFootnote(String(localized: "Apply your header color to these primary buttons."))

                    SettingsDivider()

                    AppIconSettingsSection()
                }

                SettingsCard(title: String(localized: "Interaction")) {
                    SettingsToggleRow(
                        title: String(localized: "Haptic Feedback"),
                        systemImage: "iphone.radiowaves.left.and.right",
                        isOn: $isHapticsEnabled
                    )

                    SettingsDivider()

                    SettingsToggleRow(
                        title: String(localized: "Response Complete Alerts"),
                        systemImage: "bell",
                        isOn: responseCompletionNotificationBinding
                    )

                    if let notificationStatusText {
                        SettingsFootnote(notificationStatusText)
                    }

                    SettingsDivider()

                    SettingsPickerRow(
                        title: String(localized: "Send While Responding"),
                        systemImage: "arrow.up.message",
                        selection: $streamingSendBehaviorRawValue
                    ) {
                        ForEach(StreamingSendBehavior.allCases) { behavior in
                            Text(behavior.settingsDescription).tag(behavior.rawValue)
                        }
                    }
                }

                SettingsCard(title: String(localized: "Chat")) {
                    SettingsToggleRow(
                        title: String(localized: "Thinking and Tool Cards"),
                        systemImage: "brain.head.profile",
                        isOn: $showsThinkingAndToolCards
                    )

                    SettingsDivider()

                    SettingsToggleRow(
                        title: String(localized: "Expand Thinking by Default"),
                        systemImage: "rectangle.expand.vertical",
                        isOn: $thinkingCardsStartExpanded
                    )

                    SettingsDivider()

                    SettingsToggleRow(
                        title: String(localized: "Expand Tools by Default"),
                        systemImage: "wrench.and.screwdriver",
                        isOn: $toolCardsStartExpanded
                    )

                    SettingsFootnote(String(localized: "Thinking and Tool cards start expanded instead of collapsed. Tapping a card still toggles it."))

                    SettingsDivider()

                    SettingsToggleRow(
                        title: String(localized: "Streamed Text Animation"),
                        systemImage: "sparkles",
                        isOn: $isStreamedTextAnimationEnabled
                    )

                    SettingsFootnote(String(localized: "Fades words in as a response streams. Turn off to show text instantly."))

                    SettingsDivider()

                    SettingsToggleRow(
                        title: String(localized: "Response Timestamps"),
                        systemImage: "clock",
                        isOn: $showsAssistantTurnTimestamps
                    )

                    SettingsFootnote(String(localized: "Adds a small marker and the time above each response so back-to-back replies are easier to tell apart."))

                    SettingsDivider()

                    SettingsToggleRow(
                        title: String(localized: "Wrap Code Block Lines"),
                        systemImage: "arrow.turn.down.left",
                        isOn: $wrapsCodeBlockLines
                    )

                    SettingsFootnote(String(localized: "Wraps long lines in code blocks to fit the screen instead of scrolling sideways. You can also tap the wrap button in any code block."))

                    SettingsDivider()

                    SettingsToggleRow(
                        title: String(localized: "Right-to-Left Chat Layout"),
                        systemImage: "text.alignright",
                        isOn: $rtlChatLayoutEnabled
                    )

                    SettingsFootnote(String(localized: "Lays out messages and the composer right-to-left for Arabic, Hebrew, Persian, and Urdu. Code, math, tables, and tool output stay left-to-right. Other screens are unaffected."))

                    SettingsDivider()

                    SettingsToggleRow(
                        title: String(localized: "Hide Attachment Paths"),
                        systemImage: "eye.slash",
                        isOn: $hidesAttachmentPaths
                    )

                    SettingsFootnote(String(localized: "Hides the appended file-path line in your sent messages. Attachments still appear as previews, and the server still receives the paths."))

                    SettingsDivider()

                    SettingsToggleRow(
                        title: String(localized: "Live Activity Excerpts"),
                        systemImage: "lock",
                        isOn: $showsLiveActivityResponseExcerpts
                    )

                    SettingsFootnote(String(localized: "Shows short response text on the Lock Screen and Dynamic Island."))
                }

                SettingsCard(title: String(localized: "Sessions")) {
                    SettingsToggleRow(
                        title: String(localized: "Message Count"),
                        systemImage: "number",
                        isOn: $showsSessionMessageCount
                    )

                    SettingsDivider()

                    SettingsToggleRow(
                        title: String(localized: "Workspace"),
                        systemImage: "folder",
                        isOn: $showsSessionWorkspace
                    )

                    SettingsDivider()

                    SettingsToggleRow(
                        title: String(localized: "Cron Sessions"),
                        systemImage: "clock.arrow.2.circlepath",
                        isOn: $showsCronSessions
                    )

                    SettingsDivider()

                    SettingsToggleRow(
                        title: String(localized: "CLI Sessions"),
                        systemImage: "terminal",
                        isOn: $showsCliSessions
                    )
                }

                SettingsCard(title: String(localized: "Siri & Shortcuts")) {
                    if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                        Link(destination: settingsURL) {
                            SettingsAccessoryRow(
                                title: String(localized: "Open Zora Settings"),
                                systemImage: "gearshape",
                                accessorySystemImage: "arrow.up.forward"
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Open Zora Settings")
                    }

                    SettingsFootnote(String(localized: "Run Zora actions like New Chat from Siri, Spotlight, the Lock Screen, or the iPhone Action button. Open Zora Settings to manage its Siri & Search options. To assign an action to the Action button, open the iOS Settings app, choose Action Button, then Shortcut, and pick a Zora action."))
                }

                serversCard
                    .id(SettingsScrollAnchor.servers)

                SettingsCard(title: String(localized: "Active Server")) {
                    HapticButton {
                        showDefaultModelPicker = true
                    } label: {
                        SettingsAccessoryRow(
                            title: String(localized: "Default Model"),
                            value: defaultModelLabel,
                            systemImage: "cpu"
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens the default model picker.")

                    SettingsDivider()

                    HapticButton {
                        showDefaultProfilePicker = true
                    } label: {
                        SettingsAccessoryRow(
                            title: String(localized: "Default Profile"),
                            value: defaultProfileLabel,
                            systemImage: "person.crop.circle"
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens the default profile picker.")

                    SettingsDivider()

                    SettingsValueRow(title: String(localized: "Status")) {
                        serverStatusPill
                    }

                    SettingsDivider()

                    NavigationLink {
                        CustomHeadersSettingsView(authManager: authManager)
                    } label: {
                        SettingsAccessoryRow(
                            title: String(localized: "Connection Headers"),
                            systemImage: "list.bullet.rectangle"
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens the custom request headers editor.")

                    SettingsValueRow(title: String(localized: "Version")) {
                        serverVersionContent
                    }

                    serverUpdateCheckAction
                    serverUpdateNote
                    serverUpdateAction
                }

                SettingsCard(title: String(localized: "App")) {
                    SettingsInfoRow(title: String(localized: "Version"), value: appVersion)
                    SettingsInfoRow(title: String(localized: "Build"), value: appBuild)

                    SettingsDivider()

                    Link(destination: AppConfig.privacyPolicyURL) {
                        SettingsAccessoryRow(
                            title: String(localized: "Privacy Policy"),
                            systemImage: "hand.raised",
                            accessorySystemImage: "arrow.up.forward"
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Privacy Policy")

                    SettingsDivider()

                    Link(destination: AppConfig.supportURL) {
                        SettingsAccessoryRow(
                            title: String(localized: "Support"),
                            systemImage: "questionmark.circle",
                            accessorySystemImage: "arrow.up.forward"
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Support")
                }

                #if DEBUG
                SettingsCard(title: String(localized: "Developer")) {
                    NavigationLink {
                        StreamingLabView()
                    } label: {
                        SettingsAccessoryRow(title: String(localized: "Streaming Lab"), systemImage: "waveform.path.ecg")
                    }
                    .buttonStyle(.plain)

                    SettingsFootnote(String(localized: "Debug builds only. Replay a canned reply and tune the streamed-text fade feel live."))
                }
                #endif

                SettingsCard(title: String(localized: "Offline Data")) {
                    SettingsFootnote(cacheStatusMessage ?? String(localized: "Cached sessions and messages are kept for offline viewing. Clearing removes this server's cache only — other servers and the Hermes server are not affected."))

                    SettingsButton(String(localized: "Clear Offline Cache"), role: .destructive, isLoading: isClearingCache) {
                        isConfirmingClearCache = true
                    }
                    .disabled(isClearingCache)
                }

                SettingsCard(title: String(localized: "Account")) {
                    SettingsFootnote(signOutFootnote)

                    SettingsButton(String(localized: "Sign Out of This Server"), role: .destructive) {
                        isConfirmingReconfigure = true
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 36)
            .zoraAdaptiveContentFrame(.readablePage)
        }
        .background(Color.clear)
        .navigationTitle("Settings")
        .task {
            await updateController.loadServerSettings()
            await refreshNotificationPermissionStatus()
        }
        .alert("Clear this server's cache?", isPresented: $isConfirmingClearCache) {
            Button("Cancel", role: .cancel) {}
            Button("Clear Cache", role: .destructive) {
                Task {
                    await clearOfflineCache()
                }
            }
        } message: {
            Text("This server's cached sessions and messages will be deleted. Other servers and online server data are not affected.")
        }
        .alert("Update server?", isPresented: $isConfirmingUpdate) {
            Button("Cancel", role: .cancel) {}
            Button("Update") {
                Task {
                    await updateController.applyServerUpdate()
                }
            }
        } message: {
            Text("This pulls the latest Hermes server version and restarts it. Active chats may be interrupted briefly; the app reconnects when the server is back.")
        }
        // Result of a manual "Check for updates" tap (#308). The outcome is kept
        // set after dismissal so the title/message read off it without blanking
        // mid-animation; a fresh check overwrites it before re-presenting.
        .alert(
            forcedCheckAlertTitle,
            isPresented: $updateController.isPresentingForcedCheckResult
        ) {
            if case .updateAvailable = updateController.forcedCheckOutcome {
                // The popup already carries the restart warning, so Update applies
                // directly — no second confirmation dialog (issue #308).
                Button("Update") {
                    Task {
                        await updateController.applyServerUpdate()
                    }
                }
                Button("Dismiss", role: .cancel) {}
            } else {
                Button("OK", role: .cancel) {}
            }
        } message: {
            Text(forcedCheckAlertMessage)
        }
        .alert("Sign out of this server?", isPresented: $isConfirmingReconfigure) {
            Button("Cancel", role: .cancel) {}
            Button("Sign Out", role: .destructive) {
                Task {
                    // Purge this server's offline cache before signing out, while
                    // the view (and its modelContext) is still alive — sign-out
                    // forgets the active server from the registry, so its cache
                    // would otherwise be orphaned. Mirrors the server-detail
                    // remove path (#18). Best-effort: the cache is server-keyed,
                    // so a leftover row can never surface as another server's.
                    try? CacheStore.clearCache(for: server, in: modelContext)
                    await authManager.signOut()
                    dismiss()
                }
            }
        } message: {
            Text(signOutMessage)
        }
        // The Identity + Header Logo Color controls edit the *active* server (#17):
        // mirror their global @AppStorage value through to that server's registry
        // entry so it survives a switch and a relaunch. The @AppStorage write keeps
        // the live avatar/tint instant; this just persists it per server.
        .onChange(of: identityDisplayName) { syncActiveServerIdentity() }
        .onChange(of: identityInitials) { syncActiveServerIdentity() }
        .onChange(of: headerLogoColorHex) { syncActiveServerIdentity() }
        .sheet(isPresented: $isPresentingAddServer) {
            AddServerView(authManager: authManager)
        }
        .sheet(isPresented: $showDefaultModelPicker) {
            DefaultModelPickerView(
                server: server,
                currentDefaultModel: updateController.defaultModel,
                onSave: { model in
                    updateController.defaultModel = model
                }
            )
        }
        .sheet(isPresented: $showDefaultProfilePicker) {
            DefaultProfilePickerView(
                server: server,
                currentDefaultProfileName: updateController.defaultProfileName,
                onSave: { selection in
                    updateController.defaultProfileName = selection.name
                    updateController.defaultProfileDisplayName = selection.displayName
                    if let defaultModel = selection.defaultModel, !defaultModel.isEmpty {
                        updateController.defaultModel = defaultModel
                    }
                }
            )
        }
        .onAppear {
            // Land on the requested section once when opened via a deep link
            // (the avatar's "Manage Servers" → Servers card), not on every
            // re-appear after popping back from a sub-screen (#283).
            guard let initialScrollTarget, !didScrollToInitialTarget else { return }
            didScrollToInitialTarget = true
            DispatchQueue.main.async {
                proxy.scrollTo(initialScrollTarget, anchor: .top)
            }
        }
        }
        .zoraBrandedScreen()
    }

    @ViewBuilder
    private var serversCard: some View {
        SettingsCard(title: String(localized: "Servers")) {
            ForEach(authManager.servers) { account in
                if account.id != authManager.servers.first?.id {
                    SettingsDivider()
                }

                NavigationLink {
                    ServerDetailView(authManager: authManager, account: account)
                } label: {
                    SettingsServerRow(
                        account: account,
                        isActive: account.id == authManager.activeServerID
                    )
                }
                .buttonStyle(.plain)
            }

            SettingsDivider()

            HapticButton {
                isPresentingAddServer = true
            } label: {
                SettingsAccessoryRow(title: String(localized: "Add Server"), systemImage: "plus.circle")
            }
            .buttonStyle(.plain)
            .accessibilityHint("Adds another Hermes server.")
        }
    }

    /// The active server's registry entry, or nil while unconfigured.
    private var activeAccount: ServerAccount? {
        authManager.servers.first { $0.id == authManager.activeServerID }
    }

    /// Pushes the current global identity values (which the Identity + Header Logo
    /// Color controls edit) into the active server's registry entry, so per-server
    /// identity follows the active server (#17). Single-server users see no change.
    private func syncActiveServerIdentity() {
        guard let account = activeAccount else { return }
        authManager.updateServerIdentity(
            account,
            displayName: identityDisplayName,
            initials: identityInitials,
            headerLogoColorHex: headerLogoColorHex
        )
    }

    private var signOutFootnote: String {
        authManager.servers.count > 1
            ? String(localized: "Signs out of the active server and switches to another configured server.")
            : String(localized: "Signs out of the active server and returns to onboarding.")
    }

    private var signOutMessage: String {
        authManager.servers.count > 1
            ? String(localized: "You'll switch to another configured server. Sign in again to use this one.")
            : String(localized: "You'll return to onboarding and need the server URL and password to sign back in.")
    }

    @ViewBuilder
    private var serverVersionContent: some View {
        if updateController.isLoadingServerSettings {
            ProgressView()
        } else if let serverVersion = updateController.serverVersion {
            Text(serverVersion)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        } else {
            Text(updateController.serverSettingsError ?? String(localized: "Unknown"))
                .foregroundStyle(.secondary)
        }
    }

    private var defaultModelLabel: String {
        if updateController.isLoadingDefaultModel {
            return String(localized: "Loading")
        }

        guard let defaultModel = updateController.defaultModel, !defaultModel.isEmpty else {
            return String(localized: "Not set")
        }

        return defaultModel
    }

    private var defaultProfileLabel: String {
        if updateController.isLoadingDefaultProfile {
            return String(localized: "Loading")
        }

        if let defaultProfileDisplayName = updateController.defaultProfileDisplayName, !defaultProfileDisplayName.isEmpty {
            return defaultProfileDisplayName
        }

        guard let defaultProfileName = updateController.defaultProfileName, !defaultProfileName.isEmpty else {
            return String(localized: "Not set")
        }

        return defaultProfileName == "default" ? String(localized: "Default") : defaultProfileName
    }

    @ViewBuilder
    private var serverStatusPill: some View {
        if updateController.isLoadingServerSettings {
            SettingsStatusPill(label: String(localized: "Loading"))
        } else if updateController.serverSettingsError == nil, updateController.serverVersion != nil {
            // Only "Connected" when the latest load actually succeeded — a stale
            // `serverVersion` from an earlier success must not mask a now-failed
            // load (e.g. a restart that never came back).
            SettingsStatusPill(label: String(localized: "Connected"))
        } else {
            SettingsStatusPill(label: updateController.serverSettingsError ?? String(localized: "Unknown"), tint: .orange)
        }
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? String(localized: "Unknown")
    }

    private var appBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? String(localized: "Unknown")
    }

    private var responseCompletionNotificationBinding: Binding<Bool> {
        Binding(
            get: { isResponseCompletionNotificationsEnabled },
            set: { isEnabled in
                if isEnabled {
                    Task {
                        await enableResponseCompletionNotifications()
                    }
                } else {
                    isResponseCompletionNotificationsEnabled = false
                    Task {
                        await refreshNotificationPermissionStatus()
                    }
                }
            }
        )
    }

    private var headerLogoColorBinding: Binding<Color> {
        Binding(
            get: { HeaderLogoColor.color(for: headerLogoColorHex) },
            set: { color in
                if let hex = HeaderLogoColor.hexString(from: color) {
                    headerLogoColorHex = hex
                }
            }
        )
    }

    private var identityInitialsBinding: Binding<String> {
        Binding(
            get: { identityInitials },
            set: { identityInitials = SessionIdentitySettings.normalizedInitials($0) }
        )
    }

    private var identityPreviewInitials: String {
        SessionIdentitySettings.displayInitials(
            displayName: identityDisplayName,
            storedInitials: identityInitials,
            fallbackFullName: NSFullUserName()
        )
    }

    private var notificationStatusText: String? {
        notificationStatusMessage ?? notificationPermissionStatus.map(notificationPermissionLabel)
    }

    // The manual "Check for updates" control (#308). Distinct from the passive
    // on-open check: it forces a live git fetch on the server. While a check is in
    // flight it swaps to a "Checking…" spinner; it's disabled during an apply so
    // the two update flows never run at once.
    @ViewBuilder
    private var serverUpdateCheckAction: some View {
        if updateController.isCheckingForUpdates {
            updateProgressRow(String(localized: "Checking for updates…"))
        } else {
            SettingsButton(String(localized: "Check for updates")) {
                Task {
                    await updateController.checkForUpdatesManually()
                }
            }
            .disabled(updateController.isUpdateApplyInFlight)
            .padding(.top, 4)
        }
    }

    private var forcedCheckAlertTitle: String {
        switch updateController.forcedCheckOutcome {
        case let .updateAvailable(behind):
            return String(localized: "Update available · \(behind) behind")
        case .upToDate:
            return String(localized: "You're up to date")
        case .disabled:
            return String(localized: "Update checks are off")
        case .error, .none:
            return String(localized: "Couldn't check for updates")
        }
    }

    private var forcedCheckAlertMessage: String {
        switch updateController.forcedCheckOutcome {
        case .updateAvailable:
            return String(localized: "This pulls the latest Hermes server version and restarts it. Active chats may be interrupted briefly; the app reconnects when the server is back.")
        case .upToDate:
            return String(localized: "The Hermes server is running the latest version.")
        case .disabled:
            return String(localized: "Update checks are turned off on this server.")
        case .error, .none:
            return String(localized: "Something went wrong reaching the server. Try again in a moment.")
        }
    }

    // Informational only — never a warning. A normal, up-to-date server shows a
    // calm "Up to date"; a server that genuinely lags shows how far behind it is.
    // When the check is disabled, errored, or hasn't loaded, we show nothing here
    // and let the plain version row stand on its own.
    @ViewBuilder
    private var serverUpdateNote: some View {
        if updateController.serverVersion != nil, let serverUpdateState = updateController.serverUpdateState {
            switch serverUpdateState {
            case .upToDate:
                updateNoteRow(systemImage: "checkmark.circle", tint: .secondary, text: String(localized: "Up to date"))
            case let .updateAvailable(behind):
                updateNoteRow(systemImage: "arrow.up.circle", tint: .blue, text: String(localized: "Update available · \(behind) behind"))
            case .unavailable:
                EmptyView()
            }
        }
    }

    private func updateNoteRow(systemImage: String, tint: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)

            Text(text)
                .font(AppFont.footnote())
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    // The in-app "Update" action. Every phase resolves to a concrete UI so there
    // is never a stuck spinner *or* a silent vanish: the initial Update button is
    // gated on the server reporting a pending update, but once a run is underway
    // the progress / blocked / failed UI is driven purely by `updateApplyPhase`.
    // That keeps the message + Retry visible even if a slow/failed restart leaves
    // `serverUpdateState` nil or stale. Success returns to `.idle`, where the
    // refreshed `.upToDate` state removes the button.
    @ViewBuilder
    private var serverUpdateAction: some View {
        switch updateController.updateApplyPhase {
        case .idle:
            if updateController.serverVersion != nil, case .updateAvailable = updateController.serverUpdateState {
                updateActionButton(title: String(localized: "Update"))
            }
        case .applying:
            updateProgressRow(String(localized: "Starting update…"))
        case .recovering:
            updateProgressRow(String(localized: "Updating & restarting…"))
        case .blocked:
            VStack(alignment: .leading, spacing: 10) {
                updateMessageRow(systemImage: "clock", tint: .secondary)
                updateActionButton(title: String(localized: "Retry update"))
            }
        case .failed:
            VStack(alignment: .leading, spacing: 10) {
                updateMessageRow(systemImage: "exclamationmark.triangle", tint: .orange)
                updateActionButton(title: String(localized: "Retry update"))
            }
        }
    }

    private func updateActionButton(title: String) -> some View {
        SettingsButton(title) {
            isConfirmingUpdate = true
        }
        // Mirror of the check button's `isUpdateApplyInFlight` guard: while a
        // forced check is running, block Update/Retry so apply can't race the
        // in-flight POST /api/updates/check (#308 review).
        .disabled(updateController.isCheckingForUpdates)
        .padding(.top, 4)
    }

    private func updateProgressRow(_ text: String) -> some View {
        HStack(spacing: 8) {
            ProgressView()

            Text(text)
                .font(AppFont.footnote())
                .foregroundStyle(.secondary)
        }
        .padding(.top, 4)
        .accessibilityElement(children: .combine)
    }

    private func updateMessageRow(systemImage: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)

            Text(updateController.updateApplyMessage ?? String(localized: "The update could not be applied."))
                .font(AppFont.footnote())
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func clearOfflineCache() async {
        guard !isClearingCache else {
            return
        }

        isClearingCache = true
        do {
            // Scoped to the active server only, so clearing one server's cache
            // never wipes another configured server's offline data (#18).
            try CacheStore.clearCache(for: server, in: modelContext)
            cacheStatusMessage = String(localized: "This server's offline cache was cleared.")
        } catch {
            cacheStatusMessage = String(localized: "Could not clear offline cache.")
        }
        isClearingCache = false
    }

    private func refreshNotificationPermissionStatus() async {
        let status = await ResponseCompletionNotificationService.authorizationStatus()
        notificationPermissionStatus = status

        if !status.allowsSettingsToggleOn {
            isResponseCompletionNotificationsEnabled = false
        }

        notificationStatusMessage = nil
    }

    private func enableResponseCompletionNotifications() async {
        let currentStatus = await ResponseCompletionNotificationService.authorizationStatus()
        notificationPermissionStatus = currentStatus

        switch currentStatus {
        case .authorized, .provisional, .ephemeral:
            isResponseCompletionNotificationsEnabled = true
            notificationStatusMessage = nil
        case .notDetermined:
            guard !hasRequestedResponseCompletionNotificationPermission else {
                isResponseCompletionNotificationsEnabled = false
                notificationStatusMessage = String(localized: "Permission not requested.")
                return
            }

            hasRequestedResponseCompletionNotificationPermission = true
            let granted = await ResponseCompletionNotificationService.requestAuthorization()
            let updatedStatus = await ResponseCompletionNotificationService.authorizationStatus()
            notificationPermissionStatus = updatedStatus
            isResponseCompletionNotificationsEnabled = granted && updatedStatus.allowsSettingsToggleOn
            notificationStatusMessage = isResponseCompletionNotificationsEnabled ? nil : notificationPermissionLabel(updatedStatus)
        case .denied:
            isResponseCompletionNotificationsEnabled = false
            notificationStatusMessage = notificationPermissionLabel(currentStatus)
        @unknown default:
            isResponseCompletionNotificationsEnabled = false
            notificationStatusMessage = String(localized: "Notifications unavailable.")
        }
    }

    private func notificationPermissionLabel(_ status: UNAuthorizationStatus) -> String {
        switch status {
        case .authorized, .provisional, .ephemeral:
            return String(localized: "iOS notifications allowed.")
        case .notDetermined:
            return String(localized: "iOS permission not requested.")
        case .denied:
            return String(localized: "iOS notifications disabled.")
        @unknown default:
            return String(localized: "Notifications unavailable.")
        }
    }
}

private extension UNAuthorizationStatus {
    var allowsSettingsToggleOn: Bool {
        switch self {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined, .denied:
            return false
        @unknown default:
            return false
        }
    }
}

private struct SessionIdentitySettingsEditor: View {
    @ScaledMetric(relativeTo: .caption) private var avatarPreviewSize: CGFloat = 36

    @Binding var displayName: String
    @Binding var initials: String
    @Binding var avatarStyleRawValue: String
    let previewInitials: String
    let previewStyle: SessionAvatarStyle
    let previewColor: Color
    let previewForeground: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                SessionIdentityAvatarBadge(
                    style: previewStyle,
                    initials: previewInitials,
                    color: previewColor,
                    foregroundColor: previewForeground,
                    size: avatarPreviewSize
                )

                VStack(alignment: .leading, spacing: 3) {
                    Text("Sessions Avatar")
                        .font(AppFont.subheadline(weight: .medium))

                    Text("Stored on this device only.")
                        .font(AppFont.caption())
                        .foregroundStyle(.secondary)
                }
            }

            SettingsPickerRow(
                title: String(localized: "Avatar Style"),
                systemImage: "person.crop.circle",
                selection: $avatarStyleRawValue
            ) {
                ForEach(SessionAvatarStyle.allCases) { style in
                    Text(style.title).tag(style.rawValue)
                }
            }

            SettingsDivider()

            SettingsTextFieldRow(title: String(localized: "Display Name"), text: $displayName, placeholder: NSFullUserName())

            SettingsDivider()

            SettingsTextFieldRow(title: String(localized: "Initials"), text: $initials, placeholder: previewInitials)
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView(authManager: AuthManager(), server: URL(staticString: "https://webui.example.test"))
    }
}
