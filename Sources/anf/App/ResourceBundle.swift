import Foundation

/// The SwiftPM resource bundle (xterm/, l10n/), wherever this build put it.
///
/// Never use the generated `Bundle.module` here: its accessor fatalErrors when
/// the bundle is missing, and its only fallback is an absolute path into the
/// build machine's `.build` directory. v1.0.0 shipped without the bundle, so on
/// every user machine opening the terminal — or merely launching under a
/// non-ko/en locale — crashed the app. This lookup is non-fatal and checks all
/// layouts we actually run from; callers degrade gracefully when it's nil.
let anfResourceBundle: Bundle? = {
    let name = "anf_anf.bundle"
    let candidates: [URL?] = [
        Bundle.main.resourceURL,                       // anf.app/Contents/Resources/
        Bundle.main.bundleURL,                         // swift run: the bin dir
        URL(fileURLWithPath: CommandLine.arguments[0]) // odd direct invocations
            .deletingLastPathComponent(),
    ]
    for c in candidates {
        if let c, let b = Bundle(url: c.appendingPathComponent(name)) { return b }
    }
    return nil
}()
