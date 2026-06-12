import Foundation

/// One snapshot in a vault's timeline.
struct VaultSnapshot: Identifiable, Hashable, Sendable {
    let id: String          // commit hash
    let date: Date
    let summary: String     // human label, e.g. "12 files changed"
}

/// The Vault engine: per-folder time-travel backup built on the system `git`
/// binary (every Mac with Command Line Tools has it). All operations run off
/// the main thread; auto-snapshots are debounced so disk stays idle. Git is an
/// implementation detail — nothing here leaks the word "commit" to the user.
///
/// We shell out to `git` rather than statically linking libgit2: in a
/// CLT-only / SwiftPM build, vendoring libgit2 + its transports (zlib, TLS,
/// libssh2) is a dependency swamp for zero user-visible gain on a
/// once-per-five-minutes workload. The boundary here (init/snapshot/log/
/// restore) is small enough to swap to libgit2 later without touching callers.
enum VaultService {
    static let snapshotPrefix = "anf-vault-snapshot-"

    /// Smart defaults injected into every new vault's .gitignore so the object
    /// store never swallows system cruft or dependency trees.
    static let defaultIgnore = """
    # macOS system junk
    .DS_Store
    .AppleDouble
    .LSOverride
    ._*

    # common build / temp caches
    node_modules/
    .sass-cache/
    *.log
    *.tmp
    *.crdownload
    """

    private static var git: String { "/usr/bin/git" }

    /// Nested-vault isolation folder used when the directory already has a
    /// user-owned `.git` (a real dev project) — we never touch their repo.
    static let isolatedDir = ".anf_vault"

    private static func hasUserGit(_ url: URL) -> Bool {
        // A `.git` exists that we did NOT create (no isolated marker beside it).
        var isDir: ObjCBool = false
        let dotGit = url.appendingPathComponent(".git")
        guard FileManager.default.fileExists(atPath: dotGit.path, isDirectory: &isDir),
              isDir.boolValue else { return false }
        return !FileManager.default.fileExists(
            atPath: url.appendingPathComponent("\(isolatedDir)/.anf_owned").path)
    }

    /// Where this folder's vault store lives: the directory root for plain
    /// folders, or an isolated `.anf_vault/` work tree when the folder already
    /// has the user's own git repo (so we never collide with their history).
    static func storeURL(for folder: URL) -> URL {
        isVaultIsolated(folder) ? folder.appendingPathComponent(isolatedDir) : folder
    }

    private static func isVaultIsolated(_ url: URL) -> Bool {
        FileManager.default.fileExists(
            atPath: url.appendingPathComponent("\(isolatedDir)/.git").path)
    }

    /// A folder is a vault when anf has a store for it — either a root `.git`
    /// we own, or an isolated `.anf_vault/.git`.
    static func isVault(_ url: URL) -> Bool {
        if isVaultIsolated(url) { return true }
        var isDir: ObjCBool = false
        let dotGit = url.appendingPathComponent(".git")
        guard FileManager.default.fileExists(atPath: dotGit.path, isDirectory: &isDir),
              isDir.boolValue else { return false }
        // A root `.git` counts as OUR vault only if we marked it (so a plain dev
        // repo isn't mistaken for a vault).
        return FileManager.default.fileExists(
            atPath: url.appendingPathComponent(".anf_owned").path)
    }

    // MARK: - Lifecycle

    /// Turn `folder` into a vault: `git init`, write the smart .gitignore, set a
    /// local identity (so commits work without global git config), and take the
    /// first snapshot. Returns true on success. Runs synchronously — callers
    /// should dispatch off the main thread.
    @discardableResult
    static func initVault(at folder: URL) -> Bool {
        guard !isVault(folder) else { return true }
        let fm = FileManager.default

        let isolated = hasUserGit(folder)
        if isolated {
            // The folder is a real git project — never touch the user's repo.
            // The store lives in .anf_vault/.git with the folder as work tree.
            let store = folder.appendingPathComponent(isolatedDir)
            try? fm.createDirectory(at: store, withIntermediateDirectories: true)
            let gitDir = store.appendingPathComponent(".git").path
            guard ExternalTools.run(git, ["--git-dir", gitDir, "--work-tree", folder.path,
                                          "init"], maxLines: 100, timeout: 60) != nil,
                  fm.fileExists(atPath: gitDir) else { return false }
            appendToUserGitignore(folder)
        } else {
            guard run(["init"], folder: folder) != nil else { return false }
            // Mark this root .git as ours so a plain dev repo isn't seen as a vault.
            try? "".write(to: folder.appendingPathComponent(".anf_owned"),
                          atomically: true, encoding: .utf8)
        }

        _ = run(["config", "user.name", "anf vault"], folder: folder)
        _ = run(["config", "user.email", "vault@anf.local"], folder: folder)
        let ignore = folder.appendingPathComponent(".gitignore")
        if !isVaultIsolated(folder), !fm.fileExists(atPath: ignore.path) {
            try? defaultIgnore.write(to: ignore, atomically: true, encoding: .utf8)
        }
        return snapshot(at: folder, label: "initial")
    }

    /// Append the isolated-vault exclusion to the user's existing .gitignore so
    /// our store never pollutes their `git status`.
    private static func appendToUserGitignore(_ folder: URL) {
        let ignore = folder.appendingPathComponent(".gitignore")
        let marker = "\n# anf Vault\n\(isolatedDir)/\n"
        if let existing = try? String(contentsOf: ignore, encoding: .utf8) {
            if !existing.contains("\(isolatedDir)/") {
                try? (existing + marker).write(to: ignore, atomically: true, encoding: .utf8)
            }
        } else {
            try? marker.write(to: ignore, atomically: true, encoding: .utf8)
        }
    }

    /// Stop protecting a folder: remove our store (and the marker / ignore line).
    /// The user's files — and their own `.git` — are untouched.
    static func disableVault(at folder: URL) {
        let fm = FileManager.default
        if isVaultIsolated(folder) {
            try? fm.removeItem(at: folder.appendingPathComponent(isolatedDir))
        } else {
            try? fm.removeItem(at: folder.appendingPathComponent(".git"))
            try? fm.removeItem(at: folder.appendingPathComponent(".anf_owned"))
        }
    }

    // MARK: - Snapshots

    /// Stage everything and commit, but ONLY if there are changes (an empty
    /// commit would bloat the log). Returns true if a snapshot was taken.
    @discardableResult
    static func snapshot(at folder: URL, label: String = "") -> Bool {
        _ = run(["add", "--all"], folder: folder)
        // `git diff --cached --quiet` exits 1 when there's something staged.
        if runStatus(["diff", "--cached", "--quiet"], folder: folder) == 0 {
            return false   // nothing changed
        }
        let stamp = ISO8601Stamp.now()
        let msg = "\(snapshotPrefix)\(stamp)\(label.isEmpty ? "" : " (\(label))")"
        return run(["commit", "-m", msg], folder: folder) != nil
    }

    /// The timeline, newest first.
    static func snapshots(at folder: URL, limit: Int = 200) -> [VaultSnapshot] {
        let out = run(["log", "--pretty=format:%H\u{1f}%ct\u{1f}%s",
                       "-n", "\(limit)"], folder: folder) ?? []
        return out.compactMap { line in
            let f = line.components(separatedBy: "\u{1f}")
            guard f.count == 3, let secs = Double(f[1]) else { return nil }
            return VaultSnapshot(id: f[0], date: Date(timeIntervalSince1970: secs),
                                 summary: humanSummary(f[2]))
        }
    }

    /// Files present in a snapshot but missing from the working tree now —
    /// candidates for "recover a deleted file".
    static func deletedSince(_ snapshot: VaultSnapshot, at folder: URL) -> [String] {
        let inSnap = run(["ls-tree", "-r", "--name-only", snapshot.id], folder: folder) ?? []
        let fm = FileManager.default
        return inSnap.filter { !fm.fileExists(atPath: folder.appendingPathComponent($0).path) }
    }

    /// Restore one file from a snapshot back to its original path (overwrites if
    /// it exists). Returns true on success.
    @discardableResult
    static func restore(_ relativePath: String, from snapshot: VaultSnapshot, at folder: URL) -> Bool {
        // `git checkout <hash> -- <path>` writes the file back to the work tree.
        runStatus(["checkout", snapshot.id, "--", relativePath], folder: folder) == 0
    }

    // MARK: - Maintenance

    /// Compact loose objects + prune unreachable ones (the debloat pass).
    static func compact(at folder: URL) {
        _ = run(["gc", "--auto", "--quiet"], folder: folder)
    }

    // MARK: - git plumbing

    /// Base args that point git at the right store. For an isolated vault the
    /// store lives in `.anf_vault/.git` but tracks the parent folder as its work
    /// tree; for a plain vault `-C folder` is enough.
    private static func base(_ folder: URL) -> [String] {
        if isVaultIsolated(folder) {
            return ["--git-dir", folder.appendingPathComponent("\(isolatedDir)/.git").path,
                    "--work-tree", folder.path, "-C", folder.path]
        }
        return ["-C", folder.path]
    }

    private static func run(_ args: [String], folder: URL) -> [String]? {
        ExternalTools.run(git, base(folder) + args, maxLines: 100_000, timeout: 60)
    }

    /// Run for the EXIT CODE (used for `diff --quiet`, `checkout`).
    private static func runStatus(_ args: [String], folder: URL) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: git)
        p.arguments = base(folder) + args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run(); p.waitUntilExit(); return p.terminationStatus }
        catch { return -1 }
    }
}

/// Compact ISO-ish timestamp safe for a commit subject (no spaces/colons).
enum ISO8601Stamp {
    static func now() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        f.timeZone = .current
        return f.string(from: Date())
    }
}

private func humanSummary(_ subject: String) -> String {
    // Hide the internal prefix; show the readable tail or a generic label.
    if let r = subject.range(of: "(") { return String(subject[r.lowerBound...]).trimmingCharacters(in: CharacterSet(charactersIn: "()")) }
    return L("Snapshot", "스냅샷")
}
