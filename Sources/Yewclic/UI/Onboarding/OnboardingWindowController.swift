import AppKit
import SwiftUI

/// Owns the welcome-guide window: shows it, remembers progress across
/// relaunches, and marks the guide done when the user finishes or skips.
@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    private let settings: AppSettings
    private let companion: Companion
    private var window: NSWindow?
    private var flow: OnboardingFlow?
    /// Called after the guide closes, e.g. to open Settings when skipped.
    var onClose: ((_ skipped: Bool) -> Void)?

    init(settings: AppSettings, companion: Companion) {
        self.settings = settings
        self.companion = companion
    }

    var isShowing: Bool { window?.isVisible == true }

    /// Opens the guide. Resumes at the saved step unless `fromStart` is set.
    func show(fromStart: Bool = false) {
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let startStep = fromStart ? .welcome : (OnboardingStep(rawValue: settings.onboardingResumeStep) ?? .welcome)
        let newFlow = OnboardingFlow(startingAt: startStep)
        newFlow.onStepChange = { [weak self] step in self?.settings.onboardingResumeStep = step.rawValue }
        flow = newFlow

        let newWindow = Self.makeWindow(rootView: OnboardingView(
            flow: newFlow,
            settings: settings,
            companion: companion,
            onFinish: { [weak self] skipped in self?.finish(skipped: skipped) }
        ))
        newWindow.delegate = self
        window = newWindow

        NSApp.activate(ignoringOtherApps: true)
        newWindow.center()
        newWindow.makeKeyAndOrderFront(nil)
        NSLog("Yewclic welcome guide shown at step %@, frame %@", startStep.rawValue, NSStringFromRect(newWindow.frame))
    }

    private func finish(skipped: Bool) {
        settings.hasCompletedOnboarding = true
        settings.onboardingResumeStep = ""
        window?.close()
        onClose?(skipped)
    }

    // Closing with the red button counts as "later": the guide reopens next
    // launch at the same step.
    func windowWillClose(_ notification: Notification) {
        window = nil
        flow = nil
    }

    static func makeWindow<Content: View>(rootView: Content) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: OnboardingView.windowSize),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to yewclic"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        // Fixed size: stop the hosting controller resizing the window, and let
        // the content run under the transparent title bar (the view leaves
        // room for it), so the window is exactly the designed size.
        let hostingController = NSHostingController(rootView: rootView.ignoresSafeArea())
        hostingController.sizingOptions = []
        window.contentViewController = hostingController
        window.setContentSize(OnboardingView.windowSize)
        return window
    }
}

/// `Yewclic --snapshot-onboarding <folder>` renders every guide step to a PNG
/// and quits. Used to check the screens without clicking through them.
@MainActor
enum OnboardingSnapshotter {
    static let argument = "--snapshot-onboarding"

    static var requestedOutputFolder: URL? {
        let arguments = CommandLine.arguments
        guard let flagIndex = arguments.firstIndex(of: argument), flagIndex + 1 < arguments.count else { return nil }
        return URL(fileURLWithPath: arguments[flagIndex + 1], isDirectory: true)
    }

    static func renderAllSteps(to folder: URL, settings: AppSettings, companion: Companion) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for appearanceName in [NSAppearance.Name.aqua, .darkAqua] {
            for step in OnboardingStep.allCases {
                let flow = OnboardingFlow(startingAt: step)
                let view = OnboardingView(flow: flow, settings: settings, companion: companion, onFinish: { _ in })
                let window = OnboardingWindowController.makeWindow(rootView: view)
                window.appearance = NSAppearance(named: appearanceName)
                // Off-screen so nothing flashes on the user's display.
                window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
                window.orderFrontRegardless()
                // Let SwiftUI lay out and run onAppear before capturing.
                RunLoop.main.run(until: Date().addingTimeInterval(0.6))

                guard let contentView = window.contentView,
                      let bitmap = contentView.bitmapImageRepForCachingDisplay(in: contentView.bounds) else { continue }
                contentView.cacheDisplay(in: contentView.bounds, to: bitmap)
                let suffix = appearanceName == .darkAqua ? "dark" : "light"
                let fileURL = folder.appendingPathComponent("\(step.position + 1)-\(step.rawValue)-\(suffix).png")
                try? bitmap.representation(using: .png, properties: [:])?.write(to: fileURL)
                window.orderOut(nil)
                print("Wrote \(fileURL.path)")
            }
        }
    }
}
