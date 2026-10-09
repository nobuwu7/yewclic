import Foundation

/// How we actually talk to a provider. Almost every vendor speaks the
/// OpenAI chat-completions dialect, so most providers are just presets of it.
enum WireFormat: String, Codable {
    case anthropicMessages
    case openAICompatible
    case claudeCodeCLI
}

/// Every brain Yewclic can use. Adding a new OpenAI-compatible vendor is a
/// one-case change here.
enum ProviderKind: String, CaseIterable, Codable, Identifiable {
    case anthropic
    case claudeCode
    case openai
    case gemini
    case mistral
    case deepseek
    case qwen
    case ollama
    case lmStudio
    case openRouter
    case groq
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .anthropic: return "Claude (Anthropic API)"
        case .claudeCode: return "Claude Code (CLI, uses your subscription)"
        case .openai: return "OpenAI"
        case .gemini: return "Google Gemini"
        case .mistral: return "Mistral"
        case .deepseek: return "DeepSeek"
        case .qwen: return "Qwen (Alibaba DashScope)"
        case .ollama: return "Ollama (local)"
        case .lmStudio: return "LM Studio (local)"
        case .openRouter: return "OpenRouter"
        case .groq: return "Groq"
        case .custom: return "Custom OpenAI-compatible"
        }
    }

    var wireFormat: WireFormat {
        switch self {
        case .anthropic: return .anthropicMessages
        case .claudeCode: return .claudeCodeCLI
        default: return .openAICompatible
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .anthropic: return "https://api.anthropic.com"
        case .claudeCode: return ""
        case .openai: return "https://api.openai.com/v1"
        case .gemini: return "https://generativelanguage.googleapis.com/v1beta/openai"
        case .mistral: return "https://api.mistral.ai/v1"
        case .deepseek: return "https://api.deepseek.com/v1"
        case .qwen: return "https://dashscope-intl.aliyuncs.com/compatible-mode/v1"
        case .ollama: return "http://localhost:11434/v1"
        case .lmStudio: return "http://localhost:1234/v1"
        case .openRouter: return "https://openrouter.ai/api/v1"
        case .groq: return "https://api.groq.com/openai/v1"
        case .custom: return "http://localhost:8080/v1"
        }
    }

    /// Starting points only. Use "Fetch models" in Settings to see what your
    /// account actually has.
    var defaultModel: String {
        switch self {
        case .anthropic: return "claude-sonnet-5-5"
        case .claudeCode: return "sonnet"
        case .openai: return "gpt-4o-mini"
        case .gemini: return "gemini-2.5-flash"
        case .mistral: return "mistral-medium-latest"
        case .deepseek: return "deepseek-chat"
        case .qwen: return "qwen-vl-max"
        case .ollama: return "qwen2.5vl"
        case .lmStudio: return ""
        case .openRouter: return "google/gemini-2.5-flash"
        case .groq: return "meta-llama/llama-4-scout-17b-16e-instruct"
        case .custom: return ""
        }
    }

    var needsAPIKey: Bool {
        switch self {
        case .claudeCode, .ollama, .lmStudio, .custom: return false
        default: return true
        }
    }

    /// Whether the default model can look at images. Text-only models get an
    /// on-device OCR transcript of the screen instead.
    var defaultSupportsVision: Bool {
        switch self {
        case .deepseek: return false
        default: return true
        }
    }

    var isLocal: Bool { self == .ollama || self == .lmStudio }
}

/// User-editable settings for one provider. The API key is NOT stored here;
/// it lives in the Keychain.
struct ProviderSettings: Codable, Equatable {
    var baseURL: String
    var model: String
    var supportsVision: Bool
    /// Only used by the Claude Code provider: path to the `claude` binary.
    var cliPath: String

    static func defaults(for kind: ProviderKind) -> ProviderSettings {
        ProviderSettings(
            baseURL: kind.defaultBaseURL,
            model: kind.defaultModel,
            supportsVision: kind.defaultSupportsVision,
            cliPath: ""
        )
    }
}
