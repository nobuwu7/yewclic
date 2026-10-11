import AVFoundation
import Speech

/// Turns push-to-talk audio into text. `start` runs on key-down, `finish` on
/// key-up and returns the final transcript.
@MainActor
protocol Transcriber: AnyObject {
    var onAudioLevel: ((Float) -> Void)? { get set }
    func start() throws
    func finish() async throws -> String
    func cancel()
}

enum MicrophonePermission {
    static var isGranted: Bool { AVCaptureDevice.authorizationStatus(for: .audio) == .authorized }

    static func request() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }
}

func rootMeanSquareLevel(of buffer: AVAudioPCMBuffer) -> Float {
    guard let channelData = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
    var sumOfSquares: Float = 0
    for frameIndex in 0..<Int(buffer.frameLength) {
        sumOfSquares += channelData[frameIndex] * channelData[frameIndex]
    }
    let rms = sqrt(sumOfSquares / Float(buffer.frameLength))
    // Rough perceptual scaling so normal speech fills most of the meter.
    return min(1, rms * 12)
}

// MARK: - Apple Speech (free, on-device when available)

@MainActor
final class AppleSpeechTranscriber: Transcriber {
    var onAudioLevel: ((Float) -> Void)?

    private let audioEngine = AVAudioEngine()
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale.current) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var latestTranscript = ""
    private var finalTranscriptContinuation: CheckedContinuation<String, Never>?

    static func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    func start() throws {
        guard let speechRecognizer, speechRecognizer.isAvailable else {
            throw ProviderError(message: "Speech recognition isn't available right now")
        }
        latestTranscript = ""

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if speechRecognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        recognitionRequest = request

        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            let transcript = result?.bestTranscription.formattedString
            let isFinal = (result?.isFinal ?? false) || error != nil
            Task { @MainActor in
                guard let self else { return }
                if let transcript { self.latestTranscript = transcript }
                if isFinal { self.resolveFinalTranscript() }
            }
        }

        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            request.append(buffer)
            let level = rootMeanSquareLevel(of: buffer)
            Task { @MainActor in self?.onAudioLevel?(level) }
        }
        audioEngine.prepare()
        try audioEngine.start()
    }

    func finish() async throws -> String {
        stopAudio()
        recognitionRequest?.endAudio()
        guard recognitionTask != nil else { return latestTranscript }

        // Wait for the recogniser's final result, but never hang the UI on it.
        let transcript = await withCheckedContinuation { continuation in
            finalTranscriptContinuation = continuation
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                self.resolveFinalTranscript()
            }
        }
        recognitionTask = nil
        recognitionRequest = nil
        return transcript
    }

    func cancel() {
        stopAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        resolveFinalTranscript()
    }

    private func resolveFinalTranscript() {
        finalTranscriptContinuation?.resume(returning: latestTranscript)
        finalTranscriptContinuation = nil
    }

    private func stopAudio() {
        if audioEngine.isRunning { audioEngine.stop() }
        audioEngine.inputNode.removeTap(onBus: 0)
    }
}

// MARK: - Whisper-style upload (OpenAI, Groq, local whisper servers...)

/// Records to a WAV file, then uploads it to any OpenAI-compatible
/// `/audio/transcriptions` endpoint.
@MainActor
final class WhisperUploadTranscriber: Transcriber {
    var onAudioLevel: ((Float) -> Void)?

    private let baseURL: String
    private let model: String
    private let apiKey: String
    private let audioEngine = AVAudioEngine()
    private var audioFile: AVAudioFile?
    private var recordingURL: URL?

    init(baseURL: String, model: String, apiKey: String) {
        self.baseURL = baseURL
        self.model = model
        self.apiKey = apiKey
    }

    func start() throws {
        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("yewclic-\(UUID().uuidString).wav")
        let fileSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: inputFormat.sampleRate,
            AVNumberOfChannelsKey: inputFormat.channelCount,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
        ]
        let file = try AVAudioFile(forWriting: url, settings: fileSettings, commonFormat: .pcmFormatFloat32, interleaved: false)
        audioFile = file
        recordingURL = url

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            try? file.write(from: buffer)
            let level = rootMeanSquareLevel(of: buffer)
            Task { @MainActor in self?.onAudioLevel?(level) }
        }
        audioEngine.prepare()
        try audioEngine.start()
    }

    func finish() async throws -> String {
        stopAudio()
        audioFile = nil // closes the file
        guard let recordingURL else { return "" }
        defer { try? FileManager.default.removeItem(at: recordingURL) }

        let audioData = try Data(contentsOf: recordingURL)
        let boundary = "yewclic-\(UUID().uuidString)"
        var body = Data()
        func appendField(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".data(using: .utf8)!)
        }
        appendField("model", model)
        appendField("response_format", "json")
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"speech.wav\"\r\nContent-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        var request = URLRequest(url: try HTTPStreaming.joinURL(baseURL, "/audio/transcriptions"))
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        if !apiKey.isEmpty { request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
        request.httpBody = body

        let json = try await HTTPStreaming.fetchJSON(request)
        return (json["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func cancel() {
        stopAudio()
        audioFile = nil
        if let recordingURL { try? FileManager.default.removeItem(at: recordingURL) }
    }

    private func stopAudio() {
        if audioEngine.isRunning { audioEngine.stop() }
        audioEngine.inputNode.removeTap(onBus: 0)
    }
}
