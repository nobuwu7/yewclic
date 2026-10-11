import Foundation
import Security

enum TranscriptionMode: String, CaseIterable, Codable, Identifiable {
    case appleOnDevice
    case assemblyAIStreaming
    case whisperUpload
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .appleOnDevice: return "Apple Speech (free, on-device)"
        case .assemblyAIStreaming: return "AssemblyAI live streaming (fastest, what Clicky uses)"
        case .whisperUpload: return "Whisper-compatible API (OpenAI, Groq, local)"
        }
    }
}

enum SpeechMode: String, CaseIterable, Codable, Identifiable {
    case system
    case openAICompatible
    case elevenLabs
    case off
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .system: return "macOS voice (free, offline)"
        case .openAICompatible: return "OpenAI-compatible /audio/speech"
        case .elevenLabs: return "ElevenLabs"
        case .off: return "Off (text bubble only)"
        }
    }
}

/// Keychain accounts for secrets that aren't tied to a chat provider.
enum SecretAccount {
    static let whisper = "speech-to-text"
    static let assemblyAI = "assemblyai"
    static let textToSpeech = "text-to-speech"
}

/// All user settings. Non-secret values persist in UserDefaults; API keys go
/// to the Keychain via `Keychain`.
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    private let defaults = UserDefaults.standard

    @Published var activeProvider: ProviderKind { didSet { save() } }
    @Published var providerSettings: [String: ProviderSettings] { didSet { save() } }

    @Published var transcriptionMode: TranscriptionMode { didSet { save() } }
    @Published var whisperBaseURL: String { didSet { save() } }
    @Published var whisperModel: String { didSet { save() } }

    @Published var speechMode: SpeechMode { didSet { save() } }
    @Published var systemVoiceIdentifier: String { didSet { save() } }
    @Published var remoteSpeechBaseURL: String { didSet { save() } }
    @Published var remoteSpeechModel: String { didSet { save() } }
    @Published var remoteSpeechVoice: String { didSet { save() } }

    /// How many previous question/answer pairs to send as context.
    @Published var rememberedTurnPairs: Int { didSet { save() } }

    /// Keep the buddy next to the cursor all the time (Clicky's "Show Clicky").
    /// When off it only appears while you're asking something.
    @Published var alwaysShowBuddy: Bool { didSet { save() } }

    private init() {
        activeProvider = ProviderKind(rawValue: defaults.string(forKey: "activeProvider") ?? "") ?? .anthropic
        if let data = defaults.data(forKey: "providerSettings"),
           let decoded = try? JSONDecoder().decode([String: ProviderSettings].self, from: data) {
            providerSettings = decoded
        } else {
            providerSettings = [:]
        }
        transcriptionMode = TranscriptionMode(rawValue: defaults.string(forKey: "transcriptionMode") ?? "") ?? .appleOnDevice
        whisperBaseURL = defaults.string(forKey: "whisperBaseURL") ?? "https://api.groq.com/openai/v1"
        whisperModel = defaults.string(forKey: "whisperModel") ?? "whisper-large-v3-turbo"
        speechMode = SpeechMode(rawValue: defaults.string(forKey: "speechMode") ?? "") ?? .system
        systemVoiceIdentifier = defaults.string(forKey: "systemVoiceIdentifier") ?? ""
        remoteSpeechBaseURL = defaults.string(forKey: "remoteSpeechBaseURL") ?? "https://api.openai.com/v1"
        remoteSpeechModel = defaults.string(forKey: "remoteSpeechModel") ?? "gpt-4o-mini-tts"
        remoteSpeechVoice = defaults.string(forKey: "remoteSpeechVoice") ?? "alloy"
        rememberedTurnPairs = defaults.object(forKey: "rememberedTurnPairs") as? Int ?? 6
        alwaysShowBuddy = defaults.object(forKey: "alwaysShowBuddy") as? Bool ?? false
    }

    func settings(for kind: ProviderKind) -> ProviderSettings {
        providerSettings[kind.rawValue] ?? .defaults(for: kind)
    }

    func updateSettings(for kind: ProviderKind, _ change: (inout ProviderSettings) -> Void) {
        var updated = settings(for: kind)
        change(&updated)
        providerSettings[kind.rawValue] = updated
    }

    func makeActiveProvider() -> LLMProvider {
        ProviderFactory.makeProvider(
            kind: activeProvider,
            settings: settings(for: activeProvider),
            apiKey: Keychain.read(account: activeProvider.rawValue) ?? ""
        )
    }

    private func save() {
        defaults.set(activeProvider.rawValue, forKey: "activeProvider")
        defaults.set(try? JSONEncoder().encode(providerSettings), forKey: "providerSettings")
        defaults.set(transcriptionMode.rawValue, forKey: "transcriptionMode")
        defaults.set(whisperBaseURL, forKey: "whisperBaseURL")
        defaults.set(whisperModel, forKey: "whisperModel")
        defaults.set(speechMode.rawValue, forKey: "speechMode")
        defaults.set(systemVoiceIdentifier, forKey: "systemVoiceIdentifier")
        defaults.set(remoteSpeechBaseURL, forKey: "remoteSpeechBaseURL")
        defaults.set(remoteSpeechModel, forKey: "remoteSpeechModel")
        defaults.set(remoteSpeechVoice, forKey: "remoteSpeechVoice")
        defaults.set(rememberedTurnPairs, forKey: "rememberedTurnPairs")
        defaults.set(alwaysShowBuddy, forKey: "alwaysShowBuddy")
    }
}

/// Minimal generic-password Keychain wrapper. Keys never touch UserDefaults
/// or disk in plain text.
enum Keychain {
    private static let service = "com.yewclic.app"

    static func read(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func write(account: String, value: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        guard !value.isEmpty else { return }
        var item = query
        item[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(item as CFDictionary, nil)
    }
}
