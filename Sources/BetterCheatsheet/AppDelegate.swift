import AppKit
import Combine
import SwiftUI

/// A panel that can become key (so its NSTextView can accept typing when a
/// tab is set editable-in-overlay) without activating the app or stealing
/// focus the way a normal window would - the classic floating-palette trick.
final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let appState = AppState()
    private let settings = SettingsStore()
    private var mainWindow: NSWindow?
    private var overlayPanel: OverlayPanel?
    private var statusItem: NSStatusItem?
    private var hotKeyManager: HotKeyManager?
    private var settingsCancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpMainWindow()
        setUpOverlayPanel()
        setUpStatusItem()
        registerHotKey(keyCode: settings.hotKey.keyCode, modifiers: settings.hotKey.modifiers)
        observeSettings()

        showEditor()
    }

    private func registerHotKey(keyCode: UInt32, modifiers: UInt32) {
        hotKeyManager = HotKeyManager(keyCode: keyCode, modifiers: modifiers) { [weak self] in
            self?.toggleOverlay()
        }
    }

    private func observeSettings() {
        settings.$hotKey
            .dropFirst()
            .sink { [weak self] hotKey in
                self?.registerHotKey(keyCode: hotKey.keyCode, modifiers: hotKey.modifiers)
            }
            .store(in: &settingsCancellables)

        settings.$theme
            .sink { [weak self] theme in
                self?.applyTheme(theme)
            }
            .store(in: &settingsCancellables)
    }

    private func applyTheme(_ theme: AppTheme) {
        switch theme {
        case .light:
            NSApp.appearance = NSAppearance(named: .aqua)
            setWindowsTranslucent(false)
        case .dark:
            NSApp.appearance = NSAppearance(named: .darkAqua)
            setWindowsTranslucent(false)
        case .frostedGlass:
            NSApp.appearance = nil
            setWindowsTranslucent(true)
        }
    }

    private func setWindowsTranslucent(_ translucent: Bool) {
        for window in [mainWindow, overlayPanel] {
            window?.isOpaque = !translucent
            window?.backgroundColor = translucent ? .clear : .windowBackgroundColor
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func setUpMainWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 360),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Better Cheatsheet"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: EditorView(appState: appState, settings: settings))
        window.center()
        mainWindow = window
    }

    private func setUpOverlayPanel() {
        let panel = OverlayPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 360),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: CheatsheetView(appState: appState, settings: settings))
        overlayPanel = panel
    }

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(
            systemSymbolName: "list.bullet.rectangle",
            accessibilityDescription: "Better Cheatsheet"
        )

        let showItem = NSMenuItem(title: "Show Cheatsheet", action: #selector(toggleOverlay), keyEquivalent: "k")
        showItem.target = self
        let editItem = NSMenuItem(title: "Edit Notes", action: #selector(showEditor), keyEquivalent: "")
        editItem.target = self
        let quitItem = NSMenuItem(title: "Quit Better Cheatsheet", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.target = NSApp

        let menu = NSMenu()
        menu.addItem(showItem)
        menu.addItem(editItem)
        menu.addItem(.separator())
        menu.addItem(quitItem)
        item.menu = menu
        statusItem = item
    }

    @objc private func toggleOverlay() {
        guard let panel = overlayPanel else { return }
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            positionOverlayNearCursor(panel)
            panel.makeKeyAndOrderFront(nil)
        }
    }

    @objc private func showEditor() {
        NSApp.activate(ignoringOtherApps: true)
        mainWindow?.makeKeyAndOrderFront(nil)
    }

    private func positionOverlayNearCursor(_ panel: NSPanel) {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouseLocation) } ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }
        let size = panel.frame.size
        let origin = NSPoint(
            x: frame.midX - size.width / 2,
            y: frame.midY - size.height / 2
        )
        panel.setFrameOrigin(origin)
    }
}
