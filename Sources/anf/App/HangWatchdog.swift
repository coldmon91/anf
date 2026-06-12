import AppKit

/// Main-thread stall detector (dev tool). A background heartbeat posts a
/// timestamped block to the main queue; if it lands late, the main thread was
/// busy or blocked for that long — the same condition that shows a beachball.
/// Enabled together with tracing (`ANF_TRACE=1`), so a "느낌상 버벅임" report
/// can be reproduced with numbers and timestamps in /tmp/anf-trace.log.
enum HangWatchdog {
    private static let thresholdMs = 100.0
    private static let interval = 0.15

    static func startIfRequested() {
        guard ProcessInfo.processInfo.environment["ANF_TRACE"] == "1" else { return }
        let queue = DispatchQueue(label: "anf.hangwatch", qos: .utility)
        let clock = ContinuousClock()
        func tick() {
            let sent = clock.now
            DispatchQueue.main.async {
                let d = clock.now - sent
                let lateMs = Double(d.components.seconds) * 1_000
                    + Double(d.components.attoseconds) / 1e15
                if lateMs > thresholdMs {
                    Trace.log("⚠️ main thread stalled \(Int(lateMs))ms")
                }
                queue.asyncAfter(deadline: .now() + interval) { tick() }
            }
        }
        queue.async { tick() }
    }
}
