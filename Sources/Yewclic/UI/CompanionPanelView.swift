import SwiftUI

/// The dark panel that drops down from the menu bar icon, modelled on
/// Clicky's companion panel: status, quick brain switcher, and shortcuts.
struct CompanionPanelView: View {
    @ObservedObject var companion: Companion
    @ObservedObject var settings: AppSettings
    var onOpenSettings: () -> Void
    var onNewConversation: () -> Void
    var onQuit: () -> Void

    @State private var fetchedModels: [String] = []
    @State private var permissionsMissing: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if !permissionsMissing.isEmpty {
                Button(action: onOpenSettings) {
                    Label("Needs \(permissionsMissing.joined(separator: ", ")). Click to fix.", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .pointerOnHover()
            }

            shortcutCard

            VStack(alignment: .leading, spacing: 8) {
                sectionLabel("Brain")
                Picker("", selection: $settings.activeProvider) {
                    ForEach(ProviderKind.allCases) { Text($0.displayName).tag($0) }
                }
                .labelsHidden()

                HStack(spacing: 6) {
                    Text(settings.settings(for: settings.activeProvider).model.isEmpty ? "no model set" : settings.settings(for: settings.activeProvider).model)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Menu("Change") {
                        if fetchedModels.isEmpty {
                            Text("Loading models…")
                        }
                        ForEach(fetchedModels, id: \.self) { modelID in
                            Button(modelID) { settings.updateSettings(for: settings.activeProvider) { $0.model = modelID } }
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .font(.system(size: 12))
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                sectionLabel("Voice")
                Picker("", selection: $settings.speechMode) {
                    ForEach(SpeechMode.allCases) { Text($0.displayName).tag($0) }
                }
                .labelsHidden()
                Toggle("Always show buddy by my cursor", isOn: $settings.alwaysShowBuddy)
                    .font(.system(size: 12))
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }

            Divider().opacity(0.4)

            HStack {
                panelButton("New chat", systemImage: "arrow.counterclockwise", action: onNewConversation)
                panelButton("Settings", systemImage: "gearshape", action: onOpenSettings)
                Spacer()
                panelButton("Quit", systemImage: "power", action: onQuit)
            }
        }
        .padding(16)
        .frame(width: 320)
        .onAppear(perform: refresh)
        .onChange(of: settings.activeProvider) { refresh() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
                .shadow(color: statusColor, radius: 4)
            Text("yewclic").font(.system(size: 15, weight: .semibold, design: .rounded))
            Spacer()
            Text(statusText).font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }

    private var shortcutCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                keyCap("⌃ control")
                Text("+").foregroundStyle(.secondary)
                keyCap("⌥ option")
            }
            Text(companion.lastQuestion.isEmpty
                 ? "Hold, ask about anything on your screen, let go."
                 : "Last asked: \"\(companion.lastQuestion)\"")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.06)))
    }

    private var statusColor: Color {
        switch companion.state {
        case .idle: return BuddyStyle.glow
        case .listening: return .red
        case .thinking: return .yellow
        case .speaking: return .blue
        case .error: return .orange
        }
    }

    private var statusText: String {
        switch companion.state {
        case .idle: return "ready"
        case .listening: return "listening…"
        case .thinking: return "thinking…"
        case .speaking: return "talking"
        case .error: return "something went wrong"
        }
    }

    private func refresh() {
        var missing: [String] = []
        if !ScreenCapture.hasPermission { missing.append("Screen Recording") }
        if !PushToTalkMonitor.hasAccessibilityPermission { missing.append("Accessibility") }
        if !MicrophonePermission.isGranted { missing.append("Microphone") }
        permissionsMissing = missing

        fetchedModels = []
        let provider = settings.makeActiveProvider()
        Task {
            if let models = try? await provider.listModels() { fetchedModels = models }
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .tracking(0.6)
    }

    private func keyCap(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.12)))
    }

    private func panelButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage).font(.system(size: 12))
        }
        .buttonStyle(.borderless)
        .pointerOnHover()
    }
}

private extension View {
    /// Clicky's rule: every clickable thing shows a pointing-hand cursor.
    func pointerOnHover() -> some View {
        onHover { isHovering in
            if isHovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
}
