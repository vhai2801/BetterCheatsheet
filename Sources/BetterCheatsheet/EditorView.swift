import SwiftUI

/// Main window content: tab bar on top, editor for the selected tab below,
/// plus a per-tab toggle for whether it stays editable inside the floating
/// overlay too.
struct EditorView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var settings: SettingsStore

    var body: some View {
        VStack(spacing: 0) {
            TabBarView(appState: appState, showsSettingsTab: true)
            Divider()

            if appState.isShowingSettings {
                SettingsView(settings: settings)
            } else if let index = appState.selectedIndex {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Spacer()
                        Toggle("Editable in overlay", isOn: $appState.tabs[index].editableInOverlay)
                            .toggleStyle(.checkbox)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)

                    AutoReplaceTextEditor(text: $appState.tabs[index].content)
                }
            } else {
                Spacer()
                Text("No tabs yet — add one above")
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .frame(minWidth: 420, minHeight: 320)
        .background {
            if settings.theme == .frostedGlass {
                VisualEffectBackground(material: .underWindowBackground)
            }
        }
    }
}
