import Foundation
import Combine

struct TabItem: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var content: String = ""
    var editableInOverlay: Bool = false
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
           let decoded = try? JSONDecoder().decode([TabItem].self, from: data),
           !decoded.isEmpty {
            tabs = decoded
        } else {
            tabs = [TabItem(name: "General")]
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

    func deleteTab(id: UUID) {
        guard let idx = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs.remove(at: idx)
        if tabs.isEmpty {
            tabs = [TabItem(name: "General")]
        }
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
