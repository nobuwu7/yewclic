import AVFoundation
import Foundation

/// Real-time streaming transcription over AssemblyAI's v3 websocket (the
/// engine Clicky uses). Text arrives while you're still talking, so the
/// answer starts sooner after you let go.
///
/// Clicky fetched the temporary token through its Cloudflare Worker; Yewclic
/// fetches it directly with your own key from the Keychain.
@MainActor
final class AssemblyAITranscriber: Transcriber {
    var onAudioLevel: ((Float) -> Void)?

    private static let sampleRate = 16_000.0
    /// One shared URLSession for every session. Clicky found that creating and
    /// invalidating one per session corrupts the connection pool after a few
    /// rapid reconnects ("Socket is not connected").
    private static let sharedWebSocketSession = URLSession(configuration: .default)

    private let apiKey: String
    private let audioEngine = AVAudioEngine()
    private let pcmConverter = PCM16AudioConverter(targetSampleRate: sampleRate)
    private var webSocketTask: URLSessionWebSocketTask?
    private var connectTask: Task<Void, Error>?
    /// Audio recorded before the websocket finished opening.
    private var pendingAudioChunks: [Data] = []

    /// Finished turns by turn order, plus the turn currently being spoken.
    private var completedTurns: [Int: String] = [:]
    private var activeTurnText = ""
    private var finalTranscriptContinuation: CheckedContinuation<Void, Never>?
    private var isWaitingForFinalTurn = false

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    func start() throws {
        guard !apiKey.isEmpty else {
            throw ProviderError(message: "Add your AssemblyAI API key in Settings → Voice.")
        }

        // Start recording immediately; the websocket catches up a moment later.
        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        let converter = pcmConverter
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            let level = rootMeanSquareLevel(of: buffer)
            let pcmData = converter.convertToPCM16Data(from: buffer)
            Task { @MainActor in
                guard let self else { return }
                self.onAudioLevel?(level)
                if let pcmData, !pcmData.isEmpty { self.sendAudio(pcmData) }
            }
        }
        audioEngine.prepare()
        try audioEngine.start()

        connectTask = Task { try await connect() }
    }

    func finish() async throws -> String {
        stopAudio()
        do {
            try await connectTask?.value
        } catch {
            closeSocket()
            throw error
        }

        // Ask AssemblyAI to finalise the current turn now, then wait briefly for it.
        isWaitingForFinalTurn = true
        sendJSON(["type": "ForceEndpoint"])
        await withCheckedContinuation { continuation in
            finalTranscriptContinuation = continuation
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.4))
                self.resolveFinalTranscript()
            }
        }
        closeSocket()
        return composeTranscript()
    }

    func cancel() {
        stopAudio()
        connectTask?.cancel()
        closeSocket()
        resolveFinalTranscript()
    }

    // MARK: - Websocket

    private func connect() async throws {
        var tokenRequest = URLRequest(url: URL(string: "https://streaming.assemblyai.com/v3/token?expires_in_seconds=480")!)
        tokenRequest.setValue(apiKey, forHTTPHeaderField: "Authorization")
        let tokenJSON = try await HTTPStreaming.fetchJSON(tokenRequest)
        guard let token = tokenJSON["token"] as? String else {
            throw ProviderError(message: "AssemblyAI didn't return a token")
        }

        var components = URLComponents(string: "wss://streaming.assemblyai.com/v3/ws")!
        components.queryItems = [
            URLQueryItem(name: "sample_rate", value: "16000"),
            URLQueryItem(name: "encoding", value: "pcm_s16le"),
            URLQueryItem(name: "format_turns", value: "true"),
            URLQueryItem(name: "speech_model", value: "u3-rt-pro"),
            URLQueryItem(name: "token", value: token),
        ]
        let task = Self.sharedWebSocketSession.webSocketTask(with: components.url!)
        webSocketTask = task
        task.resume()
        receiveNextMessage()

        for chunk in pendingAudioChunks { task.send(.data(chunk)) { _ in } }
        pendingAudioChunks.removeAll()
    }

    private func sendAudio(_ pcmData: Data) {
        if let webSocketTask {
            webSocketTask.send(.data(pcmData)) { _ in }
        } else {
            pendingAudioChunks.append(pcmData)
        }
    }

    private func sendJSON(_ object: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let text = String(data: data, encoding: .utf8) else { return }
        webSocketTask?.send(.string(text)) { _ in }
    }

    private func receiveNextMessage() {
        webSocketTask?.receive { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                switch result {
                case .success(.string(let text)):
                    self.handleMessage(text)
                    self.receiveNextMessage()
                case .success(.data(let data)):
                    self.handleMessage(String(data: data, encoding: .utf8) ?? "")
                    self.receiveNextMessage()
                case .success:
                    self.receiveNextMessage()
                case .failure:
                    self.resolveFinalTranscript()
                }
            }
        }
    }

    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let message = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              message["type"] as? String == "Turn" else { return }

        let transcript = (message["transcript"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let turnOrder = message["turn_order"] as? Int ?? (completedTurns.keys.max() ?? -1) + 1
        let isTurnFinished = message["end_of_turn"] as? Bool == true || message["turn_is_formatted"] as? Bool == true

        if isTurnFinished {
            if !transcript.isEmpty { completedTurns[turnOrder] = transcript }
            activeTurnText = ""
            if isWaitingForFinalTurn { resolveFinalTranscript() }
        } else {
            activeTurnText = transcript
        }
    }

    private func composeTranscript() -> String {
        let turns = completedTurns.sorted { $0.key < $1.key }.map(\.value) + (activeTurnText.isEmpty ? [] : [activeTurnText])
        return turns.joined(separator: " ")
    }

    private func resolveFinalTranscript() {
        finalTranscriptContinuation?.resume()
        finalTranscriptContinuation = nil
    }

    private func closeSocket() {
        sendJSON(["type": "Terminate"])
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
    }

    private func stopAudio() {
        if audioEngine.isRunning { audioEngine.stop() }
        audioEngine.inputNode.removeTap(onBus: 0)
    }
}

/// Converts live mic buffers (any format) to 16-bit mono PCM at a target
/// sample rate. Adapted from Clicky's BuddyPCM16AudioConverter (MIT).
final class PCM16AudioConverter: @unchecked Sendable {
    private let targetFormat: AVAudioFormat
    private var converter: AVAudioConverter?
    private var currentInputFormat: AVAudioFormat?
    private let lock = NSLock()

    init(targetSampleRate: Double) {
        targetFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: targetSampleRate, channels: 1, interleaved: true)!
    }

    func convertToPCM16Data(from buffer: AVAudioPCMBuffer) -> Data? {
        lock.lock()
        defer { lock.unlock() }

        if currentInputFormat != buffer.format {
            converter = AVAudioConverter(from: buffer.format, to: targetFormat)
            currentInputFormat = buffer.format
        }
        guard let converter else { return nil }

        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up) + 32)
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return nil }

        var hasProvidedInput = false
        var conversionError: NSError?
        let status = converter.convert(to: outputBuffer, error: &conversionError) { _, inputStatus in
            if hasProvidedInput {
                inputStatus.pointee = .noDataNow
                return nil
            }
            hasProvidedInput = true
            inputStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, let bytes = outputBuffer.audioBufferList.pointee.mBuffers.mData else { return nil }

        let byteCount = Int(outputBuffer.frameLength) * Int(targetFormat.streamDescription.pointee.mBytesPerFrame)
        return byteCount > 0 ? Data(bytes: bytes, count: byteCount) : nil
    }
}
