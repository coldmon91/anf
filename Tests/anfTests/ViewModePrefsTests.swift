import Foundation
@testable import anf

func runViewModePrefsTests() {
    MainActor.assumeIsolated {
        let prefs = ViewModePrefs.shared
        let root = "/tmp/anf-vmp-\(UUID().uuidString)"

        T.group("ViewModePrefs inheritance") {
            let a = URL(fileURLWithPath: "\(root)/a")
            let deep = URL(fileURLWithPath: "\(root)/a/b/c")
            T.expect(prefs.mode(for: a) == nil, "no setting anywhere → nil")

            prefs.set(.icons, for: a)
            T.expect(prefs.mode(for: a) == .icons, "own setting wins")
            T.expect(prefs.mode(for: deep) == .icons, "subfolders inherit the ancestor's mode")
            T.expect(prefs.mode(for: URL(fileURLWithPath: "\(root)/other")) == nil,
                     "siblings outside the subtree don't inherit")
        }

        T.group("ViewModePrefs override and subtree reset") {
            let a = URL(fileURLWithPath: "\(root)/a")
            let b = URL(fileURLWithPath: "\(root)/a/b")
            let deep = URL(fileURLWithPath: "\(root)/a/b/c")

            prefs.set(.list, for: b)
            T.expect(prefs.mode(for: deep) == .list, "nearest ancestor wins over a farther one")
            T.expect(prefs.mode(for: a) == .icons, "parent keeps its own setting")

            // Re-setting the parent clears stale descendant entries: the whole
            // subtree follows the newest explicit choice.
            prefs.set(.columns, for: a)
            T.expect(prefs.mode(for: b) == .columns, "new parent setting overrides old child entry")
            T.expect(prefs.mode(for: deep) == .columns, "deep folders follow the newest choice")
        }
    }
}
