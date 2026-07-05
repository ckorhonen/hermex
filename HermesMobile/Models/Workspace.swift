import Foundation

struct WorkspacesResponse: Decodable, Equatable {
    let workspaces: [WorkspaceRoot]?
    let last: String?
}

struct WorkspaceSuggestionsResponse: Decodable, Equatable {
    let suggestions: [String]?
    let prefix: String?
}

struct WorkspaceRoot: Decodable, Equatable, Sendable {
    let path: String?
    let name: String?

    enum CodingKeys: String, CodingKey {
        case path
        case name
    }

    init(from decoder: Decoder) throws {
        if let stringValue = try? decoder.singleValueContainer().decode(String.self) {
            path = stringValue
            name = nil
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = try container.decodeIfPresent(String.self, forKey: .path)
        name = try container.decodeIfPresent(String.self, forKey: .name)
    }
}

struct DirectoryListResponse: Decodable, Equatable {
    let entries: [WorkspaceEntry]?
    let path: String?
    let workspace: String?
    let error: String?
}

struct WorkspaceEntry: Decodable, Equatable, Identifiable {
    var id: String { path ?? name ?? UUID().uuidString }
    var isBrowsableDirectory: Bool {
        isDirectory == true || type == "dir"
    }

    let name: String?
    let path: String?
    let type: String?
    let size: Int?
    let modified: Double?
    let isDirectory: Bool?

    enum CodingKeys: String, CodingKey {
        case name
        case path
        case type
        case size
        case modified
        case isDirectory
        case isDir
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = container.decodeLossyStringIfPresent(forKey: .name)
        path = container.decodeLossyStringIfPresent(forKey: .path)
        type = container.decodeLossyStringIfPresent(forKey: .type)
        size = container.decodeLossyIntIfPresent(forKey: .size)
        modified = container.decodeLossyDoubleIfPresent(forKey: .modified)
        isDirectory = container.decodeLossyBoolIfPresent(forKey: .isDirectory)
            ?? container.decodeLossyBoolIfPresent(forKey: .isDir)
    }
}

struct FileResponse: Decodable, Equatable {
    let content: String?
    let path: String?
    let name: String?
    let language: String?
    let size: Int?
    let lines: Int?
    let error: String?
}
