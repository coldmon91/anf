import Foundation

/// Directory loading off the main thread. Stateless + Sendable.
struct FileSystemService: Sendable {

    /// Reads the contents of `url`, prefetching all resource keys in one shot so each
    /// `FileItem` is built without extra stat() calls. Runs on a background task.
    func contents(of url: URL, showHidden: Bool) async -> [FileItem] {
        await Task.detached(priority: .userInitiated) {
            let fm = FileManager.default
            var options: FileManager.DirectoryEnumerationOptions = [.skipsSubdirectoryDescendants]
            if !showHidden { options.insert(.skipsHiddenFiles) }

            guard let urls = try? fm.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: Array(FileItem.resourceKeys),
                options: options
            ) else { return [] }

            return urls.compactMap { FileItem(url: $0) }
        }.value
    }

    /// Fast first-pass listing: only the keys needed to render names and sort
    /// (folder-ness), so a directory with tens of thousands of entries paints
    /// almost instantly. The full `contents(of:)` pass enriches it afterwards.
    func contentsFast(of url: URL, showHidden: Bool) async -> [FileItem] {
        await Task.detached(priority: .userInitiated) {
            // In a vault, the .git store and .gitignore are anf's plumbing — drop
            // them unconditionally (even with hidden files shown) so the user
            // never sees that Git is running underneath.
            let vault = VaultService.isVault(url)
            @inline(__always) func vaultHidden(_ name: String) -> Bool {
                vault && (name == ".git" || name == ".gitignore")
            }
            // Native bulk read (no per-item stat). Falls back to FileManager only
            // if getattrlistbulk is unavailable for this volume.
            if let entries = FastDirRead.list(path: url.path) {
                let parentPath = url.path
                // Build the items across all cores — URL construction alone is
                // ~100ms for 26k entries, so parallelising it is a real win.
                var out = [FileItem?](repeating: nil, count: entries.count)
                out.withUnsafeMutableBufferPointer { buf in
                    DispatchQueue.concurrentPerform(iterations: entries.count) { i in
                        let e = entries[i]
                        if (showHidden || !e.isHidden) && !vaultHidden(e.name) {
                            buf[i] = FileItem.fast(parentPath: parentPath, entry: e)
                        }
                    }
                }
                return out.compactMap { $0 }
            }
            let fm = FileManager.default
            var options: FileManager.DirectoryEnumerationOptions = [.skipsSubdirectoryDescendants]
            if !showHidden { options.insert(.skipsHiddenFiles) }
            guard let urls = try? fm.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: Array(FileItem.fastKeys),
                options: options
            ) else { return [] }
            return urls.compactMap { u in
                vaultHidden(u.lastPathComponent) ? nil : FileItem(fastURL: u)
            }
        }.value
    }

    /// Recursively sum the allocated size of everything under `url`. Off the main thread.
    func directorySize(of url: URL) async -> Int64 {
        await Task.detached(priority: .utility) {
            let fm = FileManager.default
            let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .fileSizeKey, .isRegularFileKey]
            guard let en = fm.enumerator(at: url, includingPropertiesForKeys: Array(keys),
                                         options: [.skipsHiddenFiles]) else { return 0 }
            var total: Int64 = 0
            for case let f as URL in en {
                let v = try? f.resourceValues(forKeys: keys)
                if v?.isRegularFile == true {
                    total += Int64(v?.totalFileAllocatedSize ?? v?.fileSize ?? 0)
                }
            }
            return total
        }.value
    }

    /// Filter by name (if any) then sort. Pure + Sendable so it can run off the
    /// main thread for large directories.
    func filteredSorted(_ items: [FileItem], filter: String, by order: SortOrder) -> [FileItem] {
        var result = items
        if !filter.isEmpty {
            result = result.filter { $0.name.localizedCaseInsensitiveContains(filter) }
        }
        // Fast path for the common name sort — see fastNameSort below.
        if order.key == .name {
            return Self.fastNameSort(result, ascending: order.ascending)
        }
        return sorted(result, by: order)
    }

    /// Name sort an order of magnitude faster than per-comparison collation: the
    /// first 16 lowercased UTF-8 bytes pack into two big-endian UInt64s, so the
    /// vast majority of the ~n·log n comparisons are two integer compares; only
    /// same-prefix ties fall back to a memcmp of the full key. Keys build in
    /// parallel. For NFC text (incl. Hangul, dictionary-ordered in Unicode) byte
    /// order matches expectations. 26k Hangul names: ~480ms → ~40ms.
    static func fastNameSort(_ items: [FileItem], ascending asc: Bool) -> [FileItem] {
        struct Key {
            var hi: UInt64 = 0, lo: UInt64 = 0
            var full: [UInt8] = []
            var dir = false
            var idx: Int32 = 0
        }
        let n = items.count
        var keys = [Key](repeating: Key(), count: n)
        keys.withUnsafeMutableBufferPointer { buf in
            let chunks = max(1, min(8, n / 2_048))
            let per = (n + chunks - 1) / chunks
            DispatchQueue.concurrentPerform(iterations: chunks) { c in
                for i in (c * per) ..< min((c + 1) * per, n) {
                    var k = Key(dir: items[i].isBrowsableContainer, idx: Int32(i))
                    k.full = Array(items[i].name.lowercased().utf8)
                    for (j, byte) in k.full.prefix(16).enumerated() {
                        if j < 8 { k.hi |= UInt64(byte) << (56 - j * 8) }
                        else { k.lo |= UInt64(byte) << (56 - (j - 8) * 8) }
                    }
                    buf[i] = k
                }
            }
        }
        keys.sort { a, b in
            if a.dir != b.dir { return a.dir }            // folders first, always
            if a.hi != b.hi { return asc ? a.hi < b.hi : a.hi > b.hi }
            if a.lo != b.lo { return asc ? a.lo < b.lo : a.lo > b.lo }
            let cmp = a.full.withUnsafeBufferPointer { ab in
                b.full.withUnsafeBufferPointer { bb -> Int32 in
                    let m = min(ab.count, bb.count)
                    let c = m == 0 ? 0 : memcmp(ab.baseAddress!, bb.baseAddress!, m)
                    if c != 0 { return c }
                    return Int32(ab.count) - Int32(bb.count)
                }
            }
            if cmp == 0 { return false }
            return asc ? cmp < 0 : cmp > 0
        }
        return keys.map { items[Int($0.idx)] }
    }

    /// Sort a snapshot. Directories always float to the top, matching Finder behaviour.
    func sorted(_ items: [FileItem], by order: SortOrder) -> [FileItem] {
        items.sorted { a, b in
            if a.isBrowsableContainer != b.isBrowsableContainer {
                return a.isBrowsableContainer
            }
            let result: Bool
            switch order.key {
            case .name:
                result = a.name.localizedStandardCompare(b.name) == .orderedAscending
            case .dateModified:
                result = a.modified < b.modified
            case .size:
                result = a.size < b.size
            case .kind:
                let ka = a.contentType?.localizedDescription ?? a.ext
                let kb = b.contentType?.localizedDescription ?? b.ext
                result = ka.localizedStandardCompare(kb) == .orderedAscending
            }
            return order.ascending ? result : !result
        }
    }
}
