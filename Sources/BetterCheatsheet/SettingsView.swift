import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: SettingsStore

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
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
