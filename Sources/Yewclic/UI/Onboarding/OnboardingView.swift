import AVFoundation
import Combine
import SwiftUI

/// The first-launch welcome guide: Welcome → Brain → Permissions → Voice → Try it.
struct OnboardingView: View {
    @ObservedObject var flow: OnboardingFlow
    @ObservedObject var settings: AppSettings
    @ObservedObject var companion: Companion
    /// Called with `true` when the user skipped instead of finishing.
    var onFinish: (_ skipped: Bool) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let windowSize = CGSize(width: 640, height: 580)

    var body: some View {
        VStack(spacing: 0) {
            OnboardingStepIndicator(flow: flow)
                .padding(.top, 34)
                .padding(.bottom, 8)

            ZStack {
                stepContent
                    .id(flow.step)
                    .transition(stepTransition)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()

            Divider()
            footer
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
        }
        .frame(width: Self.windowSize.width, height: Self.windowSize.height)
        .background(Color(nsColor: .windowBackgroundColor))
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.4, dampingFraction: 1.0), value: flow.step)
    }

    @ViewBuilder
    private var stepContent: some View {
        switch flow.step {
        case .welcome: WelcomeStep()
        case .brain: BrainStep(settings: settings)
        case .permissions: PermissionsStep(settings: settings)
        case .voice: VoiceStep(settings: settings)
        case .tryIt: TryItStep(settings: settings, companion: companion, flow: flow)
        }
    }

    /// Forward slides in from the right and leaves to the left; Back is the
    /// exact mirror, so every step leaves the way it came. Reduce Motion
    /// gets a plain cross-fade.
    private var stepTransition: AnyTransition {
        if reduceMotion { return .opacity }
        let insertionEdge: Edge = flow.isMovingForward ? .trailing : .leading
        let removalEdge: Edge = flow.isMovingForward ? .leading : .trailing
        return .asymmetric(
            insertion: .move(edge: insertionEdge).combined(with: .opacity),
            removal: .move(edge: removalEdge).combined(with: .opacity)
        )
    }

    private var footer: some View {
        HStack {
            if flow.canGoBack {
                Button("Back") { flow.goBack() }
                    .keyboardShortcut(.leftArrow, modifiers: .command)
            }
            Spacer()
            if !flow.isLastStep {
                Button("Skip setup") { onFinish(true) }
                    .buttonStyle(.link)
                    .foregroundStyle(.secondary)
                    .padding(.trailing, 8)
            }
            Button(flow.isLastStep ? "Start using yewclic" : (flow.step == .welcome ? "Get started" : "Continue")) {
                if flow.isLastStep { onFinish(false) } else { flow.goForward() }
            }
            .keyboardShortcut(.defaultAction)
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
        }
    }
}

// MARK: - Step indicator

/// Labelled segments that answer "where am I and how much is left".
/// Earlier steps can be clicked to go back.
struct OnboardingStepIndicator: View {
    @ObservedObject var flow: OnboardingFlow

    var body: some View {
        HStack(spacing: 6) {
            ForEach(OnboardingStep.allCases) { step in
                let isReached = step.position <= flow.step.position
                Button {
                    if step.position < flow.step.position { flow.move(to: step) }
                } label: {
                    VStack(spacing: 5) {
                        Capsule()
                            .fill(isReached ? Color.accentColor : Color.secondary.opacity(0.25))
                            .frame(width: 84, height: 4)
                        Text(step.shortTitle)
                            .font(.system(size: 11, weight: step == flow.step ? .semibold : .regular))
                            .foregroundStyle(step == flow.step ? .primary : .secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                // Only earlier steps are clickable. allowsHitTesting (not
                // .disabled) so the current step isn't drawn dimmed.
                .allowsHitTesting(step.position < flow.step.position)
                .accessibilityLabel("Step \(step.position + 1) of \(flow.totalSteps): \(step.shortTitle)")
            }
        }
    }
}

// MARK: - Shared pieces

private struct StepHeader: View {
    var title: String
    var subtitle: String

    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.system(size: 26, weight: .bold))
                .tracking(-0.4)
            Text(subtitle)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 470)
        }
        .padding(.top, 18)
        .padding(.bottom, 20)
    }
}

private struct StatusLine: View {
    enum Tone { case good, warning, neutral }
    var text: String
    var tone: Tone

    var body: some View {
        Label {
            Text(.init(text)).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: tone == .good ? "checkmark.circle.fill" : (tone == .warning ? "exclamationmark.circle.fill" : "info.circle"))
                .foregroundStyle(tone == .good ? Color.green : (tone == .warning ? Color.orange : Color.secondary))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct KeyCap: View {
    var symbol: String
    var name: String
    var isPressed = false

    var body: some View {
        VStack(spacing: 2) {
            Text(symbol).font(.system(size: 22, weight: .medium))
            Text(name).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
        }
        .frame(width: 74, height: 60)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isPressed ? Color.accentColor.opacity(0.25) : Color.primary.opacity(0.06))
                // Shadow on the key shape only, so it doesn't double the label text.
                .shadow(color: .black.opacity(0.12), radius: 0, y: isPressed ? 0 : 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isPressed ? Color.accentColor : Color.primary.opacity(0.15), lineWidth: 1)
        )
        .offset(y: isPressed ? 2 : 0)
    }
}

// MARK: - 1. Welcome

private struct WelcomeStep: View {
    var body: some View {
        VStack(spacing: 0) {
            Image(nsImage: NSApp.applicationIconImage ?? NSImage())
                .resizable()
                .frame(width: 104, height: 104)
                .padding(.top, 14)
                .accessibilityHidden(true)

            StepHeader(
                title: "Meet yewclic",
                subtitle: "A little helper that sits by your cursor. Ask about anything on your screen and it answers out loud, then points at what you need."
            )

            VStack(alignment: .leading, spacing: 16) {
                featureRow("keyboard", "Hold ⌃ control + ⌥ option and ask out loud", "Let go when you're done. No typing, no switching apps.")
                featureRow("eye", "It looks at your screen", "So it can answer about the app, page or error you're stuck on.")
                featureRow("cursorarrow.rays", "It points the way", "The glowing cursor flies to the button or menu you need.")
            }
            .frame(maxWidth: 440)

            Spacer(minLength: 12)

            Label("Screenshots are only taken while you hold the shortcut, and only go to the AI you choose.", systemImage: "lock.shield")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.bottom, 18)
        }
        .padding(.horizontal, 40)
    }

    private func featureRow(_ systemImage: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 18))
                .foregroundStyle(Color.accentColor)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14, weight: .semibold))
                Text(detail).font(.system(size: 13)).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - 2. Brain

private struct BrainStep: View {
    @ObservedObject var settings: AppSettings

    @State private var selectedPath: BrainPath = .local
    @State private var apiKeyDraft = ""
    @State private var fetchedModels: [String] = []
    @State private var localServerReachable: Bool?
    @State private var claudeCodePath: String?
    @State private var testResult: String?
    @State private var testSucceeded = false
    @State private var isTesting = false

    private var kind: ProviderKind { settings.activeProvider }

    private var readiness: BrainReadiness {
        BrainReadiness.evaluate(
            kind: kind,
            settings: settings.settings(for: kind),
            hasAPIKey: !apiKeyDraft.trimmingCharacters(in: .whitespaces).isEmpty,
            claudeCodeFound: claudeCodePath != nil,
            localServerReachable: localServerReachable
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            StepHeader(
                title: "Pick a brain",
                subtitle: "Choose which AI answers your questions. You can switch any time from the menu bar."
            )

            HStack(alignment: .top, spacing: 10) {
                ForEach(BrainPath.allCases) { path in
                    pathCard(path)
                }
            }
            // Cards share one height, sized to the tallest description.
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 32)

            VStack(alignment: .leading, spacing: 10) {
                pathDetails
                StatusLine(text: testResult ?? readiness.hint(for: kind),
                           tone: testResult != nil ? (testSucceeded ? .good : .warning) : (readiness.isReady ? .good : .warning))
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.04)))
            .padding(.horizontal, 32)
            .padding(.top, 14)

            Spacer(minLength: 0)
        }
        .onAppear {
            selectedPath = BrainPath.path(for: kind)
            refresh()
        }
        .onChange(of: settings.activeProvider) { refresh() }
    }

    private func pathCard(_ path: BrainPath) -> some View {
        let isSelected = selectedPath == path
        return Button {
            selectedPath = path
            if !path.providers.contains(kind) { settings.activeProvider = path.defaultProvider }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: path.systemImage)
                    .font(.system(size: 20))
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .frame(height: 26, alignment: .leading)
                Text(path.title).font(.system(size: 13, weight: .semibold))
                Text(path.subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(isSelected ? Color.accentColor.opacity(0.10) : Color.primary.opacity(0.03)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: isSelected ? 2 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var pathDetails: some View {
        switch selectedPath {
        case .local:
            Picker("App", selection: $settings.activeProvider) {
                ForEach(BrainPath.local.providers) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            modelRow
            HStack {
                Button("Check again", action: refresh)
                testButton
            }

        case .subscription:
            if let claudeCodePath {
                Text("Found Claude Code at `\(claudeCodePath)`.").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            HStack {
                Button("Check again", action: refresh)
                testButton
            }

        case .apiKey:
            HStack {
                Picker("Provider", selection: $settings.activeProvider) {
                    ForEach(BrainPath.apiKey.providers) { Text($0.displayName).tag($0) }
                }
                .frame(maxWidth: 300)
                if let keyPage = kind.apiKeyPageURL {
                    Link("Get a key", destination: keyPage).font(.system(size: 12))
                }
            }
            SecureField(kind.needsAPIKey ? "Paste your API key" : "API key (optional)", text: $apiKeyDraft)
                .textFieldStyle(.roundedBorder)
                .onChange(of: apiKeyDraft) {
                    Keychain.write(account: kind.rawValue, value: apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines))
                    testResult = nil
                }
            modelRow
            testButton
        }
    }

    private var modelRow: some View {
        HStack {
            Text("Model").font(.system(size: 12)).foregroundStyle(.secondary)
            TextField("Model id", text: Binding(
                get: { settings.settings(for: kind).model },
                set: { newModel in settings.updateSettings(for: kind) { $0.model = newModel } }
            ))
            .textFieldStyle(.roundedBorder)
            if !fetchedModels.isEmpty {
                Menu("Choose") {
                    ForEach(fetchedModels, id: \.self) { modelID in
                        Button(modelID) { settings.updateSettings(for: kind) { $0.model = modelID } }
                    }
                }
                .fixedSize()
            }
        }
    }

    private var testButton: some View {
        HStack(spacing: 8) {
            Button("Test it", action: testConnection).disabled(isTesting || readiness == .needsAPIKey)
            if isTesting { ProgressView().controlSize(.small) }
        }
    }

    /// Re-reads the key and probes the local server / CLI for the current provider.
    private func refresh() {
        apiKeyDraft = Keychain.read(account: kind.rawValue) ?? ""
        testResult = nil
        fetchedModels = []
        claudeCodePath = ClaudeCodeCLIProvider.resolveCLIPath(customCLIPath: settings.settings(for: kind).cliPath)
        localServerReachable = nil

        let probedKind = kind
        let provider = settings.makeActiveProvider()
        Task {
            let models = try? await provider.listModels()
            guard probedKind == settings.activeProvider else { return }
            fetchedModels = models ?? []
            if probedKind.isLocal {
                localServerReachable = models != nil
                // Pick an installed model if the default isn't there.
                if let models, !models.isEmpty, !models.contains(settings.settings(for: probedKind).model) {
                    settings.updateSettings(for: probedKind) { $0.model = models[0] }
                }
            }
        }
    }

    private func testConnection() {
        isTesting = true
        testResult = nil
        let provider = settings.makeActiveProvider()
        Task {
            do {
                let request = CompanionRequest(systemPrompt: "Reply with one short, friendly sentence.", history: [],
                                               userText: "Say hi in under ten words.", screenshots: [])
                var reply = ""
                for try await chunk in provider.streamReply(to: request) { reply += chunk }
                testSucceeded = true
                testResult = "It works! It said: \u{201C}\(reply.trimmingCharacters(in: .whitespacesAndNewlines))\u{201D}"
            } catch {
                testSucceeded = false
                testResult = "That didn't work: \(error.localizedDescription)"
            }
            isTesting = false
        }
    }
}

extension ProviderKind {
    /// Where to create an API key, for the "Get a key" link.
    var apiKeyPageURL: URL? {
        switch self {
        case .anthropic: return URL(string: "https://console.anthropic.com/settings/keys")
        case .openai: return URL(string: "https://platform.openai.com/api-keys")
        case .gemini: return URL(string: "https://aistudio.google.com/apikey")
        case .mistral: return URL(string: "https://console.mistral.ai/api-keys")
        case .deepseek: return URL(string: "https://platform.deepseek.com/api_keys")
        case .openRouter: return URL(string: "https://openrouter.ai/keys")
        case .groq: return URL(string: "https://console.groq.com/keys")
        default: return nil
        }
    }
}

// MARK: - 3. Permissions

private struct PermissionsStep: View {
    @ObservedObject var settings: AppSettings
    @State private var grantedPermissions: Set<AppPermission> = []
    @State private var requestedPermissions: Set<AppPermission> = []

    private let pollTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var requiredPermissions: [AppPermission] { AppPermission.required(for: settings.transcriptionMode) }
    private var allGranted: Bool { requiredPermissions.allSatisfy { grantedPermissions.contains($0) } }
    /// macOS often only reports Screen Recording / Accessibility after a restart.
    private var waitingOnRelaunch: Bool {
        requiredPermissions.contains { $0.mayNeedRelaunch && requestedPermissions.contains($0) && !grantedPermissions.contains($0) }
    }

    var body: some View {
        VStack(spacing: 0) {
            StepHeader(
                title: "A few permissions",
                subtitle: "macOS asks before any app can see your screen or hear you. Here's exactly what yewclic needs and why."
            )

            VStack(spacing: 0) {
                ForEach(Array(requiredPermissions.enumerated()), id: \.element) { index, permission in
                    permissionRow(permission)
                    if index < requiredPermissions.count - 1 { Divider().padding(.leading, 52) }
                }
            }
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.04)))
            .padding(.horizontal, 40)

            Group {
                if allGranted {
                    StatusLine(text: "All set. yewclic has everything it needs.", tone: .good)
                } else if waitingOnRelaunch {
                    HStack {
                        StatusLine(text: "Turned it on in System Settings? macOS needs yewclic to restart before it notices. You'll come straight back here.", tone: .neutral)
                        Button("Restart yewclic") { AppRelauncher.relaunch() }
                    }
                } else {
                    StatusLine(text: "Click Allow on each one. For some, macOS opens System Settings so you can switch yewclic on.", tone: .neutral)
                }
            }
            .padding(.horizontal, 40)
            .padding(.top, 14)

            Spacer(minLength: 0)
        }
        .onAppear(perform: refreshGranted)
        .onReceive(pollTimer) { _ in refreshGranted() }
    }

    private func permissionRow(_ permission: AppPermission) -> some View {
        let isGranted = grantedPermissions.contains(permission)
        return HStack(spacing: 14) {
            Image(systemName: permission.systemImage)
                .font(.system(size: 17))
                .foregroundStyle(Color.accentColor)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(permission.title).font(.system(size: 13, weight: .semibold))
                Text(permission.reason).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer()
            if isGranted {
                Label("Allowed", systemImage: "checkmark.circle.fill")
                    .labelStyle(.titleAndIcon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.green)
            } else {
                Button(requestedPermissions.contains(permission) ? "Open Settings" : "Allow") {
                    if requestedPermissions.contains(permission) {
                        permission.openSystemSettings()
                    } else {
                        requestedPermissions.insert(permission)
                        Task {
                            await permission.request()
                            refreshGranted()
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private func refreshGranted() {
        grantedPermissions = Set(AppPermission.allCases.filter { $0.isGranted })
    }
}

// MARK: - 4. Voice

private struct VoiceStep: View {
    @ObservedObject var settings: AppSettings
    @State private var samplePlayer: SystemSpeechOutput?
    @State private var isPlayingSample = false

    private var speaksAloud: Binding<Bool> {
        Binding(
            get: { settings.speechMode != .off },
            set: { settings.speechMode = $0 ? .system : .off }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            StepHeader(
                title: "How should it sound?",
                subtitle: "yewclic answers out loud with your Mac's built-in voice. It's free and works offline."
            )

            VStack(alignment: .leading, spacing: 14) {
                Toggle("Read answers out loud", isOn: speaksAloud)
                    .toggleStyle(.switch)

                if settings.speechMode == .system {
                    HStack {
                        Picker("Voice", selection: $settings.systemVoiceIdentifier) {
                            Text("Best available").tag("")
                            ForEach(SystemSpeechOutput.availableVoices, id: \.identifier) { voice in
                                Text(voice.name).tag(voice.identifier)
                            }
                        }
                        .frame(maxWidth: 300)
                        Button(isPlayingSample ? "Stop" : "Play sample", action: toggleSample)
                    }
                    Text("Want a more natural voice? Download Premium voices in System Settings → Accessibility → Spoken Content.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                } else if settings.speechMode == .off {
                    Text("Answers will appear in a bubble by your cursor instead.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                } else {
                    Text("You're using \(settings.speechMode.displayName). Change it any time in Settings → Voice.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }

                Divider()

                Toggle("Keep the glowing cursor next to my mouse all the time", isOn: $settings.alwaysShowBuddy)
                    .toggleStyle(.switch)
                Text("Off: it only appears while you're asking something.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)

                Divider()

                StatusLine(text: "yewclic listens with Apple's free on-device speech recognition. For faster live transcription, switch to AssemblyAI or Whisper in Settings → Voice.", tone: .neutral)
            }
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.04)))
            .padding(.horizontal, 40)

            Spacer(minLength: 0)
        }
        .onDisappear { samplePlayer?.stop() }
    }

    private func toggleSample() {
        if isPlayingSample {
            samplePlayer?.stop()
            return
        }
        let player = SystemSpeechOutput(voiceIdentifier: settings.systemVoiceIdentifier)
        samplePlayer = player
        isPlayingSample = true
        Task {
            try? await player.speak("Hi, I'm yewclic. Hold control and option, and ask me anything about your screen.")
            isPlayingSample = false
        }
    }
}

// MARK: - 5. Try it

private struct TryItStep: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var companion: Companion
    @ObservedObject var flow: OnboardingFlow
    @State private var hasHeardUser = false
    @State private var hasAnswered = false
    @State private var missingPermissions: [AppPermission] = []

    var body: some View {
        VStack(spacing: 0) {
            StepHeader(
                title: hasAnswered ? "You're all set" : "Give it a try",
                subtitle: hasAnswered
                    ? "That's all there is to it. Hold the keys any time you're stuck."
                    : "Hold both keys, ask a question out loud, then let go."
            )

            HStack(spacing: 10) {
                KeyCap(symbol: "⌃", name: "control", isPressed: companion.state == .listening)
                Text("+").font(.system(size: 20)).foregroundStyle(.secondary)
                KeyCap(symbol: "⌥", name: "option", isPressed: companion.state == .listening)
            }
            .animation(.spring(response: 0.2, dampingFraction: 1.0), value: companion.state)
            .padding(.bottom, 22)

            Text("Try: \u{201C}What am I looking at?\u{201D} or \u{201C}Where's the Wi-Fi setting?\u{201D}")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .padding(.bottom, 18)

            liveStatus
                .padding(14)
                .frame(maxWidth: 460)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.04)))

            if !missingPermissions.isEmpty || !brainLooksReady {
                VStack(alignment: .leading, spacing: 8) {
                    if !missingPermissions.isEmpty {
                        HStack {
                            StatusLine(text: "Still missing: \(missingPermissions.map(\.title).joined(separator: ", ")).", tone: .warning)
                            Button("Fix") { flow.move(to: .permissions) }
                        }
                    }
                    if !brainLooksReady {
                        HStack {
                            StatusLine(text: "No AI is set up yet, so it can't answer.", tone: .warning)
                            Button("Fix") { flow.move(to: .brain) }
                        }
                    }
                }
                .frame(maxWidth: 460)
                .padding(.top, 14)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 40)
        .onAppear {
            missingPermissions = AppPermission.required(for: settings.transcriptionMode).filter { !$0.isGranted }
        }
        .onChange(of: companion.state) {
            switch companion.state {
            case .listening: hasHeardUser = true
            case .speaking: hasAnswered = true
            default: break
            }
        }
    }

    /// Mirrors what the buddy is doing so the user knows it's working.
    @ViewBuilder
    private var liveStatus: some View {
        switch companion.state {
        case .listening:
            StatusLine(text: "Listening… let go when you've finished asking.", tone: .neutral)
        case .thinking:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Thinking…").font(.system(size: 12))
                Spacer()
            }
        case .speaking:
            StatusLine(text: "It's answering! Watch the cursor in case it points at something.", tone: .good)
        case .error:
            StatusLine(text: "Something went wrong. The bubble by your cursor says what.", tone: .warning)
        case .idle:
            if hasAnswered {
                StatusLine(text: "It worked. Click **Start using yewclic** to finish.", tone: .good)
            } else if hasHeardUser {
                StatusLine(text: "Didn't catch that. Hold the keys a little longer and speak clearly.", tone: .warning)
            } else {
                StatusLine(text: "Waiting for you to hold ⌃ control + ⌥ option…", tone: .neutral)
            }
        }
    }

    /// A light check (no network): key present, CLI found, or a local provider.
    private var brainLooksReady: Bool {
        let kind = settings.activeProvider
        let readiness = BrainReadiness.evaluate(
            kind: kind,
            settings: settings.settings(for: kind),
            hasAPIKey: !(Keychain.read(account: kind.rawValue) ?? "").isEmpty,
            claudeCodeFound: ClaudeCodeCLIProvider.resolveCLIPath(customCLIPath: settings.settings(for: kind).cliPath) != nil,
            localServerReachable: true
        )
        return readiness.isReady
    }
}
