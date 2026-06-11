import Foundation
@testable import anf

/// Type-to-select: jamo search keys plus the BrowserModel jump behavior
/// (prefix match, buffer accumulation, pause reset, nearest-follower fallback).
func runTypeaheadTests() {
    T.group("HangulJamo.searchKey") {
        T.equal(HangulJamo.searchKey("플레이"), "ㅍㅡㄹㄹㅔㅇㅣ", "syllables expand to jamo")
        T.equal(HangulJamo.searchKey("Backup"), "backup", "latin just lowercases")
        T.equal(HangulJamo.searchKey("값"), "ㄱㅏㅂㅅ", "tail clusters expand too")
    }

    MainActor.assumeIsolated {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("anftype-\(UUID().uuidString)")
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            for name in ["archives", "backup", "blog", "playground", "presentation", "플레이그라운드"] {
                try fm.createDirectory(at: dir.appendingPathComponent(name),
                                       withIntermediateDirectories: true)
            }
        } catch { T.expect(false, "fixture setup threw: \(error)"); return }
        defer { try? fm.removeItem(at: dir) }

        let model = BrowserModel(start: dir)
        let deadline = Date().addingTimeInterval(5)
        while model.items.count != 6 && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        T.equal(model.items.count, 6, "fixture listing loaded")
        guard model.items.count == 6 else { return }

        @MainActor func selectedName() -> String {
            model.items.first { model.selection.contains($0.id) }?.name ?? "(none)"
        }
        let t0 = Date()

        T.group("typeSelect: prefix jump and accumulation") {
            model.typeSelect("p", now: t0)
            T.equal(selectedName(), "playground", "'p' jumps to the first p-item")
            model.typeSelect("r", now: t0.addingTimeInterval(0.3))
            T.equal(selectedName(), "presentation", "quick 'r' accumulates to 'pr'")
        }

        T.group("typeSelect: pause resets the buffer") {
            model.typeSelect("b", now: t0.addingTimeInterval(3))
            T.equal(selectedName(), "backup", "after a pause 'b' starts fresh")
            model.typeSelect("l", now: t0.addingTimeInterval(3.2))
            T.equal(selectedName(), "blog", "'bl' refines within the window")
        }

        T.group("typeSelect: Korean jamo matching") {
            model.typeSelect("ㅍ", now: t0.addingTimeInterval(6))
            T.equal(selectedName(), "플레이그라운드", "initial consonant finds the Korean name")
            model.typeSelect("ㅡ", now: t0.addingTimeInterval(6.2))
            T.equal(selectedName(), "플레이그라운드", "IME jamo stream keeps matching")
        }

        T.group("typeSelect: no-match falls to the nearest follower") {
            model.typeSelect("c", now: t0.addingTimeInterval(9))
            T.equal(selectedName(), "playground",
                    "no c-item → alphabetically nearest following name")
        }
    }
}
