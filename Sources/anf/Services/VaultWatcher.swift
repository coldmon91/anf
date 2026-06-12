import Foundation
import CoreServices

/// Watches every active vault folder with FSEvents and takes a debounced
/// background snapshot once changes settle — so an actively-churning folder
/// never commits (or hitches) until the user stops typing/saving. Idle disk,
/// idle CPU: the anf promise.
@MainActor
final class VaultWatcher {
    static let shared = VaultWatcher()

    private struct Watch {
        let stream: FSEventStreamRef
        var debounce: DispatchWorkItem?
    }
    private var watches: [String: Watch] = [:]
    private let debounceSeconds: TimeInterval = 300   // 5-minute snapshot cadence

    /// The folders anf protects, persisted so watching resumes after relaunch.
    private let storeKey = "anf.vaults.v1"
    private(set) var vaultPaths: Set<String> {
        didSet { UserDefaults.standard.set(Array(vaultPaths), forKey: storeKey) }
    }

    private init() {
        vaultPaths = Set(UserDefaults.standard.stringArray(forKey: storeKey) ?? [])
        // Resume watching any vault that still exists.
        for path in vaultPaths where VaultService.isVault(URL(fileURLWithPath: path)) {
            startWatching(path)
        }
    }

    func isVault(_ url: URL) -> Bool { vaultPaths.contains(url.standardizedFileURL.path) }

    /// Turn a folder into a vault and begin protecting it (off the main thread).
    func enable(_ url: URL, completion: @escaping (Bool) -> Void) {
        let path = url.standardizedFileURL.path
        Task.detached(priority: .userInitiated) {
            let ok = VaultService.initVault(at: url)
            await MainActor.run {
                if ok {
                    self.vaultPaths.insert(path)
                    self.startWatching(path)
                }
                completion(ok)
            }
        }
    }

    /// Stop protecting a folder and remove its store.
    func disable(_ url: URL) {
        let path = url.standardizedFileURL.path
        stopWatching(path)
        vaultPaths.remove(path)
        Task.detached(priority: .utility) { VaultService.disableVault(at: url) }
    }

    /// Snapshot now (e.g. before the user does something risky), bypassing the
    /// debounce. Background.
    func snapshotNow(_ url: URL) {
        Task.detached(priority: .userInitiated) { _ = VaultService.snapshot(at: url) }
    }

    // MARK: - FSEvents

    private func startWatching(_ path: String) {
        guard watches[path] == nil else { return }
        var ctx = FSEventStreamContext(version: 0,
                                       info: Unmanaged.passUnretained(self).toOpaque(),
                                       retain: nil, release: nil, copyDescription: nil)
        let flags = UInt32(kFSEventStreamCreateFlagNoDefer
                           | kFSEventStreamCreateFlagWatchRoot
                           | kFSEventStreamCreateFlagUseCFTypes)
        // The C callback can't capture `path`; resolve the watched root from the
        // changed paths inside onChange instead.
        let cb: FSEventStreamCallback = { _, info, _, paths, _, _ in
            guard let info else { return }
            let me = Unmanaged<VaultWatcher>.fromOpaque(info).takeUnretainedValue()
            let cpaths = unsafeBitCast(paths, to: NSArray.self) as? [String] ?? []
            Task { @MainActor in me.onChange(changed: cpaths) }
        }
        guard let s = FSEventStreamCreate(kCFAllocatorDefault, cb, &ctx,
                                          [path] as CFArray,
                                          FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                                          2.0, flags) else { return }
        FSEventStreamSetDispatchQueue(s, DispatchQueue.global(qos: .utility))
        FSEventStreamStart(s)
        watches[path] = Watch(stream: s, debounce: nil)
    }

    private func stopWatching(_ path: String) {
        guard let w = watches[path] else { return }
        w.debounce?.cancel()
        FSEventStreamStop(w.stream); FSEventStreamInvalidate(w.stream); FSEventStreamRelease(w.stream)
        watches.removeValue(forKey: path)
    }

    private func onChange(changed: [String]) {
        // Which watched vault(s) do these changes belong to? Ignore our own
        // plumbing churn (.git writes during a snapshot).
        let real = changed.filter { !$0.contains("/.git/") }
        let roots = Set(watches.keys.filter { root in
            real.contains { $0 == root || $0.hasPrefix(root + "/") }
        })
        for root in roots {
            watches[root]?.debounce?.cancel()
            let url = URL(fileURLWithPath: root)
            let work = DispatchWorkItem {
                Task.detached(priority: .utility) { _ = VaultService.snapshot(at: url) }
            }
            watches[root]?.debounce = work
            DispatchQueue.main.asyncAfter(deadline: .now() + debounceSeconds, execute: work)
        }
    }
}
