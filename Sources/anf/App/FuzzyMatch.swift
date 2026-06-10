import Foundation

/// Lightweight fuzzy matcher in the spirit of fzf: the pattern must appear as a
/// (case-insensitive) subsequence of the text. Score rewards consecutive matches,
/// matches at word boundaries (`/ _ - . space`) and the start of the string, and
/// lightly penalizes long noisy paths. Returns nil when the pattern doesn't match.
enum FuzzyMatch {
    static func score(pattern: String, text: String) -> Int? {
        if pattern.isEmpty { return 0 }
        let p = Array(pattern.lowercased())
        let t = Array(text.lowercased())
        guard p.count <= t.count else { return nil }

        var pi = 0
        var total = 0
        var prevMatch = -2
        var run = 0
        for ti in t.indices {
            guard pi < p.count, t[ti] == p[pi] else { continue }
            var bonus = 1
            if ti == prevMatch + 1 {
                run += 1
                bonus += 5 + run * 2          // consecutive streak
            } else {
                run = 0
            }
            if ti == 0 {
                bonus += 10                    // very start
            } else {
                switch t[ti - 1] {
                case "/", "_", "-", " ", ".": bonus += 8   // word boundary
                default: break
                }
            }
            total += bonus
            prevMatch = ti
            pi += 1
        }
        guard pi == p.count else { return nil }
        total -= t.count / 24                  // prefer shorter / less noisy
        return total
    }

    /// Rank URLs by fuzzy score of the query against the filename (falling back to
    /// the full path), best first, capped at `limit`.
    static func rank(_ urls: [URL], query: String, limit: Int) -> [URL] {
        var scored: [(url: URL, score: Int)] = []
        scored.reserveCapacity(urls.count)
        for url in urls {
            if let s = score(pattern: query, text: url.lastPathComponent) {
                scored.append((url, s))
            } else if let s = score(pattern: query, text: url.path) {
                scored.append((url, s - 60))
            }
        }
        scored.sort { $0.score > $1.score }
        return scored.prefix(limit).map(\.url)
    }
}
