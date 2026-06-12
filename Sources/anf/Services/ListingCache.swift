import Foundation

/// Last known listing per folder (raw + sorted), so re-entering a big folder
/// paints instantly instead of waiting for the bulk read + sort. The fresh read
/// still runs right behind it and diff-replaces whatever changed, so the cache
/// can never show stale content for more than one read cycle (~100ms).
@MainActor
final class ListingCache {
    static let shared = ListingCache()

    struct Entry {
        let all: [FileItem]
        let sorted: [FileItem]
    }

    private var map: [String: Entry] = [:]
    private var lru: [String] = []   // most recently used last
    /// Bounded by total cached items, not folder count — one 26k folder costs
    /// what many small ones do. 60k items ≈ ~18 MB worst case.
    private let itemBudget = 60_000

    private func key(_ url: URL, hidden: Bool, sort: SortOrder) -> String {
        "\(url.path)|\(hidden)|\(sort.key.rawValue)|\(sort.ascending)"
    }

    func get(url: URL, hidden: Bool, sort: SortOrder) -> Entry? {
        let k = key(url, hidden: hidden, sort: sort)
        guard let entry = map[k] else { return nil }
        lru.removeAll { $0 == k }
        lru.append(k)
        return entry
    }

    func put(url: URL, hidden: Bool, sort: SortOrder, all: [FileItem], sorted: [FileItem]) {
        let k = key(url, hidden: hidden, sort: sort)
        map[k] = Entry(all: all, sorted: sorted)
        lru.removeAll { $0 == k }
        lru.append(k)
        var total = map.values.reduce(0) { $0 + $1.all.count }
        while total > itemBudget, let oldest = lru.first {
            total -= map[oldest]?.all.count ?? 0
            map.removeValue(forKey: oldest)
            lru.removeFirst()
        }
    }
}
