import AVFoundation

/// Speaks replies aloud. `speak` returns when playback ends (or is stopped).
@MainActor
protocol SpeechOutput: AnyObject {
    func speak(_ text: String) async throws
    func stop()
}

// MARK: - Built-in macOS voice (free, offline)

@MainActor
final class SystemSpeechOutput: NSObject, SpeechOutput, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private let voiceIdentifier: String
    private var finishedContinuation: CheckedContinuation<Void, Never>?

    init(voiceIdentifier: String) {
        self.voiceIdentifier = voiceIdentifier
        super.init()
        synthesizer.delegate = self
    }

    static var availableVoices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix(Locale.current.language.languageCode?.identifier ?? "en") }
            .sorted { ($0.quality.rawValue, $0.name) > ($1.quality.rawValue, $1.name) }
    }

    func speak(_ text: String) async throws {
        let utterance = AVSpeechUtterance(string: text)
        if !voiceIdentifier.isEmpty, let voice = AVSpeechSynthesisVoice(identifier: voiceIdentifier) {
            utterance.voice = voice
        } else {
            utterance.voice = Self.availableVoices.first
        }
        await withCheckedContinuation { continuation in
            finishedContinuation = continuation
            synthesizer.speak(utterance)
        }
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        resume()
    }

    private func resume() {
        finishedContinuation?.resume()
        finishedContinuation = nil
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.resume() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.resume() }
    }
}

// MARK: - Remote voices (OpenAI-compatible /audio/speech, ElevenLabs)

/// Downloads synthesized audio and plays it.
@MainActor
final class RemoteAudioSpeechOutput: NSObject, SpeechOutput, AVAudioPlayerDelegate {
    enum Service { case openAICompatible, elevenLabs }

    private let service: Service
    private let baseURL: String
    private let model: String
    private let voice: String
    private let apiKey: String
    private var player: AVAudioPlayer?
    private var finishedContinuation: CheckedContinuation<Void, Never>?

    init(service: Service, baseURL: String, model: String, voice: String, apiKey: String) {
        self.service = service
        self.baseURL = baseURL
        self.model = model
        self.voice = voice
        self.apiKey = apiKey
    }

    func speak(_ text: String) async throws {
        let request = try buildRequest(for: text)
        let (audioData, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse, !(200..<300).contains(httpResponse.statusCode) {
            throw ProviderError(message: "TTS HTTP \(httpResponse.statusCode): \(String(data: audioData, encoding: .utf8) ?? "")")
        }
        let audioPlayer = try AVAudioPlayer(data: audioData)
        audioPlayer.delegate = self
        player = audioPlayer
        await withCheckedContinuation { continuation in
            finishedContinuation = continuation
            audioPlayer.play()
        }
    }

    func stop() {
        player?.stop()
        resume()
    }

    private func resume() {
        finishedContinuation?.resume()
        finishedContinuation = nil
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.resume() }
    }

    private func buildRequest(for text: String) throws -> URLRequest {
        switch service {
        case .openAICompatible:
            var request = URLRequest(url: try HTTPStreaming.joinURL(baseURL, "/audio/speech"))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if !apiKey.isEmpty { request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "model": model, "voice": voice, "input": text, "response_format": "mp3",
            ])
            return request
        case .elevenLabs:
            let voiceID = voice.isEmpty ? "21m00Tcm4TlvDq8ikWAM" : voice
            var request = URLRequest(url: try HTTPStreaming.joinURL("https://api.elevenlabs.io", "/v1/text-to-speech/\(voiceID)"))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
            request.setValue("audio/mpeg", forHTTPHeaderField: "Accept")
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "text": text, "model_id": model.isEmpty ? "eleven_flash_v2_5" : model,
            ])
            return request
        }
    }
}

// MARK: - Silent

@MainActor
final class SilentSpeechOutput: SpeechOutput {
    func speak(_ text: String) async throws {}
    func stop() {}
}
