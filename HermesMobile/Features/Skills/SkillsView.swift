import SwiftUI

struct SkillsView: View {
    let server: URL
    let onAPIError: (Error) -> Void

    @State private var viewModel: SkillsViewModel
    @State private var selectedSkill: SkillSummary?
    @State private var searchText = ""

    init(server: URL, onAPIError: @escaping (Error) -> Void) {
        self.server = server
        self.onAPIError = onAPIError
        _viewModel = State(initialValue: SkillsViewModel(server: server))
    }

    var body: some View {
        content
            .navigationTitle("Skills")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await loadSkills() }
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
            .task {
                await loadSkills()
            }
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search skills..."
            )
            .zoraBrandedScreen()
    }

    private var filteredGroups: [(category: String, skills: [SkillSummary])] {
        viewModel.filteredGroupedSkills(searchText: searchText)
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.skills.isEmpty {
            ZoraLoadingStateView(title: "Loading skills...")
        } else if let errorMessage = viewModel.errorMessage, viewModel.skills.isEmpty {
            ZoraUnavailableStateView(
                title: "Could Not Load Skills",
                systemImage: "exclamationmark.triangle",
                message: errorMessage,
                actionTitle: "Try Again"
            ) {
                Task { await loadSkills() }
            }
        } else if viewModel.skills.isEmpty {
            ZoraUnavailableStateView(
                title: "No Skills",
                systemImage: "hammer",
                message: "Skills from the Hermes server will appear here."
            )
        } else if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && filteredGroups.isEmpty {
            ZoraUnavailableStateView(
                title: "No Results",
                systemImage: "magnifyingglass",
                message: "No skills match \"\(searchText)\"."
            )
        } else {
            ZoraScrollContent(spacing: 24) {
                ForEach(filteredGroups, id: \.category) { group in
                    SkillCategorySection(
                        category: group.category,
                        skills: group.skills,
                        server: server,
                        onAPIError: onAPIError
                    )
                }
            }
            .refreshable {
                await loadSkills()
            }
        }
    }

    private func loadSkills() async {
        await viewModel.load()
        if let error = viewModel.lastError {
            onAPIError(error)
        }
    }
}

private struct SkillCategorySection: View {
    let category: String
    let skills: [SkillSummary]
    let server: URL
    let onAPIError: (Error) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZoraSectionHeader(category)

            VStack(spacing: 0) {
                ForEach(Array(skills.enumerated()), id: \.offset) { index, skill in
                    NavigationLink {
                        SkillDetailView(
                            skill: skill,
                            server: server,
                            onAPIError: onAPIError
                        )
                    } label: {
                        SkillRow(skill: skill)
                    }
                    .buttonStyle(.plain)

                    if index < skills.count - 1 {
                        ZoraDivider(leadingPadding: 58)
                    }
                }
            }
        }
    }
}

private struct SkillRow: View {
    let skill: SkillSummary

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "hammer")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: 40, height: 40)
                .background(ZoraBrand.subtleFill, in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(displayName)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                if let description {
                    Text(description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.forward")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .padding(.top, 12)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var displayName: String {
        let name = skill.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let name, !name.isEmpty else {
            return String(localized: "Unnamed Skill")
        }
        return name
    }

    private var description: String? {
        let text = skill.description?.trimmingCharacters(in: .whitespacesAndNewlines)
        return text?.isEmpty == false ? text : nil
    }
}

struct SkillDetailView: View {
    let skill: SkillSummary
    let server: URL
    let onAPIError: (Error) -> Void

    @State private var detail: SkillDetailResponse?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedFile: String?
    @State private var fileContent: String?
    @State private var isLoadingFile = false

    var body: some View {
        content
            .navigationTitle(skill.name ?? String(localized: "Skill"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await loadDetail() }
                    } label: {
                        if isLoading {
                            ProgressView()
                        } else {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                    }
                    .disabled(isLoading)
                }
            }
            .task {
                await loadDetail()
            }
            .sheet(item: $selectedFile) { fileName in
                NavigationStack {
                    SkillLinkedFileView(
                        fileName: fileName,
                        content: fileContent,
                        isLoading: isLoadingFile
                    )
                }
            }
            .zoraBrandedScreen()
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && detail == nil {
            ZoraLoadingStateView(title: "Loading skill...")
        } else if let errorMessage, detail == nil {
            ZoraUnavailableStateView(
                title: "Could Not Load Skill",
                systemImage: "exclamationmark.triangle",
                message: errorMessage,
                actionTitle: "Try Again"
            ) {
                Task { await loadDetail() }
            }
        } else if let detail {
            ZoraScrollContent(spacing: 16, topPadding: 16) {
                if let content = detail.content, !content.isEmpty {
                    MarkdownRenderer(content: content)
                }

                if let linkedFiles = detail.linkedFiles, !linkedFiles.isEmpty {
                    SkillLinkedFilesSection(
                        fileNames: linkedFiles,
                        onSelect: { fileName in
                            Task { await loadLinkedFile(named: fileName) }
                        }
                    )
                }
            }
        } else {
            ZoraUnavailableStateView(
                title: "No Content",
                systemImage: "doc.text",
                message: "This skill has no content."
            )
        }
    }

    private func loadDetail() async {
        guard let name = skill.name else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let response = try await APIClient.shared(for: server).skillContent(name: name)
            detail = response
        } catch {
            errorMessage = error.localizedDescription
            onAPIError(error)
        }
    }

    private func loadLinkedFile(named fileName: String) async {
        guard let name = skill.name else { return }
        isLoadingFile = true
        selectedFile = fileName
        defer { isLoadingFile = false }

        do {
            let response = try await APIClient.shared(for: server).skillContent(name: name, file: fileName)
            fileContent = response.content
        } catch {
            fileContent = String(localized: "Could not load file: \(error.localizedDescription)")
        }
    }
}

private struct SkillLinkedFilesSection: View {
    let fileNames: [String]
    let onSelect: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZoraSectionHeader("Linked Files", horizontalPadding: 20)

            VStack(spacing: 0) {
                ForEach(Array(fileNames.enumerated()), id: \.element) { index, fileName in
                    Button {
                        onSelect(fileName)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "doc.text")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                                .frame(width: 34, height: 34)
                                .background(ZoraBrand.subtleFill, in: Circle())

                            Text(fileName)
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                                .lineLimit(1)

                            Spacer(minLength: 8)

                            Image(systemName: "chevron.forward")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 9)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if index < fileNames.count - 1 {
                        ZoraDivider(leadingPadding: 54)
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }
}

struct SkillLinkedFileView: View {
    let fileName: String
    let content: String?
    let isLoading: Bool

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if isLoading {
                ZoraLoadingStateView(title: "Loading file...")
            } else if let content, !content.isEmpty {
                ZoraScrollContent(topPadding: 16) {
                    MarkdownRenderer(content: content)
                }
            } else {
                ZoraUnavailableStateView(
                    title: "No Content",
                    systemImage: "doc.text",
                    message: "This file appears to be empty."
                )
            }
        }
        .navigationTitle(fileName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") {
                    dismiss()
                }
            }
        }
    }
}

extension String: @retroactive Identifiable {
    public var id: String { self }
}
