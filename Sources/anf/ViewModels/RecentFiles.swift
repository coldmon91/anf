import Foundation

/// App-wide history of recently opened FILES (not folders — folders live in
/// `RecentFolders`), most-recent-first, persisted to UserDefaults. Backs the
/// "Recents" virtual location in the sidebar, mirroring Finder's Recents.
@MainActor
final class RecentFiles {
    static let shared = RecentFiles()

    private(set) var items: [URL]
    private let key = "anf.recentFiles.v1"
    private let cap = 100

    private init() {
        let paths = UserDefaults.standard.stringArray(forKey: key) ?? []
        items = paths.map { URL(fileURLWithPath: $0) }
    }

    /// Record an opened file: move it to the front, dedupe by path, cap length.
    func record(_ url: URL) {
        guard url.isFileURL else { return }
        let std = url.standardizedFileURL
        items.removeAll { $0.standardizedFileURL.path == std.path }
        items.insert(std, at: 0)
        if items.count > cap { items = Array(items.prefix(cap)) }
        persist()
    }

    private func persist() {
        UserDefaults.standard.set(items.map(\.path), forKey: key)
    }
}
