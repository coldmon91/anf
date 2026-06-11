import Foundation
@testable import anf

/// Folder-entry latency breakdown. Not part of the pass/fail suite — run with
///   ANF_BENCH=/path/to/big/folder swift run anfTests
/// and it prints where the milliseconds go (bulk read → FileItem build → sort).
func runNavBench(path: String) {
    @inline(__always) func ms(_ t: ContinuousClock.Instant, _ u: ContinuousClock.Instant) -> String {
        String(format: "%6.1fms", Double((u - t).components.attoseconds) / 1e15)
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
