import Foundation

/// One client for every vendor that speaks the OpenAI chat-completions
/// dialect: OpenAI, Gemini, Mistral, DeepSeek, Qwen, Ollama, LM Studio,
/// OpenRouter, Groq, and any custom server (vLLM, llama.cpp, LiteLLM...).
struct OpenAICompatibleProvider: LLMProvider {
    var kind: ProviderKind
    var baseURL: String
    var model: String
    var apiKey: String

    func streamReply(to request: CompanionRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var urlRequest = URLRequest(url: try HTTPStreaming.joinURL(baseURL, "/chat/completions"))
                    urlRequest.httpMethod = "POST"
                    applyHeaders(to: &urlRequest)
                    urlRequest.httpBody = try JSONSerialization.data(withJSONObject: buildBody(for: request))
                    // Local models can take a while to load on first use.
                    urlRequest.timeoutInterval = kind.isLocal ? 300 : 90

                    for try await line in try await HTTPStreaming.openLineStream(for: urlRequest) {
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if payload == "[DONE]" { break }
                        guard let data = payload.data(using: .utf8),
                              let chunk = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }

                        if let error = chunk["error"] as? [String: Any] {
                            throw ProviderError(message: error["message"] as? String ?? "Stream error")
                        }
                        let choices = chunk["choices"] as? [[String: Any]] ?? []
                        if let delta = choices.first?["delta"] as? [String: Any],
                           let text = delta["content"] as? String, !text.isEmpty {
                            continuation.yield(text)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func listModels() async throws -> [String] {
        var urlRequest = URLRequest(url: try HTTPStreaming.joinURL(baseURL, "/models"))
        applyHeaders(to: &urlRequest)
        let json = try await HTTPStreaming.fetchJSON(urlRequest)
        let models = json["data"] as? [[String: Any]] ?? []
        // Gemini prefixes ids with "models/", which its chat endpoint doesn't want.
        return models.compactMap { ($0["id"] as? String)?.replacingOccurrences(of: "models/", with: "") }.sorted()
    }

    private func applyHeaders(to urlRequest: inout URLRequest) {
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !apiKey.isEmpty {
            urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        if kind == .openRouter {
            urlRequest.setValue("Yewclic", forHTTPHeaderField: "X-Title")
        }
    }

    private func buildBody(for request: CompanionRequest) -> [String: Any] {
        var messages: [[String: Any]] = [["role": "system", "content": request.systemPrompt]]
        messages += request.history.map { ["role": $0.role.rawValue, "content": $0.text] }

        if !request.screenshots.isEmpty {
            var content: [[String: Any]] = []
            for screenshot in request.screenshots {
                let dataURL = "data:image/jpeg;base64," + screenshot.jpegData.base64EncodedString()
                content.append(["type": "text", "text": screenshot.promptCaption])
                content.append(["type": "image_url", "image_url": ["url": dataURL]])
            }
            content.append(["type": "text", "text": request.userText])
            messages.append(["role": "user", "content": content])
        } else {
            messages.append(["role": "user", "content": request.userText])
        }

        return [
            "model": model,
            "stream": true,
            "max_tokens": 1024,
            "messages": messages,
        ]
    }
}
