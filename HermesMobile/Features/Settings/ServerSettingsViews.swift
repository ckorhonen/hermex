import SwiftUI
import SwiftData
import UIKit

// Server connection + multi-server Settings screens, split out of SettingsView.swift.

struct CustomHeadersSettingsView: View {
    @Bindable var authManager: AuthManager
    @State private var headers: [CustomHeader]
    @Environment(\.scenePhase) private var scenePhase

    init(authManager: AuthManager) {
        self.authManager = authManager
        _headers = State(initialValue: authManager.currentCustomHeaders)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                CustomHeadersEditor(headers: $headers)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Connection Headers")
        .navigationBarTitleDisplayMode(.inline)
        // Live-refresh the network clients on every edit (cheap, in-memory only)
        // but defer the slow Keychain write until the editor is dismissed so
        // typing never stutters.
        .onChange(of: headers) { _, newValue in
            authManager.updateCustomHeaders(newValue, persist: false)
        }
        .onDisappear {
            authManager.updateCustomHeaders(headers, persist: true)
        }
        // onDisappear doesn't fire when the app is backgrounded or terminated
        // mid-edit, so also flush to the Keychain when the scene leaves active.
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                authManager.updateCustomHeaders(headers, persist: true)
            }
        }
    }
}

// MARK: - Multi-server (#17)

/// Small circular avatar (initials + per-server Header Logo Color) for server rows.
private struct ServerAvatarBadge: View {
    let initials: String
    let colorHex: String
    var size: CGFloat = 32

    var body: some View {
        Text(initials)
            .font(AppFont.caption(weight: .semibold))
            .foregroundStyle(HeaderLogoColor.prefersDarkForeground(for: colorHex) ? Color.black : Color.white)
            .frame(width: size, height: size)
            .background(HeaderLogoColor.color(for: colorHex), in: Circle())
            .overlay(Circle().stroke(.white.opacity(0.18), lineWidth: 1))
            .accessibilityHidden(true)
    }
}

/// One row in the Settings "Servers" list: avatar, name, URL, and an active marker.
struct SettingsServerRow: View {
    let account: ServerAccount
    let isActive: Bool

    private var hostFallback: String {
        URL(string: account.urlString)?.host ?? account.urlString
    }

    private var name: String {
        account.displayName.isEmpty ? hostFallback : account.displayName
    }

    private var previewInitials: String {
        SessionIdentitySettings.displayInitials(
            displayName: account.displayName,
            storedInitials: account.initials,
            fallbackFullName: hostFallback
        )
    }

    var body: some View {
        HStack(spacing: 12) {
            ServerAvatarBadge(initials: previewInitials, colorHex: account.headerLogoColorHex)

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(AppFont.subheadline(weight: .medium))
                    .lineLimit(1)

                Text(account.urlString)
                    .font(AppFont.caption())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            if isActive {
                SettingsStatusPill(label: String(localized: "Active"))
            }

            Image(systemName: "chevron.forward")
                .font(AppFont.caption(weight: .semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isActive ? String(localized: "\(name), \(account.urlString), active server") : String(localized: "\(name), \(account.urlString)"))
        .accessibilityHint("Opens server details to switch, edit, or remove.")
    }
}

/// Reusable per-server identity editor (display name, initials, Header Logo Color),
/// used by the add-server flow and the server detail screen (#17).
private struct ServerIdentityEditor: View {
    @Binding var displayName: String
    @Binding var initials: String
    @Binding var colorHex: String
    /// Host-derived fallback used for the avatar preview when fields are empty.
    let fallbackName: String

    private var previewInitials: String {
        SessionIdentitySettings.displayInitials(
            displayName: displayName.isEmpty ? fallbackName : displayName,
            storedInitials: initials,
            fallbackFullName: fallbackName
        )
    }

    private var initialsBinding: Binding<String> {
        Binding(
            get: { initials },
            set: { initials = SessionIdentitySettings.normalizedInitials($0) }
        )
    }

    private var colorBinding: Binding<Color> {
        Binding(
            get: { HeaderLogoColor.color(for: colorHex) },
            set: { if let hex = HeaderLogoColor.hexString(from: $0) { colorHex = hex } }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ServerAvatarBadge(initials: previewInitials, colorHex: colorHex, size: 36)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Server Avatar")
                        .font(AppFont.subheadline(weight: .medium))

                    Text("Stored on this device only.")
                        .font(AppFont.caption())
                        .foregroundStyle(.secondary)
                }
            }

            SettingsTextFieldRow(
                title: String(localized: "Display Name"),
                text: $displayName,
                placeholder: fallbackName.isEmpty ? String(localized: "Server") : fallbackName
            )

            SettingsDivider()

            SettingsTextFieldRow(title: String(localized: "Initials"), text: initialsBinding, placeholder: previewInitials)

            SettingsDivider()

            HeaderLogoColorSettings(selectedHex: $colorHex, customColor: colorBinding)
        }
    }
}

/// Per-server detail: identity editing, switch-to-active, and remove/sign-out (#17).
struct ServerDetailView: View {
    @Bindable var authManager: AuthManager
    let account: ServerAccount

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var displayName: String
    @State private var initials: String
    @State private var colorHex: String
    @State private var isConfirmingRemove = false
    @State private var isRemoving = false

    init(authManager: AuthManager, account: ServerAccount) {
        self.authManager = authManager
        self.account = account
        _displayName = State(initialValue: account.displayName)
        _initials = State(initialValue: account.initials)
        _colorHex = State(initialValue: account.headerLogoColorHex)
    }

    private var isActive: Bool { account.id == authManager.activeServerID }
    private var hasOtherServers: Bool { authManager.servers.count > 1 }
    private var hostFallback: String { URL(string: account.urlString)?.host ?? account.urlString }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                SettingsCard(title: String(localized: "Server")) {
                    SettingsInfoRow(title: String(localized: "URL"), value: account.urlString, valueIsSelectable: true)

                    SettingsDivider()

                    SettingsValueRow(title: String(localized: "Status")) {
                        SettingsStatusPill(label: isActive ? String(localized: "Active") : String(localized: "Inactive"))
                    }
                }

                SettingsCard(title: String(localized: "Identity")) {
                    ServerIdentityEditor(
                        displayName: $displayName,
                        initials: $initials,
                        colorHex: $colorHex,
                        fallbackName: hostFallback
                    )
                }

                if !isActive {
                    SettingsCard(title: String(localized: "Active Server")) {
                        SettingsFootnote(String(localized: "Makes this the active server. Sessions, chats, and settings reload for it."))

                        SettingsButton(String(localized: "Switch to This Server")) {
                            authManager.switchActiveServer(to: account)
                        }
                    }
                }

                SettingsCard(title: isActive ? String(localized: "Account") : String(localized: "Remove Server")) {
                    SettingsFootnote(removeFootnote)

                    SettingsButton(removeButtonTitle, role: .destructive, isLoading: isRemoving) {
                        isConfirmingRemove = true
                    }
                    .disabled(isRemoving)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 36)
        }
        .background(Color(.systemBackground))
        .navigationTitle(displayName.isEmpty ? hostFallback : displayName)
        .navigationBarTitleDisplayMode(.inline)
        // Persist identity edits to this server's registry entry. When it's the
        // active server, the registry mirrors them into the global @AppStorage so
        // the avatar / header tint update live (#17).
        .onChange(of: displayName) { persistIdentity() }
        .onChange(of: initials) { persistIdentity() }
        .onChange(of: colorHex) { persistIdentity() }
        .alert(removeAlertTitle, isPresented: $isConfirmingRemove) {
            Button("Cancel", role: .cancel) {}
            Button(removeButtonTitle, role: .destructive) {
                Task {
                    let wasActive = isActive
                    isRemoving = true
                    // Purge this server's offline cache *before* removing it, while
                    // the view (and its modelContext) is still alive — removing the
                    // active server flips auth state and tears this stack down on
                    // its own. Best-effort: the cache is server-keyed, so a leftover
                    // row can never surface as another server's content (#18, PR
                    // #286 W2).
                    if let removedServerURL = URL(string: account.urlString) {
                        try? CacheStore.clearCache(for: removedServerURL, in: modelContext)
                    }
                    await authManager.removeServer(account)
                    // Only a non-active removal leaves this view alive to reset its
                    // state and pop; the active-server case is already torn down.
                    if !wasActive {
                        isRemoving = false
                        dismiss()
                    }
                }
            }
        } message: {
            Text(removeAlertMessage)
        }
    }

    private func persistIdentity() {
        authManager.updateServerIdentity(
            account,
            displayName: displayName,
            initials: initials,
            headerLogoColorHex: colorHex
        )
    }

    private var removeButtonTitle: String {
        isActive ? String(localized: "Sign Out of This Server") : String(localized: "Remove Server")
    }

    private var removeAlertTitle: String {
        isActive ? String(localized: "Sign out of this server?") : String(localized: "Remove this server?")
    }

    private var removeFootnote: String {
        if isActive {
            return hasOtherServers
                ? String(localized: "Signs out and switches to another configured server.")
                : String(localized: "Signs out and returns to onboarding.")
        }
        return String(localized: "Removes this server and its saved settings on this device. Your active server is unaffected.")
    }

    private var removeAlertMessage: String {
        if isActive {
            return hasOtherServers
                ? String(localized: "You'll switch to another configured server. Sign in again to use this one.")
                : String(localized: "You'll return to onboarding and need the server URL and password to sign back in.")
        }
        return String(localized: "This removes the server and its saved settings on this device. Your active server is unaffected.")
    }
}

/// Secondary onboarding/auth flow to add another server, collecting URL/password
/// (existing validation + login), custom headers, and per-server identity. Routes
/// through `AuthManager.addServer`, which never disturbs the active server on
/// failure (#17). Presented from Settings and from the session-list avatar
/// long-press switcher (#283).
struct AddServerView: View {
    @Bindable var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss

    @State private var serverURLString = ""
    @State private var password = ""
    @State private var customHeaders: [CustomHeader] = []
    @State private var needsPassword = false
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var displayName = ""
    @State private var initials = ""
    @State private var colorHex = HeaderLogoColor.defaultHex

    private var trimmedURL: String {
        serverURLString.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSubmit: Bool { !trimmedURL.isEmpty && !isWorking }

    private var derivedHost: String {
        (try? AuthManager.normalizedServerURL(from: serverURLString))?.host ?? ""
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    SettingsCard(title: String(localized: "Server")) {
                        SettingsTextFieldRow(
                            title: String(localized: "URL"),
                            text: $serverURLString,
                            placeholder: "100.64.0.1:8787",
                            keyboardType: .URL,
                            autocapitalization: .never,
                            submitLabel: .go,
                            onSubmit: { Task { await submit() } }
                        )

                        if needsPassword {
                            SettingsDivider()

                            SettingsTextFieldRow(
                                title: String(localized: "Password"),
                                text: $password,
                                placeholder: String(localized: "Server password"),
                                autocapitalization: .never,
                                isSecure: true,
                                submitLabel: .go,
                                onSubmit: { Task { await submit() } }
                            )
                        }
                    }

                    SettingsCard(title: String(localized: "Connection Headers")) {
                        CustomHeadersEditor(headers: $customHeaders)
                    }

                    SettingsCard(title: String(localized: "Identity")) {
                        ServerIdentityEditor(
                            displayName: $displayName,
                            initials: $initials,
                            colorHex: $colorHex,
                            fallbackName: derivedHost
                        )
                    }

                    statusBanner
                }
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 36)
            }
            .background(Color(.systemBackground))
            .navigationTitle("Add Server")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { Task { await submit() } }
                        .disabled(!canSubmit)
                }
            }
        }
    }

    @ViewBuilder
    private var statusBanner: some View {
        if isWorking {
            SettingsFootnote(String(localized: "Checking server…"))
        } else if needsPassword, errorMessage == nil {
            SettingsFootnote(String(localized: "This server requires a password."))
        }

        if let errorMessage {
            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                .font(AppFont.footnote())
                .foregroundStyle(.orange)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func submit() async {
        guard canSubmit else { return }
        errorMessage = nil
        isWorking = true
        let outcome = await authManager.addServer(
            serverURLString: serverURLString,
            password: password,
            customHeaders: customHeaders
        )
        isWorking = false

        switch outcome {
        case .needsPassword:
            needsPassword = true
        case .failed:
            errorMessage = authManager.lastErrorMessage
        case let .added(url):
            applyIdentity(to: url)
            dismiss()
        }
    }

    /// Overrides the new server's seeded identity (the registry seeds it from the
    /// previous active server's global defaults) with the add-flow's chosen values.
    private func applyIdentity(to url: URL) {
        guard let account = authManager.servers.first(where: { $0.id == url.absoluteString }) else { return }

        let finalName = displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? (url.host ?? account.displayName)
            : displayName
        let finalInitials = SessionIdentitySettings.displayInitials(
            displayName: finalName,
            storedInitials: initials,
            fallbackFullName: url.host ?? finalName
        )
        authManager.updateServerIdentity(
            account,
            displayName: finalName,
            initials: finalInitials,
            headerLogoColorHex: colorHex
        )
    }
}
