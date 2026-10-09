import AppKit
import SwiftUI

enum BuddyState: Equatable {
    case idle
    case listening
    case thinking
    case speaking
    case error
}

enum BuddyStyle {
    /// Bright yew green, matching the app icon.
    static let glow = Color(red: 0.24, green: 0.86, blue: 0.52)
    static let errorGlow = Color.orange
    /// Resting angle so the triangle reads as a cursor.
    static let restingRotationDegrees = -35.0
    static let pointerPhrases = ["right here!", "this one!", "over here!", "click this!", "here it is!", "found it!"]
}

/// Everything the overlay draws. Positions are in the overlay window's
/// SwiftUI space (top-left origin).
@MainActor
final class BuddyOverlayModel: ObservableObject {
    @Published var state: BuddyState = .idle
    @Published var buddyPosition: CGPoint = .zero
    @Published var rotationDegrees: Double = BuddyStyle.restingRotationDegrees
    @Published var flightScale: CGFloat = 1
    @Published var bubbleText: String = ""
    @Published var audioLevel: Float = 0
    @Published var pointingLabel: String = ""
    @Published var isVisible = false
}

/// A transparent, click-through window over one display that hosts the
/// buddy: it follows the cursor, shows a waveform while listening, spins
/// while thinking, and swoops along a curved path to point at things
/// (flight animation adapted from Clicky, MIT).
@MainActor
final class BuddyOverlayController {
    let model = BuddyOverlayModel()
    /// When true the buddy stays on screen between questions.
    var alwaysVisible = false {
        didSet { alwaysVisible ? show(on: ScreenCapture.screenUnderMouse()) : hideSoon(after: 0.2) }
    }

    private var panel: NSPanel?
    private var followTimer: Timer?
    private var flightTimer: Timer?
    private var flightContinuation: CheckedContinuation<Void, Never>?
    private var hideWorkItem: DispatchWorkItem?
    private var isNavigating = false

    func show(on screen: NSScreen) {
        hideWorkItem?.cancel()
        let overlayPanel = panel ?? makePanel()
        panel = overlayPanel
        let movedScreens = overlayPanel.frame != screen.frame
        if movedScreens {
            overlayPanel.setFrame(screen.frame, display: true)
        }
        overlayPanel.orderFrontRegardless()
        if !model.isVisible || movedScreens {
            model.buddyPosition = followPosition(for: NSEvent.mouseLocation)
        }
        withAnimation(.easeOut(duration: 0.2)) { model.isVisible = true }
        startFollowingMouse()
    }

    /// Fades the buddy out after a short pause, unless something new starts
    /// or the user wants it always visible.
    func hideSoon(after delay: TimeInterval = 1.5) {
        hideWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if self.alwaysVisible {
                withAnimation(.easeOut(duration: 0.3)) { self.model.bubbleText = "" }
                return
            }
            withAnimation(.easeIn(duration: 0.3)) { self.model.isVisible = false }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                if !self.model.isVisible {
                    self.panel?.orderOut(nil)
                    self.followTimer?.invalidate()
                    self.model.bubbleText = ""
                }
            }
        }
        hideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    /// Flies to each target in turn (switching monitors if needed), shows a
    /// little label, then flies back to the cursor.
    func point(at targets: [(screenPoint: CGPoint, screenFrame: CGRect, label: String)]) async {
        guard !targets.isEmpty else { return }
        isNavigating = true
        defer { isNavigating = false }

        for target in targets {
            guard !Task.isCancelled else { break }
            if let targetScreen = ScreenCapture.screen(containing: target.screenFrame), panel?.frame != target.screenFrame {
                show(on: targetScreen)
            }
            guard let panel else { return }
            let localPoint = CGPoint(
                x: target.screenPoint.x - panel.frame.minX,
                y: panel.frame.maxY - target.screenPoint.y
            )
            await fly(to: localPoint)
            model.rotationDegrees = BuddyStyle.restingRotationDegrees
            withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
                model.pointingLabel = target.label.isEmpty ? (BuddyStyle.pointerPhrases.randomElement() ?? "right here!") : target.label
            }
            try? await Task.sleep(for: .seconds(2.6))
            withAnimation(.easeOut(duration: 0.25)) { model.pointingLabel = "" }
        }

        // Fly home to the cursor (which may be on another screen).
        let cursorScreen = ScreenCapture.screenUnderMouse()
        if panel?.frame != cursorScreen.frame {
            show(on: cursorScreen)
        } else {
            await fly(to: followPosition(for: NSEvent.mouseLocation))
        }
        model.rotationDegrees = BuddyStyle.restingRotationDegrees
    }

    /// Quadratic bezier flight with smoothstep easing. The triangle turns to
    /// face where it's going and swells at the top of the arc.
    private func fly(to destination: CGPoint) async {
        finishFlight()
        let start = model.buddyPosition
        let distance = hypot(destination.x - start.x, destination.y - start.y)
        let duration = min(max(distance / 800, 0.6), 1.4)
        let frameInterval = 1.0 / 60.0
        let totalFrames = max(Int(duration / frameInterval), 1)
        let arcHeight = min(distance * 0.2, 80)
        let control = CGPoint(x: (start.x + destination.x) / 2, y: (start.y + destination.y) / 2 - arcHeight)

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            flightContinuation = continuation
            var frame = 0
            flightTimer = Timer.scheduledTimer(withTimeInterval: frameInterval, repeats: true) { [weak self] timer in
                MainActor.assumeIsolated {
                    guard let self else { timer.invalidate(); return }
                    frame += 1
                    if frame > totalFrames {
                        self.model.buddyPosition = destination
                        self.finishFlight()
                        return
                    }
                    let linear = Double(frame) / Double(totalFrames)
                    let t = linear * linear * (3 - 2 * linear)
                    let inverse = 1 - t
                    self.model.buddyPosition = CGPoint(
                        x: inverse * inverse * start.x + 2 * inverse * t * control.x + t * t * destination.x,
                        y: inverse * inverse * start.y + 2 * inverse * t * control.y + t * t * destination.y
                    )
                    let tangentX = 2 * inverse * (control.x - start.x) + 2 * t * (destination.x - control.x)
                    let tangentY = 2 * inverse * (control.y - start.y) + 2 * t * (destination.y - control.y)
                    // +90° because the triangle's tip points up at 0°.
                    self.model.rotationDegrees = atan2(tangentY, tangentX) * 180 / .pi + 90
                    self.model.flightScale = 1 + sin(linear * .pi) * 0.3
                }
            }
        }
    }

    /// Stops any flight in progress and releases whoever is waiting on it.
    private func finishFlight() {
        flightTimer?.invalidate()
        flightTimer = nil
        model.flightScale = 1
        flightContinuation?.resume()
        flightContinuation = nil
    }

    private func startFollowingMouse() {
        followTimer?.invalidate()
        followTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.isNavigating, let panel = self.panel else { return }
                // Hop to whichever monitor the cursor moves to.
                let mouseLocation = NSEvent.mouseLocation
                if !NSMouseInRect(mouseLocation, panel.frame, false) {
                    let newScreen = ScreenCapture.screenUnderMouse()
                    panel.setFrame(newScreen.frame, display: true)
                    self.model.buddyPosition = self.followPosition(for: mouseLocation)
                    return
                }
                let target = self.followPosition(for: mouseLocation)
                let current = self.model.buddyPosition
                // Ease toward the cursor so it feels like it's tagging along.
                self.model.buddyPosition = CGPoint(
                    x: current.x + (target.x - current.x) * 0.3,
                    y: current.y + (target.y - current.y) * 0.3
                )
            }
        }
    }

    private func followPosition(for mouseLocation: CGPoint) -> CGPoint {
        guard let panel else { return .zero }
        return CGPoint(
            x: mouseLocation.x - panel.frame.minX + 20,
            y: panel.frame.maxY - mouseLocation.y + 22
        )
    }

    private func makePanel() -> NSPanel {
        let overlayPanel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        overlayPanel.isOpaque = false
        overlayPanel.backgroundColor = .clear
        overlayPanel.hasShadow = false
        overlayPanel.ignoresMouseEvents = true
        overlayPanel.level = .screenSaver
        overlayPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        overlayPanel.contentView = NSHostingView(rootView: BuddyOverlayView(model: model))
        return overlayPanel
    }
}

// MARK: - Views

struct BuddyOverlayView: View {
    @ObservedObject var model: BuddyOverlayModel

    private var glow: Color { model.state == .error ? BuddyStyle.errorGlow : BuddyStyle.glow }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            if model.isVisible {
                // All three looks stay in the tree and cross-fade, so the buddy
                // never "pops" when its state changes.
                BuddyTriangle()
                    .fill(glow)
                    .frame(width: 16, height: 16)
                    .rotationEffect(.degrees(model.rotationDegrees))
                    .shadow(color: glow, radius: 8 + (model.flightScale - 1) * 20)
                    .scaleEffect(model.flightScale)
                    .opacity(model.state == .listening || model.state == .thinking ? 0 : 1)
                    .position(model.buddyPosition)

                BuddyWaveform(audioLevel: CGFloat(model.audioLevel), color: glow)
                    .opacity(model.state == .listening ? 1 : 0)
                    .position(model.buddyPosition)

                BuddySpinner(color: glow)
                    .opacity(model.state == .thinking ? 1 : 0)
                    .position(model.buddyPosition)

                if !model.pointingLabel.isEmpty {
                    Text(model.pointingLabel)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.black.opacity(0.85)))
                        .overlay(Capsule().strokeBorder(glow.opacity(0.7)))
                        .foregroundStyle(.white)
                        .fixedSize()
                        .transition(.scale(scale: 0.5).combined(with: .opacity))
                        .offset(x: model.buddyPosition.x + 12, y: model.buddyPosition.y + 8)
                }

                if !model.bubbleText.isEmpty && model.pointingLabel.isEmpty {
                    SpeechBubble(text: model.bubbleText, accent: glow)
                        .frame(maxWidth: 320, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .offset(x: model.buddyPosition.x + 16, y: model.buddyPosition.y + 14)
                        .transition(.opacity)
                }
            }
        }
        .animation(.easeInOut(duration: 0.15), value: model.state)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
    }
}

struct BuddyTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let size = min(rect.width, rect.height)
        let height = size * sqrt(3.0) / 2.0
        path.move(to: CGPoint(x: rect.midX, y: rect.midY - height / 1.5))
        path.addLine(to: CGPoint(x: rect.midX - size / 2, y: rect.midY + height / 3))
        path.addLine(to: CGPoint(x: rect.midX + size / 2, y: rect.midY + height / 3))
        path.closeSubpath()
        return path
    }
}

/// Five little bars that bounce with your voice.
struct BuddyWaveform: View {
    var audioLevel: CGFloat
    var color: Color
    private let barProfile: [CGFloat] = [0.4, 0.7, 1.0, 0.7, 0.4]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 36.0)) { context in
            HStack(spacing: 2) {
                ForEach(0..<barProfile.count, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(color)
                        .frame(width: 2, height: barHeight(index: index, date: context.date))
                }
            }
            .shadow(color: color.opacity(0.6), radius: 6)
        }
    }

    private func barHeight(index: Int, date: Date) -> CGFloat {
        let phase = CGFloat(date.timeIntervalSinceReferenceDate * 3.6) + CGFloat(index) * 0.35
        let easedLevel = pow(min(max(audioLevel - 0.008, 0) * 2.85, 1), 0.76)
        let idlePulse = (sin(phase) + 1) / 2 * 1.5
        return 3 + easedLevel * 10 * barProfile[index] + idlePulse
    }
}

struct BuddySpinner: View {
    var color: Color
    @State private var isSpinning = false

    var body: some View {
        Circle()
            .trim(from: 0.15, to: 0.85)
            .stroke(AngularGradient(colors: [color.opacity(0), color], center: .center),
                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            .frame(width: 14, height: 14)
            .rotationEffect(.degrees(isSpinning ? 360 : 0))
            .shadow(color: color.opacity(0.6), radius: 6)
            .onAppear {
                withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false)) { isSpinning = true }
            }
    }
}

struct SpeechBubble: View {
    var text: String
    var accent: Color

    var body: some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(.white)
            .lineLimit(14)
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.black.opacity(0.85)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(accent.opacity(0.35)))
    }
}
