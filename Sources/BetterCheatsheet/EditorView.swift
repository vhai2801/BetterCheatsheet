import SwiftUI

/// Main window content: tab bar on top, editor for the selected tab below,
/// plus a per-tab toggle for whether it stays editable inside the floating
/// overlay too.
struct EditorView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var settings: SettingsStore

    @State private var formattingController = TextFormattingController()

    var body: some View {
        VStack(spacing: 0) {
            TabBarView(appState: appState, showsSettingsTab: true)
            Divider()

            if appState.isShowingSettings {
                SettingsView(settings: settings)
            } else if let index = appState.selectedIndex {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 10) {
                        Button(action: formattingController.toggleBold) {
                            Image(systemName: "bold")
                        }
                        .help("Bold")

                        Button(action: formattingController.decreaseFontSize) {
                            Image(systemName: "textformat.size.smaller")
                        }
                        .help("Decrease font size")

                        Button(action: formattingController.increaseFontSize) {
                            Image(systemName: "textformat.size.larger")
                        }
                        .help("Increase font size")

                        Button(action: formattingController.showFontPanel) {
                            Image(systemName: "textformat")
                        }
                        .help("Change font")

                        Spacer()

                        Toggle("Editable in overlay", isOn: $appState.tabs[index].editableInOverlay)
                            .toggleStyle(.checkbox)
                    }
                    .buttonStyle(.bordered)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)

                    AutoReplaceTextEditor(
                        attributedText: $appState.tabs[index].attributedContent,
                        formattingController: formattingController
                    )
                }
            } else {
                Spacer()
                Text("No tabs yet — add one above")
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .frame(minWidth: 420, minHeight: 320)
    }
}
