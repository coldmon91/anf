import Foundation

/// How the listing is grouped (Finder's "Arrange by"). `.none` is a plain flat
/// list. Grouping reorders items so same-bucket entries are adjacent and inserts a
/// header before each bucket; it's independent of the sort within each bucket.
enum GroupKey: String, CaseIterable, Identifiable {
    case none, kind, dateModified, size
    var id: String { rawValue }
    var title: String {
        switch self {
        case .none:         return L("None", "없음")
        case .kind:         return L("Kind", "종류")
        case .dateModified: return L("Date Modified", "수정일")
        case .size:         return L("Size", "크기")
        }
    }
}

/// A contiguous run of items sharing a group bucket, with the header label and the
/// slice it covers in the (reordered) items array.
struct FileGroup: Equatable {
    let title: String
    let range: Range<Int>
}

enum FileGrouping {
    /// Reorder `items` (already sorted) into group buckets, preserving the incoming
    /// sort order within each bucket, and return the reordered items plus the group
    /// ranges. For `.none`, returns the input unchanged with no groups.
    static func group(_ items: [FileItem], by key: GroupKey) -> (items: [FileItem], groups: [FileGroup]) {
        guard key != .none, !items.isEmpty else { return (items, []) }

        // Stable bucketing: keep the first-seen bucket order would ignore the
        // intended ordering, so each bucket carries an explicit sort rank.
        var order: [String: Int] = [:]      // label → bucket rank (lower = first)
        var buckets: [String: [FileItem]] = [:]
        for item in items {
            let (rank, label) = bucket(item, by: key)
            if order[label] == nil { order[label] = rank }
            buckets[label, default: []].append(item)
        }
        let labels = order.keys.sorted {
            order[$0]! != order[$1]! ? order[$0]! < order[$1]!
                                     : $0.localizedStandardCompare($1) == .orderedAscending
        }

        var out: [FileItem] = []; out.reserveCapacity(items.count)
        var groups: [FileGroup] = []
        for label in labels {
            let slice = buckets[label]!
            groups.append(FileGroup(title: label, range: out.count ..< out.count + slice.count))
            out.append(contentsOf: slice)
        }
        return (out, groups)
    }

    /// (rank, label) for an item under a group key. Rank orders the buckets;
    /// label is the header text and the bucket identity.
    private static func bucket(_ item: FileItem, by key: GroupKey) -> (Int, String) {
        switch key {
        case .none:
            return (0, "")
        case .kind:
            // Folders lead, then by localized kind name.
            if item.isBrowsableContainer { return (0, L("Folders", "폴더")) }
            return (1, Format.kind(item))
        case .dateModified:
            return dateBucket(item.modified)
        case .size:
            return sizeBucket(item)
        }
    }

    private static func dateBucket(_ date: Date) -> (Int, String) {
        guard date > .distantPast else { return (99, L("Unknown", "알 수 없음")) }
        let cal = Calendar.current
        let now = Date()
        if cal.isDateInToday(date)     { return (0, L("Today", "오늘")) }
        if cal.isDateInYesterday(date) { return (1, L("Yesterday", "어제")) }
        let days = cal.dateComponents([.day], from: date, to: now).day ?? 0
        if days < 7   { return (2, L("Past 7 Days", "지난 7일")) }
        if days < 30  { return (3, L("Past 30 Days", "지난 30일")) }
        if days < 365 { return (4, L("Past Year", "지난 1년")) }
        return (5, L("Earlier", "그 이전"))
    }

    private static func sizeBucket(_ item: FileItem) -> (Int, String) {
        if item.isBrowsableContainer { return (0, L("Folders", "폴더")) }
        switch item.size {
        case 0:                 return (1, L("Zero KB", "0 KB"))
        case ..<100_000:        return (2, L("Tiny (< 100 KB)", "아주 작음 (< 100 KB)"))
        case ..<10_000_000:     return (3, L("Small (< 10 MB)", "작음 (< 10 MB)"))
        case ..<100_000_000:    return (4, L("Medium (< 100 MB)", "보통 (< 100 MB)"))
        case ..<1_000_000_000:  return (5, L("Large (< 1 GB)", "큼 (< 1 GB)"))
        default:                return (6, L("Huge (≥ 1 GB)", "아주 큼 (≥ 1 GB)"))
        }
    }
}
