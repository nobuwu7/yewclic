import AppKit

/// The whole push-to-talk loop:
/// hold ⌃⌥ → listen + screenshot → release → transcribe → ask the active
/// provider → stream the answer into a bubble → speak it → point at things.
@MainActor
final class Companion {
    let overlay = BuddyOverlayController()
    private let settings = AppSettings.shared
    private let pushToTalk = PushToTalkMonitor()

    private var transcriber: Transcriber?
    private var speechOutput: SpeechOutput?
    private var screenshotTask: Task<CapturedScreen?, Never>?
    private var replyTask: Task<Void, Never>?
    private var history: [ConversationTurn] = []

    private var model: BuddyOverlayModel { overlay.model }

    func start() {
        pushToTalk.onPress = { [weak self] in self?.beginListening() }
        pushToTalk.onRelease = { [weak self] in self?.finishListening() }
        pushToTalk.start()
    }

    func clearConversation() {
        history.removeAll()
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

        // Take the screenshot right away so it shows what the user was looking
        // at when they started talking.
        screenshotTask = Task { try? await ScreenCapture.captureScreenUnderMouse() }

        let newTranscriber = makeTranscriber()
        newTranscriber.onAudioLevel = { [weak self] level in self?.model.audioLevel = level }
        transcriber = newTranscriber
        do {
            try newTranscriber.start()
        } catch {
            showError("Microphone error: \(error.localizedDescription)")
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
                let screenshot = await screenshotTask?.value
                try await answer(question: transcript, screenshot: screenshot)
            } catch is CancellationError {
                // Interrupted by a new push-to-talk; nothing to show.
            } catch {
                showError(error.localizedDescription)
            }
        }
    }

    // MARK: - Answering

    private func answer(question: String, screenshot: CapturedScreen?) async throws {
        let providerKind = settings.activeProvider
        let providerSettings = settings.settings(for: providerKind)
        let provider = settings.makeActiveProvider()

        var userText = question
        var screenshotForModel: CapturedScreen?
        if let screenshot {
            if providerSettings.supportsVision {
                screenshotForModel = screenshot
                userText = "[Screenshot attached: \(screenshot.pixelWidth)x\(screenshot.pixelHeight) pixels]\n\n\(question)"
            } else {
                // Text-only model: describe the screen with on-device OCR instead.
                let screenText = ScreenTextReader.describeScreen(screenshot)
                userText = """
                [You can't see images. Here is the text on the user's screen \
                (\(screenshot.pixelWidth)x\(screenshot.pixelHeight) pixels), one item per line \
                as "(x,y) text" where x,y is the item's centre:]
                \(screenText)

                User: \(question)
                """
            }
        }

        let request = CompanionRequest(
            systemPrompt: SystemPrompt.text,
            history: Array(history.suffix(settings.rememberedTurnPairs * 2)),
            userText: userText,
            screenshot: screenshotForModel
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

        let pointTargets: [(screenPoint: CGPoint, label: String)] = screenshot.map { screenshot in
            PointTags.extractTargets(from: fullReply).map {
                (screenshot.screenPoint(forImagePoint: $0.imagePoint), $0.label)
            }
        } ?? []

        let output = makeSpeechOutput()
        speechOutput = output
        async let pointing: Void = overlay.point(at: pointTargets)
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
    }

    // MARK: - Factories

    private func makeTranscriber() -> Transcriber {
        switch settings.transcriptionMode {
        case .appleOnDevice:
            return AppleSpeechTranscriber()
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

enum SystemPrompt {
    static let text = """
    You are Yewclic, a friendly helper that lives next to the user's mouse cursor on their Mac. \
    The user holds a shortcut and talks to you; you see a screenshot of the screen they're on \
    (or, for text-only models, a list of the text on it). Your reply is read aloud.

    How to reply:
    - Talk like a helpful friend sitting beside them. Short, plain sentences. Usually 1-4 sentences.
    - No markdown, bullet points, code blocks, or emoji. It will be spoken.
    - If they ask how to do something in an app, give the next one or two steps, not a whole manual.
    - If the screen doesn't show enough to answer, say what you'd need to see.

    Pointing:
    - When it helps to show them where something is, add a tag like [POINT:x,y:short label] right \
    after the sentence that mentions it. x,y are pixel coordinates in the screenshot, measured from \
    the top-left corner, at the centre of the thing.
    - Only point at things that are actually visible. Use at most 3 tags. Never read the tags aloud \
    or mention coordinates in your words.
    """
}
