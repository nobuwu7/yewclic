import AVFoundation
import Speech
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        TabView {
            BrainSettingsView(settings: settings)
                .tabItem { Label("Brain", systemImage: "brain") }
            VoiceSettingsView(settings: settings)
                .tabItem { Label("Voice", systemImage: "waveform") }
            PermissionsView()
                .tabItem { Label("Permissions", systemImage: "lock.shield") }
        }
        .padding()
        .frame(minWidth: 520, minHeight: 560)
    }
}

// MARK: - Brain (LLM provider)

struct BrainSettingsView: View {
    @ObservedObject var settings: AppSettings
    @State private var apiKeyDraft = ""
    @State private var fetchedModels: [String] = []
    @State private var statusMessage = ""
    @State private var isBusy = false

    private var kind: ProviderKind { settings.activeProvider }

    private func binding<Value>(_ keyPath: WritableKeyPath<ProviderSettings, Value>) -> Binding<Value> {
        Binding(
            get: { settings.settings(for: kind)[keyPath: keyPath] },
            set: { newValue in settings.updateSettings(for: kind) { $0[keyPath: keyPath] = newValue } }
        )
    }

    var body: some View {
        Form {
            Section("Provider") {
                Picker("Use", selection: $settings.activeProvider) {
                    ForEach(ProviderKind.allCases) { Text($0.displayName).tag($0) }
                }
                Text(providerHint).font(.caption).foregroundStyle(.secondary)
            }

            Section("Connection") {
                if kind.wireFormat == .claudeCodeCLI {
                    TextField("Path to claude (blank = auto-detect)", text: binding(\.cliPath))
                    Text(ClaudeCodeCLIProvider.resolveCLIPath(customCLIPath: settings.settings(for: kind).cliPath).map { "Found: \($0)" }
                         ?? "Not found. Install Claude Code, then run `claude` once to sign in.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    TextField("Base URL", text: binding(\.baseURL))
                    if kind.needsAPIKey || kind == .custom {
                        SecureField(kind.needsAPIKey ? "API key" : "API key (optional)", text: $apiKeyDraft)
                            .onSubmit(saveKey)
                        HStack {
                            Button("Save key", action: saveKey)
                            Text("Stored in your Mac's Keychain.").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("Model") {
                HStack {
                    TextField("Model id", text: binding(\.model))
                    if !fetchedModels.isEmpty {
                        Menu("Pick") {
                            ForEach(fetchedModels, id: \.self) { modelID in
                                Button(modelID) { settings.updateSettings(for: kind) { $0.model = modelID } }
                            }
                        }
                        .fixedSize()
                    }
                }
                Toggle("Model can see images (send screenshots)", isOn: binding(\.supportsVision))
                Text("Turn this off for text-only models. Yewclic will read the screen's text on-device and send that instead.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Fetch models", action: fetchModels).disabled(isBusy)
                    Button("Test connection", action: testConnection).disabled(isBusy)
                    Button("Reset to defaults") {
                        settings.providerSettings[kind.rawValue] = .defaults(for: kind)
                    }
                    if isBusy { ProgressView().controlSize(.small) }
                }
                if !statusMessage.isEmpty {
                    Text(statusMessage).font(.caption).textSelection(.enabled)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: loadKey)
        .onChange(of: settings.activeProvider) {
            loadKey()
            fetchedModels = []
            statusMessage = ""
        }
    }

    private var providerHint: String {
        switch kind {
        case .claudeCode: return "Runs `claude -p` locally. No API key needed; uses your Claude Pro/Max login. Slower to start than the API."
        case .ollama: return "Run `ollama pull qwen2.5vl` (or another vision model) and keep Ollama open."
        case .lmStudio: return "Start LM Studio's local server and load a model."
        case .deepseek: return "DeepSeek's API is text-only, so the screen is sent as on-device OCR text."
        case .custom: return "Any server that speaks the OpenAI /chat/completions API (vLLM, llama.cpp, LiteLLM...)."
        default: return "Uses the \(kind.wireFormat == .anthropicMessages ? "Anthropic Messages" : "OpenAI-compatible") API."
        }
    }

    private func loadKey() {
        apiKeyDraft = Keychain.read(account: kind.rawValue) ?? ""
    }

    private func saveKey() {
        Keychain.write(account: kind.rawValue, value: apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines))
        statusMessage = "Key saved."
    }

    private func fetchModels() {
        saveKey()
        isBusy = true
        statusMessage = ""
        Task {
            do {
                fetchedModels = try await settings.makeActiveProvider().listModels()
                statusMessage = "Found \(fetchedModels.count) models. Use Pick to choose one."
            } catch {
                statusMessage = "Couldn't list models: \(error.localizedDescription)"
            }
            isBusy = false
        }
    }

    private func testConnection() {
        saveKey()
        isBusy = true
        statusMessage = ""
        Task {
            do {
                let request = CompanionRequest(systemPrompt: "Reply with one short sentence.", history: [],
                                               userText: "Say hi and tell me which model you are.", screenshot: nil)
                var reply = ""
                for try await chunk in settings.makeActiveProvider().streamReply(to: request) { reply += chunk }
                statusMessage = "✓ \(reply.trimmingCharacters(in: .whitespacesAndNewlines))"
            } catch {
                statusMessage = "✗ \(error.localizedDescription)"
            }
            isBusy = false
        }
    }
}

// MARK: - Voice (speech in / speech out)

struct VoiceSettingsView: View {
    @ObservedObject var settings: AppSettings
    @State private var whisperKeyDraft = ""
    @State private var speechKeyDraft = ""

    var body: some View {
        Form {
            Section("Listening (speech to text)") {
                Picker("Engine", selection: $settings.transcriptionMode) {
                    ForEach(TranscriptionMode.allCases) { Text($0.displayName).tag($0) }
                }
                if settings.transcriptionMode == .whisperUpload {
                    TextField("Base URL", text: $settings.whisperBaseURL)
                    TextField("Model", text: $settings.whisperModel)
                    SecureField("API key (blank for local servers)", text: $whisperKeyDraft)
                        .onSubmit { Keychain.write(account: SecretAccount.whisper, value: whisperKeyDraft) }
                    Button("Save key") { Keychain.write(account: SecretAccount.whisper, value: whisperKeyDraft) }
                }
            }

            Section("Talking (text to speech)") {
                Picker("Voice engine", selection: $settings.speechMode) {
                    ForEach(SpeechMode.allCases) { Text($0.displayName).tag($0) }
                }
                switch settings.speechMode {
                case .system:
                    Picker("Voice", selection: $settings.systemVoiceIdentifier) {
                        Text("Best available").tag("")
                        ForEach(SystemSpeechOutput.availableVoices, id: \.identifier) { voice in
                            Text("\(voice.name) (\(qualityName(voice.quality)))").tag(voice.identifier)
                        }
                    }
                    Text("Tip: download Premium/Enhanced voices in System Settings → Accessibility → Spoken Content.")
                        .font(.caption).foregroundStyle(.secondary)
                case .openAICompatible, .elevenLabs:
                    if settings.speechMode == .openAICompatible {
                        TextField("Base URL", text: $settings.remoteSpeechBaseURL)
                    }
                    TextField("Model", text: $settings.remoteSpeechModel)
                    TextField(settings.speechMode == .elevenLabs ? "Voice ID" : "Voice", text: $settings.remoteSpeechVoice)
                    SecureField("API key", text: $speechKeyDraft)
                        .onSubmit { Keychain.write(account: SecretAccount.textToSpeech, value: speechKeyDraft) }
                    Button("Save key") { Keychain.write(account: SecretAccount.textToSpeech, value: speechKeyDraft) }
                case .off:
                    EmptyView()
                }
            }

            Section("Memory") {
                Stepper("Remember last \(settings.rememberedTurnPairs) exchanges", value: $settings.rememberedTurnPairs, in: 0...20)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            whisperKeyDraft = Keychain.read(account: SecretAccount.whisper) ?? ""
            speechKeyDraft = Keychain.read(account: SecretAccount.textToSpeech) ?? ""
        }
    }

    private func qualityName(_ quality: AVSpeechSynthesisVoiceQuality) -> String {
        switch quality {
        case .premium: return "Premium"
        case .enhanced: return "Enhanced"
        default: return "Default"
        }
    }
}

// MARK: - Permissions

struct PermissionsView: View {
    @State private var refreshTick = 0

    var body: some View {
        Form {
            Section {
                permissionRow(
                    title: "Screen Recording",
                    detail: "So Yewclic can see your screen when you hold the shortcut.",
                    isGranted: ScreenCapture.hasPermission,
                    action: ScreenCapture.requestPermission,
                    settingsAnchor: "Privacy_ScreenCapture"
                )
                permissionRow(
                    title: "Accessibility",
                    detail: "So the ⌃⌥ push-to-talk shortcut works in every app.",
                    isGranted: PushToTalkMonitor.hasAccessibilityPermission,
                    action: PushToTalkMonitor.requestAccessibilityPermission,
                    settingsAnchor: "Privacy_Accessibility"
                )
                permissionRow(
                    title: "Microphone",
                    detail: "So it can hear you while you hold the shortcut.",
                    isGranted: MicrophonePermission.isGranted,
                    action: { Task { _ = await MicrophonePermission.request(); refreshTick += 1 } },
                    settingsAnchor: "Privacy_Microphone"
                )
                permissionRow(
                    title: "Speech Recognition",
                    detail: "Only needed for the Apple Speech engine.",
                    isGranted: SFSpeechAuthorization.isGranted,
                    action: { Task { _ = await AppleSpeechTranscriber.requestPermission(); refreshTick += 1 } },
                    settingsAnchor: "Privacy_SpeechRecognition"
                )
            } footer: {
                Text("Screen Recording and Accessibility changes may need Yewclic to restart.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Button("Refresh") { refreshTick += 1 }
        }
        .formStyle(.grouped)
        .id(refreshTick)
    }

    private func permissionRow(title: String, detail: String, isGranted: Bool, action: @escaping () -> Void, settingsAnchor: String) -> some View {
        HStack {
            Image(systemName: isGranted ? "checkmark.circle.fill" : "exclamationmark.circle")
                .foregroundStyle(isGranted ? .green : .orange)
            VStack(alignment: .leading) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !isGranted {
                Button("Grant") { action() }
                Button("Open Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(settingsAnchor)") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
    }
}

enum SFSpeechAuthorization {
    static var isGranted: Bool { SFSpeechRecognizer.authorizationStatus() == .authorized }
}
