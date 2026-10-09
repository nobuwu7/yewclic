import Foundation

/// Runs the local `claude` CLI in headless mode so answers are billed to the
/// user's Claude subscription instead of an API key. The screenshot is written
/// to a temp file and Claude Code reads it with its own Read tool.
struct ClaudeCodeCLIProvider: LLMProvider {
    var model: String
    var customCLIPath: String

    static let commonCLILocations = [
        "~/.local/bin/claude",
        "~/.claude/local/claude",
        "/opt/homebrew/bin/claude",
        "/usr/local/bin/claude",
    ]

    static func resolveCLIPath(customCLIPath: String) -> String? {
        let candidates = (customCLIPath.isEmpty ? [] : [customCLIPath]) + commonCLILocations
        return candidates
            .map { NSString(string: $0).expandingTildeInPath }
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    func streamReply(to request: CompanionRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            guard let cliPath = Self.resolveCLIPath(customCLIPath: customCLIPath) else {
                continuation.finish(throwing: ProviderError(message: "Couldn't find the `claude` CLI. Install Claude Code or set its path in Settings."))
                return
            }

            let workingDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("yewclic", isDirectory: true)
            try? FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)

            var prompt = ""
            if !request.history.isEmpty {
                prompt += "Conversation so far:\n"
                for turn in request.history {
                    prompt += "\(turn.role == .user ? "User" : "You"): \(turn.text)\n"
                }
                prompt += "\n"
            }
            if let screenshot = request.screenshot {
                let screenshotURL = workingDirectory.appendingPathComponent("screen-\(UUID().uuidString).jpg")
                try? screenshot.jpegData.write(to: screenshotURL)
                prompt += "First use the Read tool to look at the user's current screen: \(screenshotURL.path)\n\n"
            }
            prompt += request.userText

            let process = Process()
            process.executableURL = URL(fileURLWithPath: cliPath)
            process.currentDirectoryURL = workingDirectory
            process.arguments = [
                "-p", prompt,
                "--model", model.isEmpty ? "sonnet" : model,
                "--output-format", "stream-json",
                "--verbose",
                "--include-partial-messages",
                "--allowedTools", "Read",
                "--append-system-prompt", request.systemPrompt,
            ]
            // GUI apps get a minimal PATH; the CLI may need node from Homebrew.
            var environment = ProcessInfo.processInfo.environment
            environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (environment["PATH"] ?? "")
            process.environment = environment

            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            let task = Task.detached {
                do {
                    try process.run()
                    var hasYieldedPartialText = false
                    for try await line in outputPipe.fileHandleForReading.bytes.lines {
                        guard let data = line.data(using: .utf8),
                              let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }

                        if event["type"] as? String == "stream_event",
                           let innerEvent = event["event"] as? [String: Any],
                           let delta = innerEvent["delta"] as? [String: Any],
                           let text = delta["text"] as? String {
                            hasYieldedPartialText = true
                            continuation.yield(text)
                        } else if event["type"] as? String == "result" {
                            if event["is_error"] as? Bool == true {
                                throw ProviderError(message: event["result"] as? String ?? "Claude Code returned an error")
                            }
                            // Older CLI versions don't emit partial messages; use the final text.
                            if !hasYieldedPartialText, let result = event["result"] as? String {
                                continuation.yield(result)
                            }
                        }
                    }
                    process.waitUntilExit()
                    if process.terminationStatus != 0 && !hasYieldedPartialText {
                        let stderr = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                        throw ProviderError(message: "claude exited with \(process.terminationStatus): \(stderr)")
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
                if process.isRunning { process.terminate() }
            }
        }
    }

    func listModels() async throws -> [String] {
        ["sonnet", "opus", "haiku"]
    }
}
