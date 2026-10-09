import AppKit
import Combine

/// The whole push-to-talk loop:
/// hold ⌃⌥ → listen + screenshot every display → release → transcribe →
/// ask the active provider → stream the answer into a bubble → speak it →
/// fly to whatever it pointed at.
@MainActor
final class Companion: ObservableObject {
    let overlay = BuddyOverlayController()
    let pushToTalk = PushToTalkMonitor()
    private let settings = AppSettings.shared

    /// Mirrors the buddy's state for the menu bar panel.
    @Published private(set) var state: BuddyState = .idle
    @Published private(set) var lastQuestion = ""

    private var transcriber: Transcriber?
    private var speechOutput: SpeechOutput?
    private var screenshotTask: Task<[CapturedScreen], Never>?
    private var replyTask: Task<Void, Never>?
    private var history: [ConversationTurn] = []
    private var cancellables: Set<AnyCancellable> = []

    private var model: BuddyOverlayModel { overlay.model }

    func start() {
        pushToTalk.onPress = { [weak self] in self?.beginListening() }
        pushToTalk.onRelease = { [weak self] in self?.finishListening() }
        pushToTalk.start()

        model.$state.assign(to: &$state)
        settings.$alwaysShowBuddy
            .removeDuplicates()
            .sink { [weak self] isOn in self?.overlay.alwaysVisible = isOn }
            .store(in: &cancellables)
    }

    func clearConversation() {
        history.removeAll()
        lastQuestion = ""
    }

    // MARK: - Push-to-talk

    private func beginListening() {
        // Pressing the shortcut again interrupts whatever the buddy was doing.
        replyTask?.cancel()
        speechOutput?.stop()
        transcriber?.cancel()

        guard ScreenCapture.hasPermission else {
            showError("Yewclic needs Screen Recording permission. Open Settings → Permissions.")
            return
        }

        overlay.show(on: ScreenCapture.screenUnderMouse())
        model.state = .listening
        model.bubbleText = ""
        model.pointingLabel = ""

        // Take screenshots right away so they show what the user was looking
        // at when they started talking.
        screenshotTask = Task { (try? await ScreenCapture.captureAllScreens()) ?? [] }

        let newTranscriber = makeTranscriber()
        newTranscriber.onAudioLevel = { [weak self] level in self?.model.audioLevel = level }
        transcriber = newTranscriber
        do {
            try newTranscriber.start()
        } catch {
            transcriber = nil
            showError(error.localizedDescription)
        }
    }

    private func finishListening() {
        guard let activeTranscriber = transcriber, model.state == .listening else { return }
        transcriber = nil
        model.state = .thinking
        model.audioLevel = 0

        replyTask = Task {
            do {
                let transcript = try await activeTranscriber.finish()
                guard !transcript.isEmpty else {
                    model.state = .idle
                    overlay.hideSoon(after: 0.3)
                    return
                }
                lastQuestion = transcript
                let screenshots = await screenshotTask?.value ?? []
                try await answer(question: transcript, screenshots: screenshots)
            } catch is CancellationError {
                // Interrupted by a new push-to-talk; nothing to show.
            } catch {
                showError(error.localizedDescription)
            }
        }
    }

    // MARK: - Answering

    private func answer(question: String, screenshots: [CapturedScreen]) async throws {
        let providerKind = settings.activeProvider
        let providerSettings = settings.settings(for: providerKind)
        let provider = settings.makeActiveProvider()

        var userText = question
        var screenshotsForModel: [CapturedScreen] = []
        if !screenshots.isEmpty {
            if providerSettings.supportsVision {
                screenshotsForModel = screenshots
            } else {
                // Text-only model: describe each screen with on-device OCR instead.
                let screenDescriptions = screenshots.map { screenshot in
                    """
                    \(screenshot.promptCaption)
                    Text on this screen, one item per line as "(x,y) text" where x,y is the item's centre:
                    \(ScreenTextReader.describeScreen(screenshot))
                    """
                }
                userText = """
                [You can't see images, so here is the text on the user's screens instead.]
                \(screenDescriptions.joined(separator: "\n\n"))

                User: \(question)
                """
            }
        }

        let request = CompanionRequest(
            systemPrompt: SystemPrompt.text,
            history: Array(history.suffix(settings.rememberedTurnPairs * 2)),
            userText: userText,
            screenshots: screenshotsForModel
        )

        var fullReply = ""
        for try await chunk in provider.streamReply(to: request) {
            try Task.checkCancellation()
            fullReply += chunk
            model.bubbleText = PointTags.removeTags(from: fullReply)
        }
        try Task.checkCancellation()

        let spokenText = PointTags.removeTags(from: fullReply)
        guard !spokenText.isEmpty else {
            showError("\(providerKind.displayName) returned an empty reply.")
            return
        }
        history.append(ConversationTurn(role: .user, text: question))
        history.append(ConversationTurn(role: .assistant, text: fullReply))

        model.state = .speaking
        model.bubbleText = spokenText

        // Map each tag to a real spot on the right monitor. No screen number
        // means the cursor's screen, which is always screenshot 1.
        let pointTargets = PointTags.extractTargets(from: fullReply).prefix(3).compactMap { target -> (screenPoint: CGPoint, screenFrame: CGRect, label: String)? in
            let screenIndex = (target.screenNumber ?? 1) - 1
            guard screenshots.indices.contains(screenIndex) else { return nil }
            let screenshot = screenshots[screenIndex]
            return (screenshot.screenPoint(forImagePoint: target.imagePoint), screenshot.screenFrame, target.label)
        }

        let output = makeSpeechOutput()
        speechOutput = output
        async let pointing: Void = overlay.point(at: Array(pointTargets))
        do {
            try await output.speak(spokenText)
        } catch {
            NSLog("Yewclic TTS failed: \(error.localizedDescription)")
        }
        await pointing
        try Task.checkCancellation()

        model.state = .idle
        // Leave the text up long enough to read when speech is off.
        overlay.hideSoon(after: settings.speechMode == .off ? 8 : 2.5)
    }

    private func showError(_ message: String) {
        overlay.show(on: ScreenCapture.screenUnderMouse())
        model.state = .error
        model.bubbleText = message
        overlay.hideSoon(after: 6)
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
            if self?.model.state == .error { self?.model.state = .idle }
        }
    }

    // MARK: - Factories

    private func makeTranscriber() -> Transcriber {
        switch settings.transcriptionMode {
        case .appleOnDevice:
            return AppleSpeechTranscriber()
        case .assemblyAIStreaming:
            return AssemblyAITranscriber(apiKey: Keychain.read(account: SecretAccount.assemblyAI) ?? "")
        case .whisperUpload:
            return WhisperUploadTranscriber(
                baseURL: settings.whisperBaseURL,
                model: settings.whisperModel,
                apiKey: Keychain.read(account: SecretAccount.whisper) ?? ""
            )
        }
    }

    private func makeSpeechOutput() -> SpeechOutput {
        let apiKey = Keychain.read(account: SecretAccount.textToSpeech) ?? ""
        switch settings.speechMode {
        case .system:
            return SystemSpeechOutput(voiceIdentifier: settings.systemVoiceIdentifier)
        case .openAICompatible:
            return RemoteAudioSpeechOutput(service: .openAICompatible, baseURL: settings.remoteSpeechBaseURL,
                                           model: settings.remoteSpeechModel, voice: settings.remoteSpeechVoice, apiKey: apiKey)
        case .elevenLabs:
            return RemoteAudioSpeechOutput(service: .elevenLabs, baseURL: "",
                                           model: settings.remoteSpeechModel, voice: settings.remoteSpeechVoice, apiKey: apiKey)
        case .off:
            return SilentSpeechOutput()
        }
    }
}

/// Adapted from Clicky's companion prompt (MIT), which is well tuned for
/// spoken answers and pointing.
enum SystemPrompt {
    static let text = """
    you're yewclic, a friendly companion that lives next to the user's mouse cursor on their mac. the user just spoke to you with push-to-talk and you can see their screen(s). your reply is spoken aloud, so write the way you'd actually talk. this is an ongoing conversation, so remember what they said before.

    rules:
    - default to one or two sentences. be direct and dense. but if they ask you to explain more or go deeper, go all out with a thorough explanation.
    - all lowercase, casual, warm. no emojis.
    - write for the ear, not the eye. short sentences. no lists, bullet points, markdown, or formatting.
    - don't use abbreviations or symbols that sound weird read aloud. say "for example" not "e.g.", spell out small numbers.
    - if the question relates to what's on screen, reference specific things you see. if the screen isn't relevant, just answer the question.
    - you can help with anything: coding, writing, general knowledge, brainstorming.
    - never say "simply" or "just".
    - don't read code out word for word. describe what it does or what needs to change.
    - don't end with yes/no questions like "want me to explain more?". when it fits, end by planting a seed: a bigger idea, a deeper concept, or a next-level technique worth coming back for. it's fine to end with nothing extra.
    - if you get several screen images, the one labelled "primary focus" is where the cursor is. prioritise it but mention others if relevant.

    pointing:
    you have a small glowing triangle cursor that can fly to things on screen and point at them. use it whenever it genuinely helps: they're asking how to do something, looking for a menu, trying to find a button, or finding their way around an app. lean towards pointing, because it makes help concrete. don't point for general knowledge questions or at things they're obviously already looking at.

    to point, put a tag at the very end of your reply, after your spoken words. each image is labelled with its pixel size; use that as the coordinate space, with 0,0 at the top-left, x going right and y going down.

    format: [POINT:x,y:label] where x,y are whole-number pixel coordinates at the centre of the element and label is a short one to three word name like "search bar" or "save button". if the element is on a different screen from the cursor, add :screenN using the screen number from the image label, for example [POINT:400,300:terminal:screen2]. without it the cursor will point at the wrong place. for a step-by-step answer you may use up to three tags in the order to click them.

    if pointing wouldn't help, end with [POINT:none].

    if you're given screen text with coordinates instead of images, use those coordinates the same way.

    examples:
    - how to color grade in final cut: "you'll want the color inspector, it's up in the top right of the toolbar. click that and you'll get all the color wheels and curves. [POINT:1100,42:color inspector]"
    - what is html: "html stands for hypertext markup language, it's basically the skeleton of every web page. the css you've got open is what makes that skeleton look good. [POINT:none]"
    - element on the other monitor: "that's over on your other screen, see the terminal window? [POINT:400,300:terminal:screen2]"
    """
}
