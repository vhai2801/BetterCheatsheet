# Better Cheatsheet

## Overview
A native macOS menu-bar/window app for keeping notes on custom keyboard shortcuts. Notes are organized into user-named tabs (unlimited count) shown in a top tab bar. A global hotkey (default **⌘⇧K**) toggles a floating overlay panel that shows the same tabs/content as a quick-glance cheatsheet, without switching away from whatever app you're using. Tabs can individually be marked "editable in overlay" so you can jot things down without opening the full editor window. While editing, typing an exact ALL-CAPS modifier keyword (e.g. `CMD`, `OPTION`, `SHIFT`) auto-replaces it with its symbol (⌘, ⌥, ⇧, ...) as soon as you type a word-boundary character after it. The app makes no network connections and stores notes locally only, at `~/Library/Application Support/BetterCheatsheet/tabs.json`.

Built as a Swift Package (not an Xcode project) because only Xcode Command Line Tools are installed, not full Xcode. `build.sh` wraps the compiled binary into a real, ad-hoc-codesigned `BetterCheatsheet.app` bundle.

## Architecture map
- `Package.swift` — executable target `BetterCheatsheet`, macOS 13+, zero dependencies
- `Sources/BetterCheatsheet/main.swift` — entry point: creates `NSApplication`, sets `.regular` activation policy, assigns `AppDelegate`, calls `app.run()`
- `Sources/BetterCheatsheet/AppDelegate.swift` — owns the main editor `NSWindow`, the floating `OverlayPanel` (an `NSPanel` subclass with `.nonactivatingPanel` style so it can become key for typing without stealing app focus), the `NSStatusItem` menu bar icon/menu (Show Cheatsheet / Edit Notes / Quit), and registers the global hotkey
- `Sources/BetterCheatsheet/HotKeyManager.swift` — wraps Carbon's `RegisterEventHotKey`/`InstallEventHandler`. Chosen over a `CGEventTap` specifically to avoid needing Accessibility/Input Monitoring permission on first launch
- `Sources/BetterCheatsheet/Models.swift` — `TabItem` (Codable: id, name, content, editableInOverlay) and `AppState` (ObservableObject; loads/saves `[TabItem]` as JSON to Application Support, persists selected tab id in `UserDefaults`)
- `Sources/BetterCheatsheet/TextReplacement.swift` — pure dictionary (ALL-CAPS keyword → symbol) + `TextReplacement.replacement(in:beforeLocation:)`, a pure NSString range-finder with no UIKit/AppKit dependency, easy to unit-test/extend
- `Sources/BetterCheatsheet/AutoReplaceTextEditor.swift` — `NSViewRepresentable` wrapping `NSTextView`; intercepts `shouldChangeTextIn:replacementString:` to apply `TextReplacement` live at the caret, preserving cursor position
- `Sources/BetterCheatsheet/TabBarView.swift` — horizontal scrolling tab bar; `TabButton` collapses to `maxWidth: 110` and expands to fit content on hover (animated); double-click to rename, right-click for rename/delete, "+" control to add (hidden in the overlay via `allowAdding: false`)
- `Sources/BetterCheatsheet/EditorView.swift` — main window content: tab bar + "editable in overlay" checkbox + `AutoReplaceTextEditor` for the selected tab
- `Sources/BetterCheatsheet/CheatsheetView.swift` — overlay content: tab bar (no add control) + read-only `Text` unless the tab is `editableInOverlay`, in which case the same `AutoReplaceTextEditor` is used
- `Info.plist` — app bundle metadata (`LSMinimumSystemVersion` 13.0, no network entitlements requested)
- `build.sh` — `swift build` + manual `.app` bundle assembly + ad-hoc `codesign`

## Current status (as of 2026-07-05)
- All source files written, `swift build` succeeds cleanly.
- Not yet done: running `build.sh` to produce the `.app`, launching it, visually verifying via screenshot, initializing git, creating the private GitHub repo and pushing.
- Everything below "Build & repo steps" in the original plan (`/Users/blub/.claude/plans/melodic-floating-crane.md`) is the source of truth for what was originally scoped, in case this doc and that plan ever disagree.

## Next steps
1. Run `./build.sh`, `open` the resulting `.app`, confirm it launches without crashing, take a screenshot to sanity-check the window/tab bar/menu bar icon.
2. Hand off to the user for interactive testing: add a tab, type `CMD ` and confirm it becomes `⌘ `, trigger ⌘⇧K to confirm the overlay toggles and appears near the cursor without stealing focus from the frontmost app, confirm an "editable in overlay" tab is actually typable while the overlay is showing.
3. `git init` in this folder (independent from the user's home-directory repo, which must not be touched), commit everything except build artifacts (`.gitignore` already covers `.build/`, `.swiftpm/`, `*.app`, `.DS_Store`).
4. Create a private GitHub repo (`gh repo create BetterCheatsheet --private --source=. --remote=origin --push`) and push.
5. Fix anything the user reports broken from step 2.

## Decisions log
- 2026-07-05: Chose Swift Package Manager + a manual `.app`-bundle build script over an Xcode project, because only Command Line Tools are installed (no `xcodebuild`). Revisit if the user installs full Xcode and wants project-file conveniences (asset catalogs for a real app icon, etc.).
- 2026-07-05: Chose Carbon `RegisterEventHotKey` over a `CGEventTap`/`NSEvent.addGlobalMonitorForEvents` for the global hotkey specifically to avoid an Accessibility/Input Monitoring permission prompt on first launch.
- 2026-07-05: Overlay is an `NSPanel` subclass (`OverlayPanel`) overriding `canBecomeKey` to allow text editing in overlay-editable tabs, while `.nonactivatingPanel` keeps it from stealing focus/activating the app when just glancing at a read-only tab.
- 2026-07-05: User notes (`tabs.json`) are stored per-machine in Application Support, not committed to git — only the app's source syncs across laptops. Revisit if the user wants notes portable across machines too (would need a manual export/import or committing the JSON, since there's no network sync by design).
