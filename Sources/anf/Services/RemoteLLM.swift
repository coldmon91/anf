import Foundation

/// Optional bring-your-own local LLM, spoken to over the OpenAI-compatible
/// `/chat/completions` API that Ollama, LM Studio, llama.cpp, and friends expose
/// on localhost. Lets the AI features work on Macs without macOS 26 / Apple
/// Intelligence. Configured in the ⌘, settings file:
///
///     "aiEndpoint": "http://localhost:11434/v1",   // Ollama (LM Studio: :1234/v1)
///     "aiModel": "llama3.2",
///     "aiApiKey": ""                                // usually empty for local
///
/// Still "on your machine" when pointed at localhost — but it IS a network call,
/// so it's strictly opt-in and never the default.
enum RemoteLLM {
    private static let endpointKey = "anf.aiEndpoint"
    private static let modelKey = "anf.aiModel"
    private static let apiKeyKey = "anf.aiApiKey"

    static var endpoint: String? {
        let s = (UserDefaults.standard.string(forKey: endpointKey) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? nil : s
    }
    static var model: String {
        let s = (UserDefaults.standard.string(forKey: modelKey) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? "local-model" : s
    }
    static var apiKey: String? {
        let s = (UserDefaults.standard.string(forKey: apiKeyKey) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? nil : s
    }

    /// Configured = an endpoint URL is set.
    static var isConfigured: Bool { endpoint != nil }

    /// POST a chat completion. Returns the assistant text, or nil on any error.
    static func generate(instructions: String, prompt: String, maxTokens: Int, temperature: Double = 0.3) async -> String? {
        guard let base = endpoint, let url = chatURL(base) else { return nil }
        // Reasoning models (LM Studio splits thinking into `reasoning_content`)
        // spend the completion budget THINKING — too small a cap and the real
        // answer is truncated to "". Local inference is free, so give headroom.
        let cap = max(maxTokens, 2048)
        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": instructions],
                ["role": "user", "content": prompt],
            ],
            "temperature": temperature,
            "max_tokens": cap,
            "stream": false,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return nil }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let key = apiKey { req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        req.httpBody = data
        req.timeoutInterval = 120

        guard let (respData, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode),
              let json = (try? JSONSerialization.jsonObject(with: respData)) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]], let first = choices.first,
              let message = first["message"] as? [String: Any]
        else { return nil }
        let raw = (message["content"] as? String) ?? ""
        let cleaned = stripThink(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }

    /// Some models inline chain-of-thought as <think>…</think> in `content`;
    /// strip it so only the answer remains.
    static func stripThink(_ s: String) -> String {
        guard s.contains("<think>") else { return s }
        var out = s
        while let open = out.range(of: "<think>") {
            if let close = out.range(of: "</think>", range: open.upperBound..<out.endIndex) {
                out.removeSubrange(open.lowerBound..<close.upperBound)
            } else {
                out.removeSubrange(open.lowerBound..<out.endIndex)   // unterminated
                break
            }
        }
        return out
    }

    /// Quick reachability probe (used by the status line / config check).
    static func reachable() async -> Bool {
        await generate(instructions: "You are a health check.", prompt: "Reply with: ok", maxTokens: 5) != nil
    }

    /// Normalize a base URL into the chat-completions endpoint. Accepts a base
    /// ("…/v1"), a bare host ("localhost:11434"), or the full path.
    static func chatURL(_ base: String) -> URL? {
        var s = base.trimmingCharacters(in: .whitespacesAndNewlines)
        if !s.contains("://") { s = "http://" + s }
        while s.hasSuffix("/") { s.removeLast() }
        if s.hasSuffix("/chat/completions") { return URL(string: s) }
        if s.hasSuffix("/v1") { return URL(string: s + "/chat/completions") }
        return URL(string: s + "/v1/chat/completions")
    }
}
