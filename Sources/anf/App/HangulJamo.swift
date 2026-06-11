import Foundation

/// Hangul-aware search keys for type-to-select. Syllables expand into
/// compatibility jamo — "플" → "ㅍㅡㄹ" — so the per-keystroke jamo stream the
/// Korean IME produces (ㅍ, ㅡ, ㄹ…) prefix-matches composed names, and a lone
/// initial consonant (ㅍ) still finds "플레이그라운드". Other text lowercases.
enum HangulJamo {
    private static let lead = [
        "ㄱ", "ㄲ", "ㄴ", "ㄷ", "ㄸ", "ㄹ", "ㅁ", "ㅂ", "ㅃ", "ㅅ",
        "ㅆ", "ㅇ", "ㅈ", "ㅉ", "ㅊ", "ㅋ", "ㅌ", "ㅍ", "ㅎ",
    ]
    // Compound vowels and cluster tails expand to their constituents (ㅘ→ㅗㅏ,
    // ㅄ→ㅂㅅ) so the IME's per-keystroke jamo stream matches what users type.
    private static let vowel = [
        "ㅏ", "ㅐ", "ㅑ", "ㅒ", "ㅓ", "ㅔ", "ㅕ", "ㅖ", "ㅗ", "ㅗㅏ",
        "ㅗㅐ", "ㅗㅣ", "ㅛ", "ㅜ", "ㅜㅓ", "ㅜㅔ", "ㅜㅣ", "ㅠ", "ㅡ", "ㅡㅣ", "ㅣ",
    ]
    private static let tail = [
        "", "ㄱ", "ㄲ", "ㄱㅅ", "ㄴ", "ㄴㅈ", "ㄴㅎ", "ㄷ", "ㄹ", "ㄹㄱ",
        "ㄹㅁ", "ㄹㅂ", "ㄹㅅ", "ㄹㅌ", "ㄹㅍ", "ㄹㅎ", "ㅁ", "ㅂ", "ㅂㅅ", "ㅅ",
        "ㅆ", "ㅇ", "ㅈ", "ㅊ", "ㅋ", "ㅌ", "ㅍ", "ㅎ",
    ]

    /// Lowercased, NFC-normalized, with Hangul syllables expanded to jamo.
    static func searchKey(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        for scalar in s.precomposedStringWithCanonicalMapping.lowercased().unicodeScalars {
            let v = scalar.value
            if v >= 0xAC00, v <= 0xD7A3 {
                let i = Int(v - 0xAC00)
                out += lead[i / 588]
                out += vowel[(i % 588) / 28]
                out += tail[i % 28]
            } else {
                out.append(Character(scalar))
            }
        }
        return out
    }
}
