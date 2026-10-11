import Foundation

/// Claude via the Anthropic Messages API, streamed over SSE.
struct AnthropicProvider: LLMProvider {
    var baseURL: String
    var model: String
    var apiKey: String

    func streamReply(to request: CompanionRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var urlRequest = URLRequest(url: try HTTPStreaming.joinURL(baseURL, "/v1/messages"))
                    urlRequest.httpMethod = "POST"
                    applyHeaders(to: &urlRequest)
                    urlRequest.httpBody = try JSONSerialization.data(withJSONObject: buildBody(for: request))

                    for try await line in try await HTTPStreaming.openLineStream(for: urlRequest) {
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        guard let data = payload.data(using: .utf8),
                              let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }

                        if event["type"] as? String == "content_block_delta",
                           let delta = event["delta"] as? [String: Any],
                           let text = delta["text"] as? String {
                            continuation.yield(text)
                        } else if event["type"] as? String == "error",
                                  let error = event["error"] as? [String: Any] {
                            throw ProviderError(message: error["message"] as? String ?? "Anthropic stream error")
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
        var urlRequest = URLRequest(url: try HTTPStreaming.joinURL(baseURL, "/v1/models?limit=100"))
        applyHeaders(to: &urlRequest)
        let json = try await HTTPStreaming.fetchJSON(urlRequest)
        let models = json["data"] as? [[String: Any]] ?? []
        return models.compactMap { $0["id"] as? String }
    }

    private func applyHeaders(to urlRequest: inout URLRequest) {
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
    }

    private func buildBody(for request: CompanionRequest) -> [String: Any] {
        var messages: [[String: Any]] = request.history.map {
            ["role": $0.role.rawValue, "content": $0.text]
        }

        var currentContent: [[String: Any]] = []
        for screenshot in request.screenshots {
            currentContent.append(["type": "text", "text": screenshot.promptCaption])
            currentContent.append([
                "type": "image",
                "source": [
                    "type": "base64",
                    "media_type": "image/jpeg",
                    "data": screenshot.jpegData.base64EncodedString(),
                ],
            ])
        }
        currentContent.append(["type": "text", "text": request.userText])
        messages.append(["role": "user", "content": currentContent])

        return [
            "model": model,
            "max_tokens": 1024,
            "stream": true,
            "system": request.systemPrompt,
            "messages": messages,
        ]
    }
}
