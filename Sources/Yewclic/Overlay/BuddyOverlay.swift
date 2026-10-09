import AppKit
import SwiftUI

enum BuddyState: Equatable {
    case idle
    case listening
    case thinking
    case speaking
    case error
}

/// Everything the overlay draws. Positions are in the overlay window's
/// SwiftUI space (top-left origin).
@MainActor
final class BuddyOverlayModel: ObservableObject {
    @Published var state: BuddyState = .idle
    @Published var buddyPosition: CGPoint = .zero
    @Published var bubbleText: String = ""
    @Published var audioLevel: Float = 0
    @Published var pointingLabel: String = ""
    @Published var isPointing = false
    @Published var isVisible = false
}

/// A transparent, click-through window over the current display that hosts
/// the little buddy that follows the cursor and flies to things it points at.
@MainActor
final class BuddyOverlayController {
    let model = BuddyOverlayModel()
    private var panel: NSPanel?
    private var followTimer: Timer?
    private var hideWorkItem: DispatchWorkItem?

    func show(on screen: NSScreen) {
        hideWorkItem?.cancel()
        let overlayPanel = panel ?? makePanel()
        panel = overlayPanel
        if overlayPanel.frame != screen.frame {
            overlayPanel.setFrame(screen.frame, display: true)
        }
        overlayPanel.orderFrontRegardless()
        if !model.isVisible {
            model.buddyPosition = followPosition(for: NSEvent.mouseLocation)
        }
        withAnimation(.easeOut(duration: 0.2)) { model.isVisible = true }
        startFollowingMouse()
    }

    /// Fades the buddy out after a short pause, unless something new starts.
    func hideSoon(after delay: TimeInterval = 1.5) {
        hideWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
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

    /// Flies the buddy to each target in turn, then returns to the cursor.
    func point(at targets: [(screenPoint: CGPoint, label: String)]) async {
        guard let panel, !targets.isEmpty else { return }
        model.isPointing = true
        for target in targets {
            let localPoint = CGPoint(
                x: target.screenPoint.x - panel.frame.minX,
                y: panel.frame.maxY - target.screenPoint.y
            )
            withAnimation(.spring(response: 0.6, dampingFraction: 0.75)) {
                model.buddyPosition = localPoint
                model.pointingLabel = target.label
            }
            try? await Task.sleep(for: .seconds(2.8))
        }
        withAnimation(.easeOut(duration: 0.2)) { model.pointingLabel = "" }
        model.isPointing = false
    }

    private func startFollowingMouse() {
        followTimer?.invalidate()
        followTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.model.isPointing else { return }
                let target = self.followPosition(for: NSEvent.mouseLocation)
                let current = self.model.buddyPosition
                // Ease toward the cursor so it feels like it's tagging along.
                self.model.buddyPosition = CGPoint(
                    x: current.x + (target.x - current.x) * 0.25,
                    y: current.y + (target.y - current.y) * 0.25
                )
            }
        }
    }

    private func followPosition(for mouseLocation: CGPoint) -> CGPoint {
        guard let panel else { return .zero }
        return CGPoint(
            x: mouseLocation.x - panel.frame.minX + 22,
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

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            if model.isVisible {
                BuddyCursor(state: model.state, audioLevel: model.audioLevel)
                    .position(model.buddyPosition)

                if !model.pointingLabel.isEmpty {
                    Text(model.pointingLabel)
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.accentColor))
                        .foregroundStyle(.white)
                        .fixedSize()
                        .position(x: model.buddyPosition.x, y: model.buddyPosition.y - 26)
                }

                if !model.bubbleText.isEmpty {
                    SpeechBubble(text: model.bubbleText, isError: model.state == .error)
                        .frame(maxWidth: 320, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .offset(x: model.buddyPosition.x + 18, y: model.buddyPosition.y + 14)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
    }
}

struct BuddyCursor: View {
    var state: BuddyState
    var audioLevel: Float
    @State private var isPulsing = false

    private var tint: Color {
        switch state {
        case .listening: return .red
        case .error: return .orange
        default: return Color(red: 0.2, green: 0.55, blue: 1.0)
        }
    }

    var body: some View {
        ZStack {
            if state == .listening {
                Circle()
                    .fill(tint.opacity(0.25))
                    .frame(width: 22 + CGFloat(audioLevel) * 26, height: 22 + CGFloat(audioLevel) * 26)
                    .animation(.easeOut(duration: 0.08), value: audioLevel)
            }
            if state == .thinking {
                Circle()
                    .trim(from: 0, to: 0.7)
                    .stroke(tint, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .frame(width: 26, height: 26)
                    .rotationEffect(.degrees(isPulsing ? 360 : 0))
                    .animation(.linear(duration: 0.9).repeatForever(autoreverses: false), value: isPulsing)
            }
            Image(systemName: "cursorarrow")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(tint)
                .shadow(color: tint.opacity(0.6), radius: 6)
                .scaleEffect(state == .speaking && isPulsing ? 1.12 : 1.0)
                .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: isPulsing)
        }
        .onAppear { isPulsing = true }
    }
}

struct SpeechBubble: View {
    var text: String
    var isError: Bool

    var body: some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(.white)
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isError ? Color.orange.opacity(0.9) : Color.black.opacity(0.82))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12))
            )
    }
}
