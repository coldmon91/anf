import Foundation

/// Filename search backed by the macOS Spotlight index via `NSMetadataQuery`.
/// This is an index lookup (not a disk walk), so it's fast and global. Results
/// are delivered once on `onResults`; ranking is done by the caller (FuzzyMatch).
@MainActor
final class MetadataFileSearch {
    /// Cap on items pulled from a single query — short queries can match a huge
    /// number of files; we only need enough for the fuzzy ranker to pick from.
    private let resultCap = 2000

    private var query: NSMetadataQuery?
    private var token: NSObjectProtocol?
    var onResults: (([URL]) -> Void)?

    func search(_ needle: String) {
        stop()
        let q = NSMetadataQuery()
        q.searchScopes = [NSMetadataQueryLocalComputerScope]
        q.predicate = NSPredicate(format: "kMDItemFSName CONTAINS[cd] %@", needle)
        q.sortDescriptors = []
        token = NotificationCenter.default.addObserver(
            forName: .NSMetadataQueryDidFinishGathering, object: q, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.gather() }
        }
        query = q
        q.start()
    }

    private func gather() {
        guard let q = query else { return }
        q.disableUpdates()
        let count = min(q.resultCount, resultCap)
        var urls: [URL] = []
        urls.reserveCapacity(count)
        for i in 0..<count {
            if let item = q.result(at: i) as? NSMetadataItem,
               let path = item.value(forAttribute: NSMetadataItemPathKey) as? String {
                urls.append(URL(fileURLWithPath: path))
            }
        }
        onResults?(urls)
    }

    func stop() {
        query?.stop()
        if let token { NotificationCenter.default.removeObserver(token) }
        token = nil
        query = nil
    }
}
