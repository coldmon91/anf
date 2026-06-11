import AppKit
import Observation

/// Once-a-day check against the latest GitHub release. Fail-silent (offline is
/// fine); when a newer version exists a small dismissible banner appears, and a
/// dismissed version is never offered again.
@MainActor
@Observable
final class UpdateChecker {
    static let shared = UpdateChecker()

    /// Newer version tag (e.g. "1.2.0") when an update is available.
    private(set) var availableVersion: String?

    private static let lastCheckKey = "anf.update.lastCheck"
    private static let dismissedKey = "anf.update.dismissed"
    private static let releaseAPI = "https://api.github.com/repos/rescenedev/anf/releases/latest"

    func checkIfDue() {
        let now = Date().timeIntervalSince1970
        let last = UserDefaults.standard.double(forKey: Self.lastCheckKey)
        guard now - last > 24 * 3600 else { return }
        UserDefaults.standard.set(now, forKey: Self.lastCheckKey)

        Task { [weak self] in
            guard let url = URL(string: Self.releaseAPI) else { return }
            var request = URLRequest(url: url)
            request.timeoutInterval = 10
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String else { return }
            let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
                as? String ?? "0"
            guard Self.isNewer(latest, than: current),
                  UserDefaults.standard.string(forKey: Self.dismissedKey) != latest else { return }
            self?.availableVersion = latest
        }
    }

    func dismiss() {
        if let v = availableVersion {
            UserDefaults.standard.set(v, forKey: Self.dismissedKey)
        }
        availableVersion = nil
    }

    /// Numeric dotted-version comparison ("1.10.0" > "1.9").
    static func isNewer(_ a: String, than b: String) -> Bool {
        let av = a.split(separator: ".").map { Int($0) ?? 0 }
        let bv = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(av.count, bv.count) {
            let x = i < av.count ? av[i] : 0
            let y = i < bv.count ? bv[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
