import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        Form {
            Section("Global Shortcut") {
                HStack {
                    Text("Toggle overlay:")
                    HotKeyRecorderView(
                        keyCode: $settings.hotKey.keyCode,
                        modifiers: $settings.hotKey.modifiers,
                        displayText: HotKeyFormatter.string(for: settings.hotKey)
                    )
                    .frame(width: 200, height: 28)
                }
                Text("Click the field, then press the new key combination. Requires at least one modifier key.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Appearance") {
                Picker("Theme", selection: $settings.theme) {
                    ForEach(AppTheme.allCases) { theme in
                        Text(theme.label).tag(theme)
                    }
                }
                .pickerStyle(.segmented)
                Text("Applies to both the main window and the floating overlay.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
