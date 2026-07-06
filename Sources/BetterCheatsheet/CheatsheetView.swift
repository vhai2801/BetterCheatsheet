import SwiftUI

/// Content shown in the floating, hotkey-toggled overlay panel: same tab bar
/// (click to switch tabs, but no "+" add control to keep the overlay compact),
/// and a content area that's read-only unless the tab is flagged editable.
struct CheatsheetView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var settings: SettingsStore
    var onOpenMainWindow: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            TabBarView(appState: appState, allowAdding: false, onOpenMainWindow: onOpenMainWindow)
            Divider()

            if let index = appState.selectedIndex {
                let tab = appState.tabs[index]
                if tab.editableInOverlay {
                    AutoReplaceTextEditor(attributedText: $appState.tabs[index].attributedContent)
                } else {
                    ShortcutTableView(rows: .constant(tab.shortcutRows), isEditable: false)
                }
            } else {
                Spacer()
                Text("No tabs yet")
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .frame(minWidth: 260, maxWidth: .infinity, minHeight: 200, maxHeight: .infinity)
        .background {
            if settings.theme == .frostedGlass {
                VisualEffectBackground(material: .hudWindow)
            } else {
                Color(nsColor: .windowBackgroundColor)
            }
        }
        // The overlay panel itself is borderless with a clear background
        // (see AppDelegate.setUpOverlayPanel) specifically so this clip is
        // what gives the panel rounded corners instead of square ones.
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
