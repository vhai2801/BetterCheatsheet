import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var appState: AppState

    @State private var dataMessage: String?

    var body: some View {
        Form {
            Section("Global Shortcut") {
                HStack {
                    Text("Toggle overlay:")
                    HotKeyRecorderView(
                        hotKey: $settings.hotKey,
                        displayText: HotKeyFormatter.string(for: settings.hotKey)
                    )
                    .fixedSize()
                }

                Toggle("Match left/right modifier side", isOn: sideSensitiveBinding)
            }

            Section("Appearance") {
                Picker("Theme", selection: $settings.theme) {
                    ForEach(AppTheme.allCases) { theme in
                        Text(theme.label).tag(theme)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Shortcut Display") {
                Toggle("Show shortcuts as text (Cmd Shift K) instead of symbols (⌘⇧K)", isOn: $settings.shortcutsDisplayAsText)
            }

            Section("Data") {
                HStack {
                    Button("Export All Tabs…", action: exportTabs)
                    Button("Import Tabs…", action: importTabs)
                }
                if let dataMessage {
                    Text(dataMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// Writes every tab - including Note tabs' rich text, since `TabItem` is
    /// already `Codable` with RTF stored as plain `Data` - to a user-chosen
    /// file. Same JSON shape as `tabs.json` itself, so the exported file can
    /// be copied to another machine and imported there directly.
    private func exportTabs() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "BetterCheatsheet-Export.json"
        panel.title = "Export All Tabs"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let data = try JSONEncoder().encode(appState.tabs)
            try data.write(to: url, options: .atomic)
            dataMessage = "Exported \(appState.tabs.count) tab\(appState.tabs.count == 1 ? "" : "s")."
        } catch {
            dataMessage = "Export failed: \(error.localizedDescription)"
        }
    }

    /// Lets the user choose whether the imported tabs replace everything
    /// current or sit alongside it - confirmed first (via a real `NSAlert`,
    /// not just a toggle) either way, since "Overwrite" discards anything
    /// not present in the import.
    private func importTabs() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.title = "Import Tabs"
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let data = try Data(contentsOf: url)
            let imported = try JSONDecoder().decode([TabItem].self, from: data)

            let alert = NSAlert()
            alert.messageText = "Import \(imported.count) tab\(imported.count == 1 ? "" : "s")"
            alert.informativeText = "Overwrite replaces your \(appState.tabs.count) current tab\(appState.tabs.count == 1 ? "" : "s") with the imported ones. Add keeps your current tabs and adds the imported ones alongside them."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "Overwrite")
            alert.addButton(withTitle: "Add")
            alert.addButton(withTitle: "Cancel")

            switch alert.runModal() {
            case .alertFirstButtonReturn:
                appState.tabs = imported
                appState.selectedTabID = imported.first?.id
                dataMessage = "Imported \(imported.count) tab\(imported.count == 1 ? "" : "s") (overwrote existing)."
            case .alertSecondButtonReturn:
                // Fresh IDs, not the imported ones as-is - re-importing the
                // same file a second time (or a file exported from this same
                // machine) would otherwise append tabs sharing an `id` with
                // ones already in `appState.tabs`, which breaks SwiftUI's
                // `ForEach(appState.tabs, id: \.element.id)` identity.
                let added = imported.map { tab -> TabItem in
                    var copy = tab
                    copy.id = UUID()
                    return copy
                }
                appState.tabs.append(contentsOf: added)
                appState.selectedTabID = added.first?.id
                dataMessage = "Added \(added.count) tab\(added.count == 1 ? "" : "s")."
            default:
                return
            }
        } catch {
            dataMessage = "Import failed: \(error.localizedDescription)"
        }
    }

    /// Auto-populates left-side keyCodes from the generic modifier mask when
    /// turning this on for a hotkey that's never been re-recorded since side
    /// sensitivity was added, so it doesn't silently stop matching anything.
    private var sideSensitiveBinding: Binding<Bool> {
        Binding(
            get: { settings.hotKey.sideSensitive },
            set: { newValue in
                var hotKey = settings.hotKey
                if newValue && hotKey.modifierKeyCodes.isEmpty {
                    hotKey.modifierKeyCodes = ModifierKeyCode.defaultLeftKeyCodes(forCarbonModifiers: hotKey.modifiers)
                }
                hotKey.sideSensitive = newValue
                settings.hotKey = hotKey
            }
        )
    }
}
