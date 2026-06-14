import Foundation
@testable import anf

/// Regression guards for iter22 fixes. Each group targets one bug ID.
/// A regression in the fix makes the corresponding group RED.
func runFixVerificationTests() {
    // ET-001 ─────────────────────────────────────────────────────────────────
    // Prior bug: process.standardError = Pipe() — child blocks on stderr write
    // once the ~64 KB pipe buffer fills, and waitUntilExit hangs indefinitely.
    // Fix: redirect stderr to FileHandle.nullDevice.
    T.group("ET-001: large stderr output does not hang ExternalTools.run") {
        // Write 100 KB to stderr, then "done" to stdout.
        // Without the fix the child blocks on the unread stderr pipe and the
        // call never returns (would time out here as a test failure).
        let result = ExternalTools.run(
            "/bin/sh",
            ["-c", "printf '%100000s' ' ' >&2; echo done"],
            timeout: 5)
        T.equal(result.first, "done",
                "process with 100 KB stderr completes and stdout is readable (ET-001)")
    }

    // FT-002 ─────────────────────────────────────────────────────────────────
    // Prior bug: boundedForEach with cap == activeProcessorCount fired the
    // concurrentPerform branch even when useAllCores:false (network path),
    // defeating the SMB connection cap entirely.
    T.group("FT-002: boundedForEach(useAllCores:false) never exceeds cap") {
        // Choose count > activeProcessorCount so the old bypass would have fired.
        let count = ProcessInfo.processInfo.activeProcessorCount + 4
        let cap = 2
        let lock = NSLock()
        var maxSeen = 0
        var current = 0
        var processed = 0

        FileTransfer.boundedForEach(count, maxConcurrent: cap, useAllCores: false) { _ in
            lock.lock(); current += 1; if current > maxSeen { maxSeen = current }; lock.unlock()
            Thread.sleep(forTimeInterval: 0.002)   // hold the slot briefly so concurrency builds
            lock.lock(); current -= 1; processed += 1; lock.unlock()
        }

        T.equal(processed, count, "all \(count) items processed (FT-002)")
        T.expect(maxSeen <= cap,
                 "max concurrent \(maxSeen) ≤ cap \(cap) even with count > activeProcessorCount (FT-002)")
    }

    // FO-002 ─────────────────────────────────────────────────────────────────
    // Prior bug: duplicate() called appendingPathExtension("") on extension-less
    // files, which is undefined — some runtime versions append a trailing dot
    // producing "Makefile copy." instead of "Makefile copy".
    T.group("FO-002: duplicate of extension-less file has no trailing dot in name") {
        MainActor.assumeIsolated {
            let fm = FileManager.default
            let dir = fm.temporaryDirectory.appendingPathComponent("anf-fo002-\(UUID().uuidString)")
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            defer { try? fm.removeItem(at: dir) }

            let makefile = dir.appendingPathComponent("Makefile")
            try? "content".write(to: makefile, atomically: true, encoding: .utf8)
            guard let item = FileItem(url: makefile) else {
                T.expect(false, "FO-002 fixture: FileItem"); return
            }

            FileOperations.duplicate([item])

            let contents = (try? fm.contentsOfDirectory(atPath: dir.path)) ?? []
            let copy = contents.first(where: { $0 != "Makefile" })
            T.expect(copy != nil, "a duplicate was created (FO-002)")
            if let copy {
                T.expect(!copy.hasSuffix("."),
                         "copy name '\(copy)' must not end with a dot (FO-002)")
                T.equal(copy, "Makefile copy",
                        "copy name is exactly 'Makefile copy' (FO-002)")
            }
        }
    }

    // FU-001 ─────────────────────────────────────────────────────────────────
    // Prior bug: `stillTrashed` was populated on success but never returned;
    // the dead accumulation masked a subtle code-path confusion.
    // Fix: removed `stillTrashed`; `restoredPairs.map(\.original)` is used.
    // Test: trash a file, undo (restore), verify the redo stack has .created
    // with the original URL (the correct inverse for re-trashing on redo).
    T.group("FU-001: trash→undo leaves a .created redo op with the original URL") {
        MainActor.assumeIsolated {
            let fm = FileManager.default
            let dir = fm.temporaryDirectory.appendingPathComponent("anf-fu001-\(UUID().uuidString)")
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            defer { try? fm.removeItem(at: dir) }

            let file = dir.appendingPathComponent("doc.txt")
            try? "x".write(to: file, atomically: true, encoding: .utf8)

            // Manually trash and record — avoids the @MainActor headless-dialog path.
            var t: NSURL?
            guard (try? fm.trashItem(at: file, resultingItemURL: &t)) != nil,
                  let trashed = t as URL? else {
                T.expect(false, "FU-001 fixture: trashItem"); return
            }
            FileUndo.shared.record(.trash([(original: file, trashed: trashed)]))

            let beforeRedo = FileUndo.shared.redoStack.count
            T.expect(FileUndo.shared.undo(), "undo (restore from trash) reports success (FU-001)")
            T.expect(fm.fileExists(atPath: file.path),
                     "file is restored to original path (FU-001)")

            // The redo inverse must be .created([file]) so that redo re-trashes it.
            T.equal(FileUndo.shared.redoStack.count, beforeRedo + 1,
                    "redo stack gained one op after undo (FU-001)")
            if let redoOp = FileUndo.shared.redoStack.last {
                if case .created(let urls) = redoOp {
                    T.equal(urls.count, 1, ".created redo op has exactly 1 URL (FU-001)")
                    T.equal(urls.first?.lastPathComponent, file.lastPathComponent,
                            ".created redo URL matches original filename (FU-001)")
                } else {
                    T.expect(false, "redo op is .created as expected (FU-001)")
                }
            }
        }
    }
}
