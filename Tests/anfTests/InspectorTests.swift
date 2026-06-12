import Foundation
@testable import anf

/// Inspector regression pack (2026-06-13 user reports):
/// 1. The preview stopped following arrow-key selection — the memoized
///    `selectedItems` returned the warm cache WITHOUT reading `selection`, so a
///    SwiftUI body evaluating after another reader registered no Observation
///    dependency and went permanently stale.
/// 2. Opaque binaries (.so) must take the instant-placeholder path, never QL.
/// 3. Markdown gets a real block-parsed preview.
func runInspectorTests() {
    MainActor.assumeIsolated {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("anfinsp-\(UUID().uuidString)")
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }

        T.group("selectedItems registers Observation deps even on a warm cache") {
            let model = BrowserModel(start: dir)
            _ = model.selectedItems            // warm the memo OUTSIDE tracking
            var fired = false
            withObservationTracking {
                _ = model.selectedItems        // cache-hit path
            } onChange: {
                fired = true
            }
            model.selection = [dir.appendingPathComponent("x")]   // a real change must notify
            T.expect(fired, "selection change re-renders a warm-cache reader")
        }

        T.group("opaque binary / markdown classification") {
            func make(_ name: String) -> FileItem? {
                let u = dir.appendingPathComponent(name)
                fm.createFile(atPath: u.path, contents: Data("x".utf8))
                return FileItem(url: u)
            }
            T.expect(make("lib.so")?.isOpaqueBinary == true, ".so → instant placeholder")
            T.expect(make("lib.dylib")?.isOpaqueBinary == true, ".dylib → instant placeholder")
            T.expect(make("a.md")?.isOpaqueBinary == false, ".md is not a binary")
            T.expect(make("a.md")?.isMarkdown == true, ".md → markdown preview")
            T.expect(make("b.markdown")?.isMarkdown == true, ".markdown → markdown preview")
            T.expect(make("c.txt")?.isMarkdown == false, ".txt stays plain text")
        }

        T.group("MarkdownBlocks.parse") {
            let src = """
            # Title

            Some **bold** text.

            - first
            - second

            ```
            let x = 1
            ```
            """
            let blocks = MarkdownBlocks.parse(src)
            T.expect(blocks.count >= 4, "splits into blocks (got \(blocks.count))")
            T.expect(blocks.first?.kind == .header(1), "first block is an H1")
            T.expect(blocks.contains { $0.kind == .codeBlock }, "code block recognized")
            T.expect(blocks.contains {
                if case .listItem = $0.kind { return true } else { return false }
            }, "list items recognized")
            let empty = MarkdownBlocks.parse("")
            T.expect(empty.isEmpty, "empty source → no blocks (no crash)")
        }
    }
}
