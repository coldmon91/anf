import Foundation
@testable import anf

/// FileTransfer correctness: the expanded child-by-child copy of a single big
/// folder must produce an identical tree and register a single top-level undo
/// target (not one per child).
func runTransferTests() {
    MainActor.assumeIsolated {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent("anfxfer-\(UUID().uuidString)")
        let src = base.appendingPathComponent("big")
        let destDir = base.appendingPathComponent("dest")
        do {
            try fm.createDirectory(at: src.appendingPathComponent("sub"), withIntermediateDirectories: true)
            try fm.createDirectory(at: destDir, withIntermediateDirectories: true)
            for i in 0..<40 {   // ≥16 children triggers the expansion path
                try "data-\(i)".write(to: src.appendingPathComponent("f\(i).txt"),
                                      atomically: true, encoding: .utf8)
            }
            try "deep".write(to: src.appendingPathComponent("sub/deep.txt"),
                             atomically: true, encoding: .utf8)
        } catch { T.expect(false, "fixture setup threw: \(error)"); return }
        defer { try? fm.removeItem(at: base) }

        T.group("FileTransfer: expanded folder copy") {
            var finished = false
            FileTransfer.shared.transfer([src], into: destDir, move: false) { finished = true }
            let deadline = Date().addingTimeInterval(10)
            while !finished && Date() < deadline {
                RunLoop.main.run(until: Date().addingTimeInterval(0.02))
            }
            T.expect(finished, "transfer completed")

            let copied = destDir.appendingPathComponent("big")
            let names = (try? fm.contentsOfDirectory(atPath: copied.path)) ?? []
            T.equal(names.count, 41, "all 41 children copied")
            let deep = copied.appendingPathComponent("sub/deep.txt")
            T.equal((try? String(contentsOf: deep, encoding: .utf8)), "deep",
                    "nested content survives the child-by-child copy")

            // Undo removes the single top-level destination, not 41 leftovers.
            T.expect(FileUndo.shared.undo(), "undo reports success")
            T.expect(!fm.fileExists(atPath: copied.path), "undo removed the copied folder root")
            T.expect(fm.fileExists(atPath: src.path), "source untouched by undo")
        }
    }
}
