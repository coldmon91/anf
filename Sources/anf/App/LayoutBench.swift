import AppKit
import QuartzCore

/// Measures ⌘1–4 pane-layout switching end-to-end: `setLayout` plus the SwiftUI
/// commit, AppKit layout and draw that follow — the wall time the user actually
/// feels. Run with `ANF_LAYOUT_BENCH=<dir> anf`; it navigates there, cycles the
/// layouts twice (cold then warm) and exits.
@MainActor
enum LayoutBench {
    static var isRequested: Bool {
        ProcessInfo.processInfo.environment["ANF_LAYOUT_BENCH"] != nil
    }

    static func run(window: NSWindow, workspace: WorkspaceModel) {
        guard let dir = ProcessInfo.processInfo.environment["ANF_LAYOUT_BENCH"] else { return }
        let steps: [PaneLayout] = [.dual, .single, .rows, .single, .quad, .single,
                                   .dual, .single, .rows, .single, .quad, .single]
        Task { @MainActor in
            // Let the first window settle, then point the active pane at the
            // target folder and give the (async) listing time to land.
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            workspace.active.navigate(to: URL(fileURLWithPath: dir))
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            print("LAYOUTBENCH dir=\(dir) items=\(workspace.active.items.count)")

            var results: [(PaneLayout, Double)] = []
            for l in steps {
                let ms = await measure(window: window) { workspace.setLayout(l) }
                results.append((l, ms))
                print(String(format: "LAYOUTBENCH %@ %.1fms", String(describing: l), ms))
                // Let newly revealed panes finish their async listing loads so the
                // next switch measures steady state, not load contention.
                try? await Task.sleep(nanoseconds: 600_000_000)
            }
            let worst = results.map(\.1).max() ?? 0
            print(String(format: "LAYOUTBENCH worst %.1fms", worst))
            exit(worst < 250 ? 0 : 1)
        }
    }

    /// Wall time from the mutation to the next fully laid-out, drawn frame.
    private static func measure(window: NSWindow, _ mutate: () -> Void) async -> Double {
        let t0 = CACurrentMediaTime()
        mutate()
        // SwiftUI commits on the next runloop turn; force layout + draw there so
        // the clock covers everything between keypress and pixels.
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            DispatchQueue.main.async {
                window.contentView?.layoutSubtreeIfNeeded()
                window.displayIfNeeded()
                cont.resume()
            }
        }
        return (CACurrentMediaTime() - t0) * 1000
    }
}
