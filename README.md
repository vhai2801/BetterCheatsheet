# Better Cheatsheet

A native macOS app for keeping notes on your custom keyboard shortcuts, with a global hotkey that pops up a floating "cheatsheet" overlay so you never have to leave what you're doing to remember one.

## Features

- **Unlimited named tabs** for organizing shortcuts into groups, with drag-to-reorder
- **Global hotkey** (default ⇧⌘K, fully re-recordable) toggles a floating overlay showing your notes over whatever app you're in
- **Per-tab overlay editing** — mark a tab "editable in overlay" to jot things down without opening the main window
- **Rich text**: bold, font size, and full font family/style via the native Font Panel
- **Auto-replace**: type `CMD`, `SHIFT`, `OPTION`, etc. in all caps and it's replaced with the real symbol (⌘, ⇧, ⌥, ...) as you type
- **Left/right modifier matching** (optional) — make a shortcut trigger only on, say, the right Shift key, not either side
- **Light / Dark / Frosted Glass** themes (Frosted Glass applies to the overlay only)
- No network access of any kind; notes are stored locally only

## Install

Via Homebrew:

```
brew tap vhai2801/better-cheatsheet
brew install --cask better-cheatsheet
```

Update later with:

```
brew update && brew upgrade --cask better-cheatsheet
```

## Building from source

Requires only Xcode Command Line Tools (no full Xcode needed) — this is a Swift Package, not an Xcode project.

```
git clone https://github.com/vhai2801/BetterCheatsheet.git
cd BetterCheatsheet
./build.sh            # debug build
./build.sh --release   # release build
```

Either produces a real, double-clickable `BetterCheatsheet.app` (path printed at the end of the build).

## Notes

The app isn't notarized (no paid Apple Developer ID), so it's ad-hoc code signed. The Homebrew cask strips the quarantine flag on install so it launches without a Gatekeeper prompt; building from source and running it directly may show an "unidentified developer" warning on first launch — right-click the app and choose Open to bypass it.
