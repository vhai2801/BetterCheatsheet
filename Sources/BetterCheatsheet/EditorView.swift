import SwiftUI

/// Main window content: tab bar on top, editor for the selected tab below.
/// Whether a tab is a templated Shortcut/Action table or a freeform Note tab
/// is fixed at creation time (see TabBarView's "+" vs "Note" controls) and
/// can't be changed afterward, so there's no toggle here for it.
struct EditorView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var settings: SettingsStore

    @State private var formattingController = TextFormattingController()

    /// The line-spacing multiples offered in both the Note tab toolbar's
    /// menu (`TextFormattingController.setLineSpacing(_:)`, a real
    /// NSParagraphStyle line-height multiple) and the table tabs' toolbar
    /// menu (`settings.shortcutTableLineSpacing`, scaled into row spacing
    /// and `.lineSpacing(_:)` - see ShortcutTableView.swift) - matches the
    /// options Word/Docs expose. No "0" (would mean "natural/unmodified
    /// line height") - removed per direct request, since it rendered
    /// visually identical to "1" (an exact 1x multiple of that same
    /// natural height) for the fonts this app uses, making it a redundant
    /// option. Explicit labels rather than formatting the `CGFloat`
    /// directly, so "1"/"2" don't risk rendering with a stray ".0"
    /// depending on locale.
    private static let lineSpacingOptions: [(label: String, value: CGFloat)] = [
        ("1", 1), ("1.25", 1.25), ("1.5", 1.5), ("2", 2),
    ]

    var body: some View {
        VStack(spacing: 0) {
            TabBarView(appState: appState, showsSettingsTab: true)
            Divider()

            if appState.isShowingSettings {
                SettingsView(settings: settings, appState: appState)
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

                            lineSpacingMenu { formattingController.setLineSpacing($0) }
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

                            lineSpacingMenu { settings.shortcutTableLineSpacing = $0 }
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
                            isTrackpadTemplate: appState.tabs[index].isTrackpadTemplate,
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

    /// Shared by both toolbar branches above (Note tab and table tab) -
    /// identical menu, just a different destination for the chosen value.
    private func lineSpacingMenu(onSelect: @escaping (CGFloat) -> Void) -> some View {
        Menu {
            ForEach(EditorView.lineSpacingOptions, id: \.value) { option in
                Button(option.label) { onSelect(option.value) }
            }
        } label: {
            Image(systemName: "arrow.up.and.down.text.horizontal")
        }
        .help("Line spacing")
    }
}
