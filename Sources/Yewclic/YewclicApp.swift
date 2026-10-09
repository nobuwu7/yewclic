import AppKit
import Combine
import SwiftUI

@main
enum YewclicMain {
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        // Shows in the Dock and the menu bar. Clicking the Dock icon opens Settings.
        application.setActivationPolicy(.regular)
        application.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let companion = Companion()
    private let settings = AppSettings.shared
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "cursorarrow.rays", accessibilityDescription: "Yewclic")
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item

        installMainMenu()
        companion.start()

        let needsSetup = !ScreenCapture.hasPermission || !PushToTalkMonitor.hasAccessibilityPermission || !MicrophonePermission.isGranted
        if needsSetup { openSettings() }
    }

    // Clicking the Dock icon (with no windows open) brings up Settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows { openSettings() }
        return true
    }

    // Closing Settings shouldn't quit the app; the buddy keeps running.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    // Right-clicking the Dock icon shows the same provider switcher as the menu bar.
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let dockMenu = NSMenu()
        menuNeedsUpdate(dockMenu)
        // The Dock adds its own Quit item.
        if let quitItem = dockMenu.items.last, quitItem.action == #selector(quit) {
            dockMenu.removeItem(quitItem)
        }
        return dockMenu
    }

    /// A regular (Dock) app needs a main menu so ⌘, ⌘W and ⌘Q work.
    private func installMainMenu() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        addItem(to: appMenu, title: "Settings…", action: #selector(openSettings), key: ",")
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Hide Yewclic", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"))
        addItem(to: appMenu, title: "Quit Yewclic", action: #selector(quit), key: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(NSMenuItem(title: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        windowMenu.addItem(NSMenuItem(title: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"))
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)
        NSApp.mainMenu = mainMenu
    }

    // Rebuild the menu each time it opens so the provider checkmark is current.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let header = NSMenuItem(title: "Hold ⌃⌥ (Control + Option) and talk", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        let providerMenu = NSMenu()
        for kind in ProviderKind.allCases {
            let providerItem = NSMenuItem(title: kind.displayName, action: #selector(selectProvider(_:)), keyEquivalent: "")
            providerItem.target = self
            providerItem.representedObject = kind.rawValue
            providerItem.state = kind == settings.activeProvider ? .on : .off
            providerMenu.addItem(providerItem)
        }
        let providerParent = NSMenuItem(title: "Brain: \(settings.activeProvider.displayName)", action: nil, keyEquivalent: "")
        providerParent.submenu = providerMenu
        menu.addItem(providerParent)

        let modelInfo = NSMenuItem(title: "Model: \(settings.settings(for: settings.activeProvider).model)", action: nil, keyEquivalent: "")
        modelInfo.isEnabled = false
        menu.addItem(modelInfo)
        menu.addItem(.separator())

        addItem(to: menu, title: "New conversation", action: #selector(clearConversation), key: "n")
        addItem(to: menu, title: "Settings…", action: #selector(openSettings), key: ",")
        menu.addItem(.separator())
        addItem(to: menu, title: "Quit Yewclic", action: #selector(quit), key: "q")
    }

    private func addItem(to menu: NSMenu, title: String, action: Selector, key: String) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
    }

    @objc private func selectProvider(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String, let kind = ProviderKind(rawValue: rawValue) else { return }
        settings.activeProvider = kind
    }

    @objc private func clearConversation() {
        companion.clearConversation()
    }

    @objc func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 560, height: 640),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Yewclic Settings"
            window.contentViewController = NSHostingController(rootView: SettingsView(settings: settings))
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
