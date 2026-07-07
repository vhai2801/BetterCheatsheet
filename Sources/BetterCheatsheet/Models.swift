import AppKit
import Combine
import Foundation

/// A single row in a non-"Note tab"'s Shortcut/Action table. Plain strings
/// (no rich text) since the whole point of the table format is a consistent
/// look across tabs, not per-row formatting.
struct ShortcutRow: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var shortcut: String = ""
    var action: String = ""
}

struct TabItem: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    /// RTF-encoded rich text (font, bold, size). Source of truth for content
    /// when the tab is a "Note tab" (see `editableInOverlay`). Plain empty
    /// `Data`, not an RTF-round-tripped empty string - `decodeRTF` already
    /// special-cases `data.isEmpty` to skip parsing entirely, so a brand-new
    /// tab's content never needs a real RTF parse until it actually has text.
    var rtfData: Data = Data()
    /// Doubles as "is this a freeform Note tab": true shows the rich-text
    /// editor (and is editable directly in the overlay, as before); false
    /// shows the templated Shortcut/Action table instead (read-only in the
    /// overlay, editable only in the main window).
    var editableInOverlay: Bool = false
    /// Source of truth for content when the tab is NOT a Note tab.
    var shortcutRows: [ShortcutRow] = []

    private enum CodingKeys: String, CodingKey {
        case id, name, content, rtfData, editableInOverlay, shortcutRows
    }

    init(name: String) {
        self.id = UUID()
        self.name = name
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        editableInOverlay = try container.decodeIfPresent(Bool.self, forKey: .editableInOverlay) ?? false
        shortcutRows = try container.decodeIfPresent([ShortcutRow].self, forKey: .shortcutRows) ?? []
        if let data = try container.decodeIfPresent(Data.self, forKey: .rtfData) {
            rtfData = data
        } else {
            // Migrates tabs saved before rich text was added.
            let plain = try container.decodeIfPresent(String.self, forKey: .content) ?? ""
            rtfData = TabItem.encodeRTF(NSAttributedString(string: plain, attributes: TabItem.defaultAttributes))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(rtfData, forKey: .rtfData)
        try container.encode(editableInOverlay, forKey: .editableInOverlay)
        try container.encode(shortcutRows, forKey: .shortcutRows)
    }

    static let defaultAttributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13)]

    static func encodeRTF(_ attributedString: NSAttributedString) -> Data {
        (try? attributedString.data(
            from: NSRange(location: 0, length: attributedString.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )) ?? Data()
    }

    /// Keyed by the raw RTF bytes, so repeated SwiftUI body re-evaluations
    /// with unchanged content (the common case) skip re-parsing entirely.
    /// Every edit produces a new byte blob (and so a new entry) rather than
    /// updating one in place, so `countLimit` bounds how much stale history
    /// accumulates over a long editing session instead of growing unbounded
    /// (NSCache only evicts under real memory pressure otherwise, which
    /// macOS rarely signals for a small app like this).
    private static let decodeCache: NSCache<NSData, NSAttributedString> = {
        let cache = NSCache<NSData, NSAttributedString>()
        cache.countLimit = 50
        return cache
    }()

    static func decodeRTF(_ data: Data) -> NSAttributedString {
        let key = data as NSData
        if let cached = decodeCache.object(forKey: key) {
            return cached
        }
        guard !data.isEmpty,
              let attributedString = try? NSAttributedString(
                data: data,
                options: [.documentType: NSAttributedString.DocumentType.rtf],
                documentAttributes: nil
              )
        else {
            return NSAttributedString(string: "", attributes: TabItem.defaultAttributes)
        }
        decodeCache.setObject(attributedString, forKey: key)
        return attributedString
    }

    var attributedContent: NSAttributedString {
        get { TabItem.decodeRTF(rtfData) }
        set { rtfData = TabItem.encodeRTF(newValue) }
    }
}

final class AppState: ObservableObject {
    @Published var tabs: [TabItem] {
        didSet { scheduleSave() }
    }
    @Published var selectedTabID: UUID? {
        didSet { saveSelection() }
    }
    /// Transient UI state (not persisted): whether the pinned Settings tab is showing.
    @Published var isShowingSettings: Bool = false
    /// Transient (not persisted): set right after a new tab is created via
    /// the "+" flow, naming which tab's content editor should grab focus
    /// next so typing can continue straight from naming the tab into
    /// filling it in. Consumed (reset to nil) once that view actually
    /// applies the focus, so switching tabs later doesn't re-trigger it.
    @Published var pendingContentFocusTabID: UUID?

    private let fileURL: URL
    private let selectionDefaultsKey = "BetterCheatsheet.selectedTabID"
    private var saveWorkItem: DispatchWorkItem?
    private let saveQueue = DispatchQueue(label: "com.blub.bettercheatsheet.save", qos: .utility)
    private let saveDebounceInterval: TimeInterval = 0.4

    init() {
        let supportDir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BetterCheatsheet", isDirectory: true)
        try? FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
        fileURL = supportDir.appendingPathComponent("tabs.json")

        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([TabItem].self, from: data) {
            tabs = decoded
        } else {
            tabs = Self.starterTabs()
        }

        if let savedIDString = UserDefaults.standard.string(forKey: selectionDefaultsKey),
           let savedID = UUID(uuidString: savedIDString),
           tabs.contains(where: { $0.id == savedID }) {
            selectedTabID = savedID
        } else {
            selectedTabID = tabs.first?.id
        }
    }

    var selectedIndex: Int? {
        guard let id = selectedTabID else { return nil }
        return tabs.firstIndex(where: { $0.id == id })
    }

    /// Starts with one empty row (rather than the fully-empty table state)
    /// so there's already a Shortcut field ready to type into right after
    /// naming the tab - see TabBarView's `commitNewTab` for the focus jump.
    func addTab(named name: String) {
        var tab = TabItem(name: name)
        tab.shortcutRows = [ShortcutRow()]
        tabs.append(tab)
        selectedTabID = tab.id
    }

    /// Note tabs are only ever created through this - never toggled on an
    /// existing tab - so there's no way to accidentally flip a tab someone's
    /// already filled in as a table into a freeform note tab or vice versa.
    func addNoteTab() {
        var tab = TabItem(name: uniqueNoteTabName())
        tab.editableInOverlay = true
        tabs.append(tab)
        selectedTabID = tab.id
    }

    private func uniqueNoteTabName() -> String {
        let existingNames = Set(tabs.map(\.name))
        guard existingNames.contains("Note") else { return "Note" }
        var suffix = 2
        while existingNames.contains("Note \(suffix)") {
            suffix += 1
        }
        return "Note \(suffix)"
    }

    func renameTab(id: UUID, to newName: String) {
        guard let idx = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[idx].name = newName
    }

    /// Moves the tab `id` to sit at `targetIndex` in the *current* ordering
    /// (i.e. as if the tab were removed and everything to its right shifted
    /// left first) - the same convention as `List.onMove`/`move(fromOffsets:toOffset:)`.
    func moveTab(id: UUID, toIndex targetIndex: Int) {
        guard let sourceIndex = tabs.firstIndex(where: { $0.id == id }) else { return }
        let item = tabs.remove(at: sourceIndex)
        var insertIndex = targetIndex
        if sourceIndex < targetIndex {
            insertIndex -= 1
        }
        insertIndex = min(max(insertIndex, 0), tabs.count)
        tabs.insert(item, at: insertIndex)
    }

    func deleteTab(id: UUID) {
        guard let idx = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs.remove(at: idx)
        if selectedTabID == id {
            // Whatever now sits at the same index was "next"; if the deleted
            // tab was last, fall back to the new last tab.
            selectedTabID = tabs.isEmpty ? nil : tabs[min(idx, tabs.count - 1)].id
        }
    }

    /// Coalesces rapid edits - every keystroke in any tab's Note content or
    /// Shortcut/Action table mutates `tabs` - into one encode+write ~0.4s
    /// after the last change, instead of a full JSON-encode-and-atomic-write
    /// of every tab's content (not just the one being edited) on every
    /// single character typed. Captures a value-type snapshot synchronously
    /// so the actual encode/write can happen on a background queue without
    /// racing further edits to `tabs` (Swift arrays/structs are copy-on-write,
    /// so `snapshot` is a true point-in-time copy, safe to touch off-thread).
    private func scheduleSave() {
        saveWorkItem?.cancel()
        let snapshot = tabs
        let workItem = DispatchWorkItem { [fileURL] in
            Self.write(snapshot, to: fileURL)
        }
        saveWorkItem = workItem
        saveQueue.asyncAfter(deadline: .now() + saveDebounceInterval, execute: workItem)
    }

    /// Writes immediately and cancels any pending debounced write - called
    /// just before the app quits (see AppDelegate.applicationWillTerminate)
    /// so an edit made in the last fraction of a second before termination
    /// isn't lost along with the debounce window.
    func flushPendingSave() {
        saveWorkItem?.cancel()
        saveWorkItem = nil
        Self.write(tabs, to: fileURL)
    }

    private static func write(_ tabs: [TabItem], to fileURL: URL) {
        guard let data = try? JSONEncoder().encode(tabs) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private func saveSelection() {
        UserDefaults.standard.set(selectedTabID?.uuidString, forKey: selectionDefaultsKey)
    }

    /// Starter content for a fresh install (no `tabs.json` yet, or one that
    /// fails to decode) - two pre-filled cheatsheets covering common macOS
    /// and text-editing shortcuts, so a new user sees something useful right
    /// away instead of a blank slate. Ordinary tabs once created - freely
    /// renamable/editable/deletable, nothing about them is special beyond
    /// this initial seeding.
    private static func starterTabs() -> [TabItem] {
        func row(_ shortcut: String, _ action: String) -> ShortcutRow {
            ShortcutRow(shortcut: shortcut, action: action)
        }

        var general = TabItem(name: "General")
        general.shortcutRows = [
            row("⌘W", "Close Window"),
            row("⌥⌘W", "Close All Windows"),
            row("⌘Q", "Quit App"),
            row("⌥⌘⎋", "Force Quit Applications"),
            row("⌘H", "Hide App"),
            row("⌥⌘H", "Hide Others"),
            row("⌘M", "Minimize Window"),
            row("⌥⌘M", "Minimize All Windows"),
            row("⌘,", "App Preferences"),
            row("⌘⇥", "Switch Apps"),
            row("⇧⌘⇥", "Switch Apps (Reverse)"),
            row("⌘`", "Cycle Windows in App"),
            row("⌃⌘␣", "Emoji & Symbols Viewer"),
            row("⌘E", "Eject"),
            row("⌘⌫", "Move to Trash"),
            row("⇧⌘⌫", "Empty Trash"),
        ]

        var textsBased = TabItem(name: "Texts based")
        textsBased.shortcutRows = [
            row("⌘C", "Copy"),
            row("⌘X", "Cut"),
            row("⌘V", "Paste"),
            row("⇧⌘V", "Paste and Match Style"),
            row("⌘Z", "Undo"),
            row("⇧⌘Z", "Redo"),
            row("⌃␣", "Change Input language"),
            row("⌘A", "Select All"),
            row("⌘F", "Find"),
            row("⌘G", "Find Next"),
            row("⇧⌘G", "Find Previous"),
            row("⌘B", "Bold"),
            row("⌘I", "Italic"),
            row("⌘U", "Underline"),
            row("⌘←", "Move to Start of Line"),
            row("⌘→", "Move to End of Line"),
            row("⌥←", "Move Word Left"),
            row("⌥→", "Move Word Right"),
            row("⌥⌫", "Delete Word Backward"),
            row("⌘⌫", "Delete to Start of Line"),
            row("⇧⏎", "Insert Line Break"),
            row("⌥␣", "Non-breaking Space"),
        ]

        return [general, textsBased]
    }
}
