import AppKit
import ApplicationServices

/// Watches for the push-to-talk chord (hold Control + Option) anywhere in the
/// system. Global key monitoring needs the Accessibility permission.
@MainActor
final class PushToTalkMonitor {
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var isChordHeld = false

    static var hasAccessibilityPermission: Bool { AXIsProcessTrusted() }

    static func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func start() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            MainActor.assumeIsolated { self?.handleFlagsChanged(event.modifierFlags) }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event.modifierFlags)
            return event
        }
    }

    func stop() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
    }

    private func handleFlagsChanged(_ modifierFlags: NSEvent.ModifierFlags) {
        let relevantFlags = modifierFlags.intersection([.control, .option, .command, .shift])
        let isChordDown = relevantFlags == [.control, .option]

        if isChordDown && !isChordHeld {
            isChordHeld = true
            onPress?()
        } else if !isChordDown && isChordHeld {
            isChordHeld = false
            onRelease?()
        }
    }
}
