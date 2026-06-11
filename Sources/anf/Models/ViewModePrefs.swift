import Foundation

/// Per-folder view mode (icons / list / columns / gallery), persisted.
///
/// Only EXPLICIT changes are recorded (the user picking a mode while in a
/// folder), and a folder with no setting of its own inherits the nearest
/// ancestor's — so making ~/Photos a grid makes every album inside a grid too,
/// without each subfolder needing its own entry. Setting a mode on a folder
/// also clears stale settings recorded deeper in its subtree, so the whole
/// tree follows the newest choice.
@MainActor
final class ViewModePrefs {
    static let shared = ViewModePrefs()
    private var map: [String: String]
    // v2: v1 stamped every *visited* folder (record-on-leave), which froze
    // subfolders against ancestor changes; that data would defeat inheritance.
    private let key = "anf.viewmode.byFolder.v2"
    private let cap = 2_000
    private let maxDepth = 64

    private init() {
        map = UserDefaults.standard.dictionary(forKey: key) as? [String: String] ?? [:]
    }

    /// The folder's own mode, or the nearest ancestor's.
    func mode(for url: URL) -> ViewMode? {
        var u = url.standardizedFileURL
        for _ in 0..<maxDepth {
            if let m = map[u.path].flatMap(ViewMode.init) { return m }
            guard u.path != "/", !u.path.isEmpty else { return nil }
            let parent = u.deletingLastPathComponent()
            guard parent.path != u.path else { return nil }
            u = parent
        }
        return nil
    }

    func set(_ mode: ViewMode, for url: URL) {
        let path = url.standardizedFileURL.path
        // The newest explicit choice governs the whole subtree.
        let subtree = path.hasSuffix("/") ? path : path + "/"
        for k in map.keys where k.hasPrefix(subtree) {
            map.removeValue(forKey: k)
        }
        map[path] = mode.rawValue
        if map.count > cap {   // crude bound; oldest-insertion order isn't tracked
            map.removeValue(forKey: map.keys.first!)
        }
        UserDefaults.standard.set(map, forKey: key)
    }
}
