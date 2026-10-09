import Foundation

struct ConversationTurn: Codable {
    enum Role: String, Codable { case user, assistant }
    var role: Role
    var text: String
}

/// Everything a provider needs to answer one push-to-talk question.
struct CompanionRequest {
    var systemPrompt: String
    /// Earlier turns, text only. Screenshots are only sent for the current turn
    /// to keep requests small.
    var history: [ConversationTurn]
    var userText: String
    /// nil when the provider is text-only (the OCR transcript is folded into
    /// `userText` instead).
    var screenshot: CapturedScreen?
}

protocol LLMProvider {
    /// Streams the reply as text chunks.
    func streamReply(to request: CompanionRequest) -> AsyncThrowingStream<String, Error>
    /// Lists model ids the provider reports, for the Settings picker.
    func listModels() async throws -> [String]
}

struct ProviderError: LocalizedError {
    var message: String
    var errorDescription: String? { message }
}

enum ProviderFactory {
    static func makeProvider(kind: ProviderKind, settings: ProviderSettings, apiKey: String) -> LLMProvider {
        switch kind.wireFormat {
        case .anthropicMessages:
            return AnthropicProvider(baseURL: settings.baseURL, model: settings.model, apiKey: apiKey)
        case .openAICompatible:
            return OpenAICompatibleProvider(kind: kind, baseURL: settings.baseURL, model: settings.model, apiKey: apiKey)
        case .claudeCodeCLI:
            return ClaudeCodeCLIProvider(model: settings.model, customCLIPath: settings.cliPath)
        }
    }
}

enum HTTPStreaming {
    /// Opens a streaming request and throws a readable error for non-2xx
    /// responses (including the provider's error body, which usually says
    /// exactly what is wrong: bad key, unknown model, etc).
    static func openLineStream(for request: URLRequest) async throws -> AsyncLineSequence<URLSession.AsyncBytes> {
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProviderError(message: "No HTTP response")
        }
        if !(200..<300).contains(httpResponse.statusCode) {
            var errorBody = ""
            for try await line in bytes.lines {
                errorBody += line
                if errorBody.count > 2000 { break }
            }
            throw ProviderError(message: "HTTP \(httpResponse.statusCode): \(errorBody)")
        }
        return bytes.lines
    }

    static func fetchJSON(_ request: URLRequest) async throws -> [String: Any] {
        let (data, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse, !(200..<300).contains(httpResponse.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw ProviderError(message: "HTTP \(httpResponse.statusCode): \(body)")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderError(message: "Unexpected response")
        }
        return json
    }

    static func joinURL(_ base: String, _ path: String) throws -> URL {
        let trimmedBase = base.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: trimmedBase + path) else {
            throw ProviderError(message: "Invalid base URL: \(base)")
        }
        return url
    }
}
