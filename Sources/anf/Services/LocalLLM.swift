import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// On-device language model via Apple's FoundationModels (the same model that
/// powers Apple Intelligence) — no bundle, no network, so the "telemetry 0"
/// promise holds even for summarize / Q&A / smart-rename. Requires macOS 26 +
/// Apple Intelligence enabled on an eligible Mac; everything below degrades
/// gracefully (returns nil / a status) on older systems so the 14+ build keeps
/// compiling and running.
enum LocalLLM {

    enum Status: Equatable {
        case available
        case customEndpoint        // a user-configured local LLM (Ollama/LM Studio)
        case claudeCloud           // Anthropic Claude API (cloud, opt-in)
        case needsNewerOS          // < macOS 26 — no FoundationModels at all
        case appleIntelligenceOff  // 26 but AI not turned on
        case modelNotReady         // 26, downloading / warming up
        case unsupportedDevice     // ineligible hardware
    }

    /// Which backend serves the AI features. Chosen by `aiProvider` in the ⌘,
    /// settings file ("apple" / "local" / "claude"), falling back to whatever is
    /// actually configured, then Apple's on-device model.
    enum Provider { case apple, local, claude }

    static var provider: Provider {
        switch (UserDefaults.standard.string(forKey: "anf.aiProvider") ?? "").lowercased() {
        case "claude", "anthropic": return ClaudeLLM.isConfigured ? .claude : .apple
        case "local", "ollama", "openai": return RemoteLLM.isConfigured ? .local : .apple
        case "apple", "ondevice", "on-device": return .apple
        default:
            // No explicit choice — use whatever's configured (Claude, then local).
            if ClaudeLLM.isConfigured { return .claude }
            if RemoteLLM.isConfigured { return .local }
            return .apple
        }
    }

    /// Why-it-can't, for a one-line UI hint.
    static var status: Status {
        switch provider {
        case .claude: return .claudeCloud
        case .local: return .customEndpoint
        case .apple: break
        }
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            switch SystemLanguageModel.default.availability {
            case .available: return .available
            case .unavailable(let reason):
                switch reason {
                case .appleIntelligenceNotEnabled: return .appleIntelligenceOff
                case .modelNotReady: return .modelNotReady
                default: return .unsupportedDevice
                }
            }
        }
        #endif
        return .needsNewerOS
    }

    static var isAvailable: Bool {
        switch status {
        case .available, .customEndpoint, .claudeCloud: return true
        default: return false
        }
    }

    /// Localized one-liner explaining an unavailable state.
    static func unavailableHint(_ s: Status) -> String {
        switch s {
        case .available, .customEndpoint, .claudeCloud: return ""
        case .needsNewerOS: return L("Requires macOS 26 (Apple Intelligence), or connect a local/Claude model in Settings", "macOS 26(Apple Intelligence)가 필요합니다 — 또는 설정에서 로컬/Claude 모델을 연결하세요")
        case .appleIntelligenceOff: return L("Turn on Apple Intelligence in System Settings, or connect a local/Claude model in Settings", "시스템 설정에서 Apple Intelligence를 켜거나, 설정에서 로컬/Claude 모델을 연결하세요")
        case .modelNotReady: return L("The model is still downloading — try again shortly", "모델을 내려받는 중입니다 — 잠시 후 다시 시도하세요")
        case .unsupportedDevice: return L("This Mac doesn't support Apple Intelligence — connect a local/Claude model in Settings", "이 Mac은 Apple Intelligence를 지원하지 않습니다 — 설정에서 로컬/Claude 모델을 연결하세요")
        }
    }

    /// Generate text from instructions + prompt via the active provider. Returns
    /// nil if unavailable or the backend errors. `maxTokens` bounds the response.
    static func generate(instructions: String, prompt: String, maxTokens: Int = 600) async -> String? {
        switch provider {
        case .claude:
            // Big context — one shot is enough.
            return await ClaudeLLM.generate(instructions: instructions, prompt: prompt, maxTokens: maxTokens)
        case .local:
            // Small local models can overflow too — shrink-and-retry like Apple.
            return await shrinkRetry(prompt) { input in
                await RemoteLLM.generate(instructions: instructions, prompt: input, maxTokens: maxTokens)
            }
        case .apple:
            return await shrinkRetry(prompt) { input in
                await appleGenerate(instructions: instructions, prompt: input, maxTokens: maxTokens)
            }
        }
    }

    /// Run `attempt`, halving the input and retrying when it returns nil — the
    /// on-device context window is small (~4k tokens) and CJK is ~1 token/char,
    /// so a long Korean/Japanese document overflows and yields nothing; the head
    /// still carries the gist.
    private static func shrinkRetry(_ prompt: String, _ attempt: (String) async -> String?) async -> String? {
        var input = prompt
        for i in 0..<3 {
            if let out = await attempt(input) { return out }
            if i < 2, input.count > 600 { input = String(input.prefix(input.count / 2)) } else { break }
        }
        return nil
    }

    /// Apple FoundationModels path (macOS 26 + Apple Intelligence).
    private static func appleGenerate(instructions: String, prompt: String, maxTokens: Int) async -> String? {
        #if canImport(FoundationModels)
        if #available(macOS 26, *), SystemLanguageModel.default.availability == .available {
            do {
                let session = LanguageModelSession(instructions: instructions)
                let opts = GenerationOptions(temperature: 0.3, maximumResponseTokens: maxTokens)
                let response = try await session.respond(to: prompt, options: opts)
                return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            } catch { return nil }
        }
        #endif
        return nil
    }

    /// Char budget for a single LLM call. CJK is ~1 token/char vs ~0.25 for
    /// English, so the model's small context needs a much tighter cap for
    /// Korean/Japanese/Chinese text. generate() still shrinks-and-retries past
    /// this, but a right-sized first try usually succeeds outright.
    static func inputBudget(forCJK cjk: Bool) -> Int { cjk ? 3_500 : 9_000 }

    /// Back-compat budget used by callers that excerpt before calling (folder
    /// sweep). Conservative so mixed content still fits after assembly.
    static let inputCharBudget = 9_000

    /// Summarize a document's body, ANSWERING IN THE DOCUMENT'S LANGUAGE. The
    /// on-device model defaults to the Apple Intelligence UI language (often
    /// English here), and a meta-instruction like "reply in the document's
    /// language" gets ignored — but a Korean instruction reliably yields Korean.
    /// So we detect the language and pick a matching instruction. nil when the
    /// LLM is unavailable or input is empty.
    static func summarize(_ text: String) async -> String? {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return nil }
        let korean = isKorean(body)
        let budget = inputBudget(forCJK: korean || hasCJK(body))
        let clipped = body.count > budget ? String(body.prefix(budget)) : body
        let instructions = korean
            ? "다음 문서를 한국어로 2~3문장으로 요약하세요. 핵심 목적과 요점만, 군더더기 없이. 반드시 한국어로만 답하세요."
            : "Summarize the document in 2–3 sentences — purpose and key points only, no preamble."
        return await generate(instructions: instructions, prompt: clipped, maxTokens: 400)
    }

    /// True if the text contains a meaningful share of CJK (Hangul, Kana, or Han)
    /// — these cost ~1 token/char, so they need the tighter input budget even
    /// when `isKorean` is false (e.g. Japanese).
    static func hasCJK(_ text: String) -> Bool {
        var cjk = 0, total = 0
        for s in text.unicodeScalars {
            guard !s.properties.isWhitespace else { continue }
            total += 1
            let v = s.value
            if (0xAC00...0xD7A3).contains(v) || (0x1100...0x11FF).contains(v)    // Hangul
                || (0x3040...0x30FF).contains(v)                                  // Kana
                || (0x4E00...0x9FFF).contains(v) || (0x3400...0x4DBF).contains(v) // Han
                || (0xF900...0xFAFF).contains(v) { cjk += 1 }
            if total > 400 { break }
        }
        return total > 0 && Double(cjk) / Double(total) >= 0.15
    }

    /// Korean if Hangul makes up a meaningful share of the letters. A few Latin
    /// loanwords (ETF, AI) shouldn't flip a Korean doc to English.
    static func isKorean(_ text: String) -> Bool {
        var hangul = 0, latin = 0
        for s in text.unicodeScalars {
            if (0xAC00...0xD7A3).contains(s.value) || (0x1100...0x11FF).contains(s.value) { hangul += 1 }
            else if (0x41...0x5A).contains(s.value) || (0x61...0x7A).contains(s.value) { latin += 1 }
        }
        guard hangul + latin > 0 else { return false }
        return Double(hangul) / Double(hangul + latin) >= 0.2
    }
}
