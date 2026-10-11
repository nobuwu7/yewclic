import AppKit
import AVFoundation
import Foundation
import Speech

/// The welcome guide's steps, in order.
enum OnboardingStep: String, CaseIterable, Identifiable {
    case welcome
    case brain
    case permissions
    case voice
    case tryIt

    var id: String { rawValue }

    /// Short name for the step indicator.
    var shortTitle: String {
        switch self {
        case .welcome: return "Welcome"
        case .brain: return "Brain"
        case .permissions: return "Permissions"
        case .voice: return "Voice"
        case .tryIt: return "Try it"
        }
    }

    var position: Int { Self.allCases.firstIndex(of: self)! }
}

/// Moves through the guide and remembers which way it's going, so the view
/// can slide steps in from the right (forward) or left (back).
@MainActor
final class OnboardingFlow: ObservableObject {
    @Published private(set) var step: OnboardingStep
    @Published private(set) var isMovingForward = true

    /// Called whenever the step changes, so progress survives a relaunch.
    var onStepChange: ((OnboardingStep) -> Void)?

    init(startingAt step: OnboardingStep = .welcome) {
        self.step = step
    }

    var canGoBack: Bool { step != .welcome }
    var isLastStep: Bool { step == OnboardingStep.allCases.last }
    var stepNumber: Int { step.position + 1 }
    var totalSteps: Int { OnboardingStep.allCases.count }

    func goForward() {
        guard !isLastStep else { return }
        move(to: OnboardingStep.allCases[step.position + 1])
    }

    func goBack() {
        guard canGoBack else { return }
        move(to: OnboardingStep.allCases[step.position - 1])
    }

    /// Jump straight to a step, e.g. from the step indicator.
    func move(to newStep: OnboardingStep) {
        guard newStep != step else { return }
        isMovingForward = newStep.position > step.position
        step = newStep
        onStepChange?(newStep)
    }
}

// MARK: - Choosing a brain

/// The three ways to power yewclic, in plain words. Each maps to providers.
enum BrainPath: String, CaseIterable, Identifiable {
    case local
    case subscription
    case apiKey

    var id: String { rawValue }

    var title: String {
        switch self {
        case .local: return "Free and private"
        case .subscription: return "My Claude plan"
        case .apiKey: return "An API key"
        }
    }

    var subtitle: String {
        switch self {
        case .local: return "Runs on this Mac with Ollama or LM Studio. Nothing leaves your computer."
        case .subscription: return "Uses Claude Code with your Pro or Max login. No key needed."
        case .apiKey: return "Claude, OpenAI, Gemini, Mistral, DeepSeek, Qwen and more. Fastest replies."
        }
    }

    var systemImage: String {
        switch self {
        case .local: return "lock.laptopcomputer"
        case .subscription: return "person.crop.circle.badge.checkmark"
        case .apiKey: return "key.horizontal"
        }
    }

    var providers: [ProviderKind] {
        switch self {
        case .local: return [.ollama, .lmStudio]
        case .subscription: return [.claudeCode]
        case .apiKey: return [.anthropic, .openai, .gemini, .mistral, .deepseek, .qwen, .openRouter, .groq, .custom]
        }
    }

    var defaultProvider: ProviderKind { providers[0] }

    static func path(for kind: ProviderKind) -> BrainPath {
        allCases.first { $0.providers.contains(kind) } ?? .apiKey
    }
}

/// Whether the chosen brain is usable yet, and if not, what's missing.
enum BrainReadiness: Equatable {
    case ready
    case needsAPIKey
    case needsModel
    case needsClaudeCode
    case localServerNotRunning
    case unknown

    var isReady: Bool { self == .ready }

    /// One plain sentence telling the user what to do next.
    func hint(for kind: ProviderKind) -> String {
        switch self {
        case .ready: return "Ready to go."
        case .needsAPIKey: return "Paste your \(kind.displayName) key to continue."
        case .needsModel: return "Pick a model to use."
        case .needsClaudeCode: return "Install Claude Code, then run `claude` once in Terminal to sign in."
        case .localServerNotRunning:
            return kind == .ollama
                ? "Open Ollama, then run `ollama pull qwen2.5vl` in Terminal to get a model that can see."
                : "Open LM Studio, load a model and start its local server."
        case .unknown: return "Checking…"
        }
    }

    /// Works out readiness from facts the caller has already gathered, so the
    /// rules stay easy to test.
    static func evaluate(
        kind: ProviderKind,
        settings: ProviderSettings,
        hasAPIKey: Bool,
        claudeCodeFound: Bool,
        localServerReachable: Bool?
    ) -> BrainReadiness {
        switch kind.wireFormat {
        case .claudeCodeCLI:
            return claudeCodeFound ? .ready : .needsClaudeCode
        case .anthropicMessages, .openAICompatible:
            if kind.isLocal {
                guard let localServerReachable else { return .unknown }
                if !localServerReachable { return .localServerNotRunning }
            } else if kind.needsAPIKey && !hasAPIKey {
                return .needsAPIKey
            }
            return settings.model.trimmingCharacters(in: .whitespaces).isEmpty ? .needsModel : .ready
        }
    }
}

// MARK: - Permissions

/// The macOS permissions yewclic asks for, each with the reason shown to the user.
enum AppPermission: String, CaseIterable, Identifiable {
    case screenRecording
    case accessibility
    case microphone
    case speechRecognition

    var id: String { rawValue }

    var title: String {
        switch self {
        case .screenRecording: return "Screen Recording"
        case .accessibility: return "Accessibility"
        case .microphone: return "Microphone"
        case .speechRecognition: return "Speech Recognition"
        }
    }

    var reason: String {
        switch self {
        case .screenRecording: return "To see your screen, only while you hold the shortcut."
        case .accessibility: return "To notice ⌃⌥ in any app."
        case .microphone: return "To hear your question while you hold the shortcut."
        case .speechRecognition: return "To turn your voice into text on this Mac."
        }
    }

    var systemImage: String {
        switch self {
        case .screenRecording: return "rectangle.dashed.badge.record"
        case .accessibility: return "keyboard"
        case .microphone: return "mic"
        case .speechRecognition: return "waveform"
        }
    }

    /// System Settings pane for this permission.
    var settingsURL: URL? {
        let anchor: String
        switch self {
        case .screenRecording: anchor = "Privacy_ScreenCapture"
        case .accessibility: anchor = "Privacy_Accessibility"
        case .microphone: anchor = "Privacy_Microphone"
        case .speechRecognition: anchor = "Privacy_SpeechRecognition"
        }
        return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")
    }

    /// macOS only reports these as granted after the app restarts.
    var mayNeedRelaunch: Bool { self == .screenRecording || self == .accessibility }

    /// Speech Recognition is only needed for Apple's on-device engine.
    static func required(for transcriptionMode: TranscriptionMode) -> [AppPermission] {
        transcriptionMode == .appleOnDevice ? allCases : allCases.filter { $0 != .speechRecognition }
    }

    @MainActor
    var isGranted: Bool {
        switch self {
        case .screenRecording: return ScreenCapture.hasPermission
        case .accessibility: return PushToTalkMonitor.hasAccessibilityPermission
        case .microphone: return MicrophonePermission.isGranted
        case .speechRecognition: return SFSpeechRecognizer.authorizationStatus() == .authorized
        }
    }

    /// Shows the system prompt (or opens System Settings when macOS won't
    /// prompt again).
    @MainActor
    func request() async {
        switch self {
        case .screenRecording:
            ScreenCapture.requestPermission()
        case .accessibility:
            PushToTalkMonitor.requestAccessibilityPermission()
        case .microphone:
            if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
                _ = await MicrophonePermission.request()
            } else {
                openSystemSettings()
            }
        case .speechRecognition:
            if SFSpeechRecognizer.authorizationStatus() == .notDetermined {
                _ = await AppleSpeechTranscriber.requestPermission()
            } else {
                openSystemSettings()
            }
        }
    }

    @MainActor
    func openSystemSettings() {
        if let settingsURL { NSWorkspace.shared.open(settingsURL) }
    }
}

enum AppRelauncher {
    /// Quits and reopens yewclic so macOS applies newly granted permissions.
    static func relaunch() {
        let bundlePath = Bundle.main.bundlePath
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "sleep 0.6; /usr/bin/open \"$0\"", bundlePath]
        try? process.run()
        NSApp.terminate(nil)
    }
}
