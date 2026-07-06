import AppKit
import Combine
import Foundation

struct TabItem: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    /// RTF-encoded rich text (font, bold, size). Source of truth for content.
    var rtfData: Data = TabItem.encodeRTF(NSAttributedString(string: "", attributes: TabItem.defaultAttributes))
    var editableInOverlay: Bool = false

    private enum CodingKeys: String, CodingKey {
        case id, name, content, rtfData, editableInOverlay
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
    private static let decodeCache = NSCache<NSData, NSAttributedString>()

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
        didSet { save() }
    }
    @Published var selectedTabID: UUID? {
        didSet { saveSelection() }
    }
    /// Transient UI state (not persisted): whether the pinned Settings tab is showing.
    @Published var isShowingSettings: Bool = false

    private let fileURL: URL
    private let selectionDefaultsKey = "BetterCheatsheet.selectedTabID"

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
            tabs = []
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

    func addTab(named name: String) {
        let tab = TabItem(name: name)
        tabs.append(tab)
        selectedTabID = tab.id
    }

    func renameTab(id: UUID, to newName: String) {
        guard let idx = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[idx].name = newName
    }

    /// Moves the tab `id` to sit right before `targetID`, for drag-to-reorder.
    func moveTab(id: UUID, before targetID: UUID) {
        guard id != targetID, let sourceIndex = tabs.firstIndex(where: { $0.id == id }) else { return }
        let item = tabs.remove(at: sourceIndex)
        let insertIndex = tabs.firstIndex(where: { $0.id == targetID }) ?? tabs.count
        tabs.insert(item, at: insertIndex)
    }

    func deleteTab(id: UUID) {
        guard let idx = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs.remove(at: idx)
        if selectedTabID == id {
            selectedTabID = tabs.first?.id
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(tabs) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private func saveSelection() {
        UserDefaults.standard.set(selectedTabID?.uuidString, forKey: selectionDefaultsKey)
    }
}
