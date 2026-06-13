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
        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": instructions],
                ["role": "user", "content": prompt],
            ],
            "temperature": temperature,
            "max_tokens": maxTokens,
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
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String
        else { return nil }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
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
