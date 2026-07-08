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

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let appState = AppState()
    private let settings = SettingsStore()
    private var mainWindow: NSWindow?
    private var overlayPanel: OverlayPanel?
    private var statusItem: NSStatusItem?
    private var showCheatsheetMenuItem: NSMenuItem?
    private var hotKeyManager: HotKeyManager?
    private var sideSensitiveMonitor: SideSensitiveHotKeyMonitor?
    private var settingsCancellables = Set<AnyCancellable>()

    private static let overlayFrameAutosaveName = "BetterCheatsheetOverlayFrame"
    /// Whether the overlay already has a remembered position/size (from this
    /// launch's restore, or from having been shown once already this run) -
    /// only auto-centers near the cursor when this is still false.
    private var overlayHasPlacement = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpMainMenu()
        setUpMainWindow()
        setUpOverlayPanel()
        setUpStatusItem()
        registerHotKey(settings.hotKey)
        observeSettings()

        showEditor()
    }

    /// This app is a bare Swift executable (no Xcode project/NIB), so AppKit
    /// never auto-generates the usual app menu bar - without this, there's no
    /// menu item anywhere bound to Cmd+W (or Cmd+M), so those keys silently
    /// do nothing no matter what's key. `performClose:`/`performMiniaturize:`
    /// need no explicit target: nil routes them through the responder chain
    /// to whichever window is currently key.
    private func setUpMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Better Cheatsheet", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // Same gap as Cmd+W/Cmd+M above, but for Cmd+C/V/X/Z/A: with no Edit
        // menu at all, those keys had no menu item to route through and
        // silently did nothing everywhere - Note tabs (both the main window
        // and the overlay) and the Shortcut/Action table cells alike. Nil
        // targets route through the responder chain to whatever's first
        // responder, same as the Window menu above - works automatically
        // for any NSTextView/NSTextField, no per-view wiring needed.
        // Undo/Redo use the informal "undo:"/"redo:" selectors (not a
        // formally declared Swift method on NSResponder) since that's what
        // NSTextView's own internal NSUndoManager integration responds to;
        // Cut/Copy/Paste/Select All are on the NSText protocol, which
        // NSTextView/NSTextField/NSTextField's field editor all conform to.
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redoItem = editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redoItem.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)

        NSApp.mainMenu = mainMenu
    }

    /// Dispatches to the Carbon-based HotKeyManager (no permission needed,
    /// but can't distinguish left/right modifiers) or the side-sensitive
    /// NSEvent-monitor-based path (needs Accessibility permission) depending
    /// on the user's choice in Settings.
    private func registerHotKey(_ hotKey: HotKeyConfig) {
        hotKeyManager = nil
        sideSensitiveMonitor?.stop()
        sideSensitiveMonitor = nil

        if hotKey.sideSensitive {
            AccessibilityPermission.requestIfNeeded()
            let monitor = SideSensitiveHotKeyMonitor()
            monitor.start(matching: hotKey) { [weak self] in
                self?.toggleOverlay()
            }
            sideSensitiveMonitor = monitor
        } else {
            hotKeyManager = HotKeyManager(keyCode: hotKey.keyCode, modifiers: hotKey.modifiers) { [weak self] in
                self?.toggleOverlay()
            }
        }
    }

    private func observeSettings() {
        // Both effects only need to run on a *subsequent* change - the
        // initial hotKey was already applied directly in
        // applicationDidFinishLaunching (registerHotKey) and setUpStatusItem
        // (updateStatusItemTitle), so one dropFirst()-gated subscription
        // covers both instead of two separate ones each re-doing that check.
        settings.$hotKey
            .dropFirst()
            .sink { [weak self] hotKey in
                self?.registerHotKey(hotKey)
                self?.updateStatusItemTitle(for: hotKey)
            }
            .store(in: &settingsCancellables)

        settings.$theme
            .sink { [weak self] theme in
                self?.applyTheme(theme)
            }
            .store(in: &settingsCancellables)
    }

    /// Keeps the "Show Cheatsheet" item's native, right-aligned/dimmed
    /// shortcut display in sync with Settings - it's purely cosmetic (see
    /// HotKeyFormatter.menuItemKeyEquivalent), the real toggle is
    /// HotKeyManager/SideSensitiveHotKeyMonitor, but showing the wrong
    /// (or a permanently stale) shortcut here would be misleading.
    private func updateStatusItemTitle(for hotKey: HotKeyConfig) {
        if let (key, mask) = HotKeyFormatter.menuItemKeyEquivalent(for: hotKey) {
            showCheatsheetMenuItem?.keyEquivalent = key
            showCheatsheetMenuItem?.keyEquivalentModifierMask = mask
        } else {
            showCheatsheetMenuItem?.keyEquivalent = ""
            showCheatsheetMenuItem?.keyEquivalentModifierMask = []
        }
    }

    /// Frosted Glass only applies to the overlay - the main editor window
    /// always stays opaque regardless of theme, since a live desktop blur
    /// behind the window you're actively typing notes in isn't wanted there.
    /// The overlay panel itself stays non-opaque/clear in every theme (see
    /// setUpOverlayPanel) so its SwiftUI content can clip to rounded corners;
    /// which material fills those corners (blur vs solid color) is decided
    /// entirely by CheatsheetView's own background, not by the window.
    private func applyTheme(_ theme: AppTheme) {
        switch theme {
        case .light:
            NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:
            NSApp.appearance = NSAppearance(named: .darkAqua)
        case .frostedGlass:
            NSApp.appearance = nil
        }
        mainWindow?.isOpaque = true
        mainWindow?.backgroundColor = .windowBackgroundColor
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Notes are saved on a debounced/background write (see
    /// AppState.scheduleSave) rather than synchronously on every keystroke,
    /// so an edit made in the last fraction of a second before quitting
    /// could otherwise be lost along with the debounce window - this makes
    /// sure it lands before the process actually exits.
    func applicationWillTerminate(_ notification: Notification) {
        appState.flushPendingSave()
    }

    /// Without this, clicking the Dock icon (or re-launching) while the main
    /// window is closed just activates the app with nothing visible - AppKit
    /// doesn't reopen a window on its own.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            showEditor()
        }
        return true
    }

    private func setUpMainWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Better Cheatsheet"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: EditorView(appState: appState, settings: settings))
        window.center()
        mainWindow = window
    }

    /// The app lives in the menu bar, so once the main window is closed
    /// (Cmd+W or the red traffic-light button - both route through here)
    /// there's no reason to keep occupying a Dock slot too.
    func windowWillClose(_ notification: Notification) {
        guard notification.object as? NSWindow === mainWindow else { return }
        NSApp.setActivationPolicy(.accessory)
    }

    private func setUpOverlayPanel() {
        // Borderless (no .titled) so there's no reserved title-bar strip
        // above the content - a titled panel with hidden traffic lights
        // still reserved that space even with the buttons invisible.
        let panel = OverlayPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 360),
            styleMask: [.nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.minSize = NSSize(width: 260, height: 200)
        // Non-opaque/clear permanently (independent of theme): a borderless
        // window has square corners, so CheatsheetView clips its own content
        // to a rounded rect - the transparent window corners around that
        // shape are what make it read as a rounded panel again.
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.contentView = NSHostingView(rootView: CheatsheetView(
            appState: appState,
            settings: settings,
            onOpenMainWindow: { [weak self] in self?.openMainWindowFromOverlay() }
        ))

        // Restores whatever position/size the user last left it at, if any.
        overlayHasPlacement = panel.setFrameUsingName(Self.overlayFrameAutosaveName)
        panel.setFrameAutosaveName(Self.overlayFrameAutosaveName)

        overlayPanel = panel
    }

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(
            systemSymbolName: "list.bullet.rectangle",
            accessibilityDescription: "Better Cheatsheet"
        )

        // No keyEquivalent: this menu isn't part of NSApp.mainMenu, so it
        // wouldn't actually trigger the global hotkey - see
        // updateStatusItemTitle, which puts the real shortcut in the title
        // text instead and keeps it in sync with Settings.
        let showItem = NSMenuItem(title: "Show Cheatsheet", action: #selector(toggleOverlay), keyEquivalent: "")
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
        showCheatsheetMenuItem = showItem
        updateStatusItemTitle(for: settings.hotKey)
    }

    @objc private func toggleOverlay() {
        guard let panel = overlayPanel else { return }
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            if !overlayHasPlacement {
                positionOverlayNearCursor(panel)
                overlayHasPlacement = true
            }
            panel.makeKeyAndOrderFront(nil)
        }
    }

    /// The overlay's "..." button: jumping to the main window means the
    /// user is done glancing at the overlay, so close it rather than leaving
    /// it floating behind the editor.
    private func openMainWindowFromOverlay() {
        overlayPanel?.orderOut(nil)
        showEditor()
    }

    @objc private func showEditor() {
        NSApp.setActivationPolicy(.regular)
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
