import Foundation
import Observation

/// A saved search rule. All set conditions are AND'd together. Empty/`nil`
/// conditions are ignored, so an all-empty rule matches every file.
struct SmartRule: Codable, Hashable, Sendable {
    /// Case-insensitive substring of the file name. Empty = ignored.
    var nameContains: String = ""
    /// Lowercased extensions without the dot (e.g. `["pdf","docx"]`). Empty = any kind.
    var kindExtensions: [String] = []
    /// Only files modified within the last N days. `nil` = any time.
    var modifiedWithinDays: Int? = nil

    func matches(url: URL, modified: Date?) -> Bool {
        if !nameContains.isEmpty,
           !url.lastPathComponent.localizedCaseInsensitiveContains(nameContains) { return false }
        if !kindExtensions.isEmpty, !kindExtensions.contains(url.pathExtension.lowercased()) { return false }
        if let days = modifiedWithinDays {
            guard let m = modified, m >= Date().addingTimeInterval(-Double(days) * 86_400) else { return false }
        }
        return true
    }

    var isEmpty: Bool { nameContains.isEmpty && kindExtensions.isEmpty && modifiedWithinDays == nil }
}

/// A named saved search shown in the sidebar. Selecting it lists every file under
/// `scopePath` matching `rule`, recomputed live on each visit.
struct SmartFolder: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    var scopePath: String
    var rule: SmartRule

    init(id: UUID = UUID(), name: String, scopePath: String, rule: SmartRule) {
        self.id = id
        self.name = name
        self.scopePath = scopePath
        self.rule = rule
    }

    /// Synthetic address for this saved search; reuses normal navigation.
    var url: URL { URL(string: "anf://smartfolder/\(id.uuidString)")! }
}

/// Evaluates a `SmartFolder` against the filesystem. Walks `scopePath` once,
/// skipping hidden files and package contents, and returns matching file URLs up
/// to `cap`. Run off the main thread — a deep subtree walk can take a while.
enum SmartFolderQuery {
    static func evaluate(_ folder: SmartFolder, cap: Int = 2_000) -> [URL] {
        let root = URL(fileURLWithPath: (folder.scopePath as NSString).expandingTildeInPath)
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey]
        guard let en = fm.enumerator(at: root, includingPropertiesForKeys: keys,
                                     options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        var out: [URL] = []
        for case let url as URL in en {
            if out.count >= cap { break }
            guard let rv = try? url.resourceValues(forKeys: Set(keys)), rv.isRegularFile == true else { continue }
            if folder.rule.matches(url: url, modified: rv.contentModificationDate) { out.append(url) }
        }
        return out
    }
}

/// App-wide saved searches, persisted to UserDefaults as JSON. A singleton so both
/// the (per-window) sidebar and any `BrowserModel` resolving an `anf://smartfolder`
/// address share one source of truth; `@Observable` so the sidebar rebuilds on change.
@MainActor
@Observable
final class SmartFoldersStore {
    static let shared = SmartFoldersStore()

    private static let key = "anf.smartFolders.v1"
    private(set) var folders: [SmartFolder]

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode([SmartFolder].self, from: data) {
            folders = decoded
        } else {
            folders = []
        }
    }

    func folder(id: UUID) -> SmartFolder? { folders.first { $0.id == id } }

    func add(_ folder: SmartFolder) { folders.append(folder); persist() }

    func remove(id: UUID) { folders.removeAll { $0.id == id }; persist() }

    func rename(id: UUID, to name: String) {
        guard let i = folders.firstIndex(where: { $0.id == id }) else { return }
        folders[i].name = name
        persist()
    }

    func update(id: UUID, rule: SmartRule) {
        guard let i = folders.firstIndex(where: { $0.id == id }) else { return }
        folders[i].rule = rule
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(folders) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}
