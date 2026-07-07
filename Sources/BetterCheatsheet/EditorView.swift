import SwiftUI

/// Main window content: tab bar on top, editor for the selected tab below.
/// Whether a tab is a templated Shortcut/Action table or a freeform Note tab
/// is fixed at creation time (see TabBarView's "+" vs "Note" controls) and
/// can't be changed afterward, so there's no toggle here for it.
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
                        if appState.tabs[index].editableInOverlay {
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
                        } else {
                            Button {
                                appState.tabs[index].shortcutRows.append(ShortcutRow())
                            } label: {
                                Image(systemName: "plus")
                            }
                            .help("Add row")

                            Button {
                                settings.shortcutTableFontSize = max(settings.shortcutTableFontSize - 1, 9)
                            } label: {
                                Image(systemName: "textformat.size.smaller")
                            }
                            .help("Decrease shortcut/action text size")

                            Button {
                                settings.shortcutTableFontSize = min(settings.shortcutTableFontSize + 1, 28)
                            } label: {
                                Image(systemName: "textformat.size.larger")
                            }
                            .help("Increase shortcut/action text size")
                        }

                        Spacer()

                        Button(role: .destructive) {
                            appState.deleteTab(id: appState.tabs[index].id)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .help("Delete this tab")
                    }
                    .buttonStyle(.bordered)
                    .focusable(false)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)

                    if appState.tabs[index].editableInOverlay {
                        AutoReplaceTextEditor(
                            attributedText: $appState.tabs[index].attributedContent,
                            formattingController: formattingController
                        )
                    } else {
                        ShortcutTableView(
                            rows: $appState.tabs[index].shortcutRows,
                            isEditable: true,
                            settings: settings,
                            focusFirstRowOnAppear: appState.pendingContentFocusTabID == appState.tabs[index].id,
                            onFocusRequestHandled: { appState.pendingContentFocusTabID = nil }
                        )
                        // Forces a fresh mount (and so a fresh onAppear) each
                        // time the selected tab changes, rather than reusing
                        // the same view instance across different tabs -
                        // otherwise the focus-on-appear above would only
                        // ever fire for the very first table tab shown.
                        .id(appState.tabs[index].id)
                    }
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
