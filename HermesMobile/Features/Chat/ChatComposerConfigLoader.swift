import Foundation

struct ChatComposerConfigState: Equatable, Sendable {
    var currentWorkspace: String?
    var currentModel: String?
    var currentModelProvider: String?
    var currentProfile: String?
    var selectedProfileName: String?
    var selectedReasoningEffort: String?
    var modelCatalogGroups: [ModelCatalogGroup]
    var agentCommands: [AgentCommand]
    var workspaceRoots: [WorkspaceRoot]
    var workspaceSuggestions: [String]
    var profileOptions: [ProfileSummary]

    init(
        currentWorkspace: String? = nil,
        currentModel: String? = nil,
        currentModelProvider: String? = nil,
        currentProfile: String? = nil,
        selectedProfileName: String? = nil,
        selectedReasoningEffort: String? = nil,
        modelCatalogGroups: [ModelCatalogGroup] = [],
        agentCommands: [AgentCommand] = [],
        workspaceRoots: [WorkspaceRoot] = [],
        workspaceSuggestions: [String] = [],
        profileOptions: [ProfileSummary] = []
    ) {
        self.currentWorkspace = currentWorkspace
        self.currentModel = currentModel
        self.currentModelProvider = currentModelProvider
        self.currentProfile = currentProfile
        self.selectedProfileName = selectedProfileName
        self.selectedReasoningEffort = selectedReasoningEffort
        self.modelCatalogGroups = modelCatalogGroups
        self.agentCommands = agentCommands
        self.workspaceRoots = workspaceRoots
        self.workspaceSuggestions = workspaceSuggestions
        self.profileOptions = profileOptions
    }
}

struct ChatComposerConfigLoadResult: Sendable {
    let state: ChatComposerConfigState
    let configurationError: Error?
}

struct ChatComposerConfigLoader {
    private let client: APIClient

    init(client: APIClient) {
        self.client = client
    }

    func loadConfiguration(from initialState: ChatComposerConfigState) async -> ChatComposerConfigLoadResult {
        var state = initialState
        var configurationError: Error?

        do {
            let profilesResponse = try await client.profiles()
            state.profileOptions = profilesResponse.profiles ?? []
            state.selectedProfileName = state.currentProfile.nonEmpty
                ?? profilesResponse.active.nonEmpty
                ?? profilesResponse.effectiveDefaultProfileName

            if let sessionProfile = state.currentProfile.nonEmpty,
               profilesResponse.active.nonEmpty != sessionProfile {
                let switchResponse = try await client.switchProfile(name: sessionProfile)
                state.profileOptions = switchResponse.profiles ?? state.profileOptions
                state.selectedProfileName = switchResponse.active.nonEmpty ?? sessionProfile
                state.currentProfile = state.selectedProfileName

                if state.currentWorkspace == nil {
                    state.currentWorkspace = switchResponse.defaultWorkspace.nonEmpty
                }

                if state.currentModel == nil {
                    state.currentModel = switchResponse.defaultModel.nonEmpty
                }
            }

            let selectedProfile = Self.profileSummary(
                matching: state.selectedProfileName,
                in: state.profileOptions
            )
            if state.currentModel == nil {
                state.currentModel = (selectedProfile?.model).nonEmpty
            }

            let modelsResponse = try await client.models()
            state.modelCatalogGroups = modelsResponse.catalogGroups
            if state.currentModel == nil {
                state.currentModel = modelsResponse.defaultModel
            }
            if state.currentModelProvider.nonEmpty == nil {
                state.currentModelProvider = (selectedProfile?.provider).nonEmpty
                    ?? Self.uniqueProvider(for: state.currentModel, in: state.modelCatalogGroups)
            }

            let reasoningResponse = try await client.reasoning()
            state.selectedReasoningEffort = reasoningResponse.effectiveEffort

            let workspaceResponse = try await client.workspaces()
            state.workspaceRoots = workspaceResponse.workspaces ?? []
            if state.currentWorkspace == nil {
                state.currentWorkspace = workspaceResponse.last ?? state.workspaceRoots.compactMap(\.path).first
            }
            state.workspaceSuggestions = state.workspaceRoots.compactMap(\.path)
        } catch {
            configurationError = error
        }

        do {
            state.agentCommands = (try await client.commands()).commands ?? []
        } catch {
            state.agentCommands = []
        }

        return ChatComposerConfigLoadResult(
            state: state,
            configurationError: configurationError
        )
    }

    private static func profileSummary(
        matching profileName: String?,
        in profileOptions: [ProfileSummary]
    ) -> ProfileSummary? {
        guard let profileName = profileName.nonEmpty else { return nil }
        return profileOptions.first { $0.normalizedName == profileName }
    }

    private static func uniqueProvider(
        for modelID: String?,
        in groups: [ModelCatalogGroup]
    ) -> String? {
        guard let modelID = modelID.nonEmpty else { return nil }
        let providers = Set(
            groups
                .flatMap(\.slashAutocompleteModels)
                .filter { $0.id == modelID }
                .compactMap { $0.providerID.nonEmpty }
        )
        return providers.count == 1 ? providers.first : nil
    }
}
