import AppKit
import ApplicationServices

/// Watches for the push-to-talk chord (hold Control + Option) anywhere in the
/// system.
///
/// Uses a listen-only CGEvent tap (Clicky's approach), which catches
/// modifier-only shortcuts more reliably than AppKit's global monitor while
/// the app is in the background. Falls back to NSEvent monitors if the tap
/// can't be created (usually because permission hasn't been granted yet).
@MainActor
final class PushToTalkMonitor {
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?

    private var eventTap: CFMachPort?
    private var eventTapRunLoopSource: CFRunLoopSource?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var isChordHeld = false

    static var hasAccessibilityPermission: Bool { AXIsProcessTrusted() }

    static func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    var isUsingEventTap: Bool { eventTap != nil }

    func start() {
        stop()
        if !startEventTap() {
            startNSEventMonitors()
        }
    }

    /// Call after permissions change so we can upgrade from the fallback to
    /// the event tap without restarting the app.
    func restartIfNeeded() {
        if eventTap == nil { start() }
    }

    func stop() {
        if let eventTapRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), eventTapRunLoopSource, .commonModes)
        }
        if let eventTap { CFMachPortInvalidate(eventTap) }
        eventTap = nil
        eventTapRunLoopSource = nil
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
    }

    private func startEventTap() -> Bool {
        let eventMask = CGEventMask(1) << CGEventType.flagsChanged.rawValue

        let callback: CGEventTapCallBack = { _, eventType, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<PushToTalkMonitor>.fromOpaque(userInfo).takeUnretainedValue()
            // The tap's run loop source is on the main run loop, so this is the main thread.
            MainActor.assumeIsolated {
                if eventType == .tapDisabledByTimeout || eventType == .tapDisabledByUserInput {
                    if let tap = monitor.eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
                } else {
                    monitor.handleModifierFlags(NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue)))
                }
            }
            return Unmanaged.passUnretained(event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ), let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            return false
        }

        eventTap = tap
        eventTapRunLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private func startNSEventMonitors() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            MainActor.assumeIsolated { self?.handleModifierFlags(event.modifierFlags) }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleModifierFlags(event.modifierFlags)
            return event
        }
    }

    private func handleModifierFlags(_ modifierFlags: NSEvent.ModifierFlags) {
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
