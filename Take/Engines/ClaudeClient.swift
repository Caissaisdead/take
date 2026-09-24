import Foundation

/// Claude over the Messages API with the writer's own key. The one part of the
/// app that sends text off the Mac; the consent sheet says so before it runs.
/// Raw HTTP: there is no official Swift SDK.
struct ClaudeClient {
    static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    static let modelKey = "ClaudeModel"
    static let defaultModel = "claude-opus-5"
    /// The models the Settings window offers.
    static let models: [(id: String, name: String)] = [
        ("claude-opus-5", "Claude Opus 5"),
        ("claude-sonnet-5", "Claude Sonnet 5, economy"),
    ]

    static var model: String {
        UserDefaults.standard.string(forKey: modelKey) ?? defaultModel
    }

    static var hasKey: Bool {
        APIKeyStore.read() != nil
    }

    /// One reply's text for one user turn under a system prompt. Thinking is
    /// adaptive by default on this model; effort sets how much.
    static func complete(system: String, user: String, maxTokens: Int = 8_000, effort: String = "high") async throws -> String {
        guard let key = APIKeyStore.read() else { throw EngineError.notReady("No Anthropic API key. Add one in Settings.") }
        let body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "system": system,
            "messages": [["role": "user", "content": user]],
            "output_config": ["effort": effort],
            // A refusal on a safety classifier is retried on a fallback model
            // inside the same call rather than leaving the take unwritten.
            "fallbacks": "default",
        ]
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 600
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, status) = try await send(request)
        return try text(from: data, status: status)
    }

    /// Whether the key opens the chosen model: a GET on the model itself.
    static func checkKey() async throws -> String {
        guard let key = APIKeyStore.read() else { throw EngineError.notReady("No key saved.") }
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/models/\(model)")!)
        request.timeoutInterval = 30
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        let (data, status) = try await send(request)
        guard (200...299).contains(status) else {
            let message = (try? JSONDecoder().decode(ErrorEnvelope.self, from: data))?.error.message
            throw EngineError.notReady(message ?? "The API answered with status \(status).")
        }
        struct Model: Decodable { let display_name: String? }
        let name = (try? JSONDecoder().decode(Model.self, from: data))?.display_name ?? model
        return "The key works. \(name) is ready."
    }

    /// Three tries on a rate limit or a server fault, waiting as told or doubling.
    private static func send(_ request: URLRequest) async throws -> (Data, Int) {
        var attempt = 0
        while true {
            attempt += 1
            let data: Data
            let response: URLResponse
            do {
                (data, response) = try await URLSession.shared.data(for: request)
            } catch {
                guard attempt < 3 else { throw EngineError.failed(error.localizedDescription) }
                try await Task.sleep(for: .seconds(Double(1 << attempt)))
                continue
            }
            let http = response as? HTTPURLResponse
            let status = http?.statusCode ?? 0
            if status == 429 || status == 529 || (500...599).contains(status), attempt < 3 {
                let wait = http?.value(forHTTPHeaderField: "retry-after").flatMap(Double.init) ?? Double(1 << attempt)
                try await Task.sleep(for: .seconds(min(wait, 30)))
                continue
            }
            return (data, status)
        }
    }

    /// The reply's text, or what went wrong with it.
    private static func text(from data: Data, status: Int) throws -> String {
        guard (200...299).contains(status) else {
            let message = (try? JSONDecoder().decode(ErrorEnvelope.self, from: data))?.error.message
            switch status {
            case 401, 403: throw EngineError.notReady("The API key was refused: \(message ?? "status \(status)").")
            default: throw EngineError.failed(message ?? "The API answered with status \(status).")
            }
        }
        let envelope = try JSONDecoder().decode(MessageEnvelope.self, from: data)
        if envelope.stop_reason == "refusal" { throw EngineError.refused }
        let text = envelope.content.filter { $0.type == "text" }.compactMap(\.text).joined()
        guard !text.isEmpty else { throw EngineError.failed("The API answered without text.") }
        if envelope.stop_reason == "max_tokens" {
            return text + "\n\n[The take ran past its length and was cut here.]"
        }
        return text
    }

    private struct MessageEnvelope: Decodable {
        struct Block: Decodable {
            let type: String
            let text: String?
        }
        let content: [Block]
        let stop_reason: String?
    }

    private struct ErrorEnvelope: Decodable {
        struct Inner: Decodable { let message: String }
        let error: Inner
    }
}
