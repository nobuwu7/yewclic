import Testing
@testable import Yewclic

@MainActor
struct OnboardingFlowTests {
    @Test func walksForwardThroughEveryStepInOrder() {
        let flow = OnboardingFlow()
        var visited = [flow.step]
        while !flow.isLastStep {
            flow.goForward()
            visited.append(flow.step)
        }
        #expect(visited == [.welcome, .brain, .permissions, .voice, .tryIt])
        #expect(flow.stepNumber == flow.totalSteps)
    }

    @Test func cannotGoPastEitherEnd() {
        let flow = OnboardingFlow()
        flow.goBack()
        #expect(flow.step == .welcome)
        #expect(!flow.canGoBack)

        let finished = OnboardingFlow(startingAt: .tryIt)
        finished.goForward()
        #expect(finished.step == .tryIt)
    }

    @Test func directionFollowsTheMove() {
        let flow = OnboardingFlow(startingAt: .permissions)
        flow.goBack()
        #expect(!flow.isMovingForward, "Back should slide the other way")
        flow.move(to: .tryIt)
        #expect(flow.isMovingForward)
    }

    @Test func reportsStepChangesSoProgressSurvivesARelaunch() {
        let flow = OnboardingFlow()
        var saved: [OnboardingStep] = []
        flow.onStepChange = { saved.append($0) }
        flow.goForward()
        flow.goForward()
        flow.move(to: .permissions) // no-op: already there
        #expect(saved == [.brain, .permissions])
    }
}

struct BrainReadinessTests {
    private func settings(model: String) -> ProviderSettings {
        ProviderSettings(baseURL: "", model: model, supportsVision: true, cliPath: "")
    }

    @Test func apiProvidersNeedAKeyFirst() {
        #expect(BrainReadiness.evaluate(kind: .anthropic, settings: settings(model: "claude-sonnet-5-5"),
                                        hasAPIKey: false, claudeCodeFound: false, localServerReachable: nil) == .needsAPIKey)
        #expect(BrainReadiness.evaluate(kind: .anthropic, settings: settings(model: "claude-sonnet-5-5"),
                                        hasAPIKey: true, claudeCodeFound: false, localServerReachable: nil) == .ready)
    }

    @Test func emptyModelIsNotReady() {
        #expect(BrainReadiness.evaluate(kind: .openai, settings: settings(model: "  "),
                                        hasAPIKey: true, claudeCodeFound: false, localServerReachable: nil) == .needsModel)
    }

    @Test func claudeCodeOnlyNeedsTheCLI() {
        #expect(BrainReadiness.evaluate(kind: .claudeCode, settings: settings(model: ""),
                                        hasAPIKey: false, claudeCodeFound: false, localServerReachable: nil) == .needsClaudeCode)
        #expect(BrainReadiness.evaluate(kind: .claudeCode, settings: settings(model: ""),
                                        hasAPIKey: false, claudeCodeFound: true, localServerReachable: nil) == .ready)
    }

    @Test func localProvidersDependOnTheServer() {
        #expect(BrainReadiness.evaluate(kind: .ollama, settings: settings(model: "qwen2.5vl"),
                                        hasAPIKey: false, claudeCodeFound: false, localServerReachable: nil) == .unknown)
        #expect(BrainReadiness.evaluate(kind: .ollama, settings: settings(model: "qwen2.5vl"),
                                        hasAPIKey: false, claudeCodeFound: false, localServerReachable: false) == .localServerNotRunning)
        #expect(BrainReadiness.evaluate(kind: .lmStudio, settings: settings(model: "some-model"),
                                        hasAPIKey: false, claudeCodeFound: false, localServerReachable: true) == .ready)
    }

    @Test(arguments: ProviderKind.allCases)
    func everyProviderBelongsToExactlyOnePath(kind: ProviderKind) {
        let owningPaths = BrainPath.allCases.filter { $0.providers.contains(kind) }
        #expect(owningPaths.count == 1, "\(kind) should appear on exactly one card")
        #expect(BrainPath.path(for: kind) == owningPaths.first)
    }
}

struct PermissionTests {
    @Test func speechRecognitionOnlyNeededForAppleSpeech() {
        #expect(AppPermission.required(for: .appleOnDevice).contains(.speechRecognition))
        #expect(!AppPermission.required(for: .assemblyAIStreaming).contains(.speechRecognition))
        #expect(!AppPermission.required(for: .whisperUpload).contains(.speechRecognition))
    }

    @Test(arguments: AppPermission.allCases)
    func everyPermissionHasASettingsLinkAndReason(permission: AppPermission) {
        #expect(permission.settingsURL != nil)
        #expect(!permission.reason.isEmpty)
    }
}
