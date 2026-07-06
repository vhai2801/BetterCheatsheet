import SwiftUI

/// Content shown in the floating, hotkey-toggled overlay panel: same tab bar
/// (click to switch tabs, but no "+" add control to keep the overlay compact),
/// and a content area that's read-only unless the tab is flagged editable.
struct CheatsheetView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var settings: SettingsStore

    var body: some View {
        VStack(spacing: 0) {
            TabBarView(appState: appState, allowAdding: false)
            Divider()

            if let index = appState.selectedIndex {
                let tab = appState.tabs[index]
                if tab.editableInOverlay {
                    AutoReplaceTextEditor(text: $appState.tabs[index].content)
                } else {
                    ScrollView {
                        Text(tab.content)
                            .font(.system(size: 13))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                    }
                }
            } else {
                Spacer()
                Text("No tabs yet")
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .frame(width: 420, height: 360)
        .background {
            if settings.theme == .frostedGlass {
                VisualEffectBackground(material: .hudWindow)
            } else {
                Color(nsColor: .windowBackgroundColor)
            }
        }
    }
}
