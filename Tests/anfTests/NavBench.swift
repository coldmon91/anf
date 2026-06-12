import Foundation
@testable import anf

/// Soak: walk EVERY directory under a root through the production read+sort
/// path and report the worst offenders. Run with
///   ANF_SOAK=/Users/zihado/work swift run anfTests
/// Surfaces pathological folders (huge counts, slow sorts, unreadable dirs)
/// that ad-hoc testing never visits.
func runSoak(root: String) {
    let clock = ContinuousClock()
    @inline(__always) func ms(_ d: Duration) -> Double { Double(d.components.seconds) * 1_000 + Double(d.components.attoseconds) / 1e15 }

    var queue = [root]
    var visited = 0, unreadable = 0
    var worst: [(ms: Double, count: Int, path: String)] = []
    var biggest: [(count: Int, path: String)] = []
    let t0 = clock.now

    while let dir = queue.popLast() {
        guard let entries = FastDirRead.list(path: dir) else { unreadable += 1; continue }
        visited += 1
        let tSort0 = clock.now
        let items = entries.map { FileItem.fast(parentPath: dir, entry: $0) }
        let sorted = FileSystemService.fastNameSort(items, ascending: true)
        let elapsed = ms(clock.now - tSort0)

        worst.append((elapsed, sorted.count, dir))
        worst.sort { $0.ms > $1.ms }
        if worst.count > 10 { worst.removeLast() }
        biggest.append((sorted.count, dir))
        biggest.sort { $0.count > $1.count }
        if biggest.count > 10 { biggest.removeLast() }

        for e in entries where e.isDir && !e.isSymlink {
            // Skip bundle-ish/dependency trees a user wouldn't browse item by item?
            // No — browse EVERYTHING; that's the point of a soak.
            queue.append((dir as NSString).appendingPathComponent(e.name))
        }
    }
    print("soak: \(visited) dirs under \(root) in \(String(format: "%.1fs", ms(clock.now - t0) / 1000)) (\(unreadable) unreadable)")
    print("slowest build+sort:")
    for w in worst {
        print(String(format: "  %7.1fms  %6d items  %@", w.ms, w.count, w.path))
    }
    print("largest:")
    for b in biggest {
        print(String(format: "  %6d items  %@", b.count, b.path))
    }
}

/// Large-copy bench through the production FileTransfer path. Run with
///   ANF_BENCH_COPY=/folder swift run anfTests
/// Copies the folder into a temp dir (same volume → APFS clones), printing
/// wall time and verifying the entry count; cleans up afterwards.
@MainActor
func runCopyBench(src: String) {
    let clock = ContinuousClock()
    let fm = FileManager.default
    let srcURL = URL(fileURLWithPath: src)
    let destDir = fm.temporaryDirectory.appendingPathComponent("anf-copybench-\(UUID().uuidString)")
    try? fm.createDirectory(at: destDir, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: destDir) }

    var finished = false
    let t0 = clock.now
    FileTransfer.shared.transfer([srcURL], into: destDir, move: false) { finished = true }
    let deadline = Date().addingTimeInterval(600)
    while !finished && Date() < deadline {
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }
    let d = clock.now - t0
    let secs = Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18

    func count(_ url: URL) -> Int {
        var n = 0
        if let en = fm.enumerator(at: url, includingPropertiesForKeys: nil) {
            for case _ as URL in en { n += 1 }
        }
        return n
    }
    let copied = destDir.appendingPathComponent(srcURL.lastPathComponent)
    print(String(format: "copy bench: %@ → temp in %.1fs (src %d entries, dest %d entries)",
                 srcURL.lastPathComponent, secs, count(srcURL), count(copied)))
}

/// PDF body-extraction latency breakdown. Run with
///   ANF_BENCH_PDF=/folder/with/pdfs swift run anfTests
/// Prints per-file size/pages/ms plus the worst case and the wall-clock of the
/// same parallel sweep `docContent` performs during a palette search.
func runPDFBench(path: String) {
    let clock = ContinuousClock()
    @inline(__always) func ms(_ d: Duration) -> Double {
        Double(d.components.seconds) * 1_000 + Double(d.components.attoseconds) / 1e15
    }
    let fm = FileManager.default
    var pdfs: [URL] = []
    if let walker = fm.enumerator(at: URL(fileURLWithPath: path),
                                  includingPropertiesForKeys: [.fileSizeKey]) {
        for case let url as URL in walker where url.pathExtension.lowercased() == "pdf" {
            pdfs.append(url)
        }
    }
    print("pdf bench: \(pdfs.count) files under \(path)")
    var total = 0.0, worst = (0.0, "")
    for url in pdfs {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let t0 = clock.now
        let body = DocumentText.extract(url)
        let elapsed = ms(clock.now - t0)
        total += elapsed
        if elapsed > worst.0 { worst = (elapsed, url.lastPathComponent) }
        print(String(format: "  %7.1fms  %6.1fKB  %7d chars  %@",
                     elapsed, Double(size) / 1024, body?.count ?? 0, url.lastPathComponent))
    }
    print(String(format: "serial total %.0fms, worst %.0fms (%@)", total, worst.0, worst.1))

    // The palette path: parallel sweep through the cache, same as docContent.
    // Cold = first query of a session; warm = every following keystroke.
    for label in ["cold", "warm"] {
        let t0 = clock.now
        DispatchQueue.concurrentPerform(iterations: pdfs.count) { i in
            _ = DocumentTextCache.shared.text(for: pdfs[i])?
                .localizedCaseInsensitiveContains("zz없는단어zz")
        }
        print(String(format: "parallel sweep (%@ cache): %.0fms wall", label, ms(clock.now - t0)))
    }
}

/// Folder-entry latency breakdown. Not part of the pass/fail suite — run with
///   ANF_BENCH=/path/to/big/folder swift run anfTests
/// and it prints where the milliseconds go (bulk read → FileItem build → sort).
func runNavBench(path: String) {
    @inline(__always) func ms(_ t: ContinuousClock.Instant, _ u: ContinuousClock.Instant) -> String {
        String(format: "%6.1fms", Double((u - t).components.seconds) * 1_000 + Double((u - t).components.attoseconds) / 1e15)
    }
    let clock = ContinuousClock()
    print("bench: \(path)")

    for round in 1...3 {
        let t0 = clock.now
        let raw = FastDirRead.list(path: path) ?? []
        let t1 = clock.now

        let url = URL(fileURLWithPath: path)
        let items: [FileItem] = MainActor.assumeIsolated {
            var sem: [FileItem] = []
            let group = DispatchGroup()
            group.enter()
            Task { @MainActor in
                sem = await FileSystemService().contentsFast(of: url, showHidden: false)
                group.leave()
            }
            while group.wait(timeout: .now()) == .timedOut {
                RunLoop.main.run(until: Date().addingTimeInterval(0.005))
            }
            return sem
        }
        let t2 = clock.now

        let sorted = MainActor.assumeIsolated {
            FileSystemService().filteredSorted(items, filter: "", by: SortOrder())
        }
        let t3 = clock.now

        print("  #\(round) raw=\(raw.count) bulkRead=\(ms(t0, t1))  contentsFast=\(ms(t1, t2))  sort=\(ms(t2, t3))  total=\(ms(t0, t3))  (\(sorted.count) items)")
    }
}
