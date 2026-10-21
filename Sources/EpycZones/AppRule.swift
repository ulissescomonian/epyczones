import AppKit
import Foundation
import Observation

/// A rule that auto-snaps new windows of a specific app to a position or zone.
struct AppRule: Identifiable, Codable, Equatable {
    enum Target: Codable, Equatable {
        case position(SnapPosition)
        /// Index into the active layout of the screen the window appears on.
        case zone(Int)

        var displayName: String {
            switch self {
            case .position(let p): return p.displayName
            case .zone(let i):     return String(localized: "Zone \(i + 1)")
            }
        }
    }

    let id: UUID
    var bundleID: String
    var appName: String
    var target: Target

    init(id: UUID = UUID(), bundleID: String, appName: String, target: Target) {
        self.id = id
        self.bundleID = bundleID
        self.appName = appName
        self.target = target
    }
}

/// Persists app rules to ~/Library/Application Support/EpycZones/app-rules.json.
@Observable
@MainActor
final class AppRuleStore {
    static let shared = AppRuleStore(fileURL: AppPaths.file("app-rules.json"))

    private(set) var rules: [AppRule] = []

    /// Where rules persist; nil keeps them in memory, for screen renders.
    private let fileURL: URL?

    init(fileURL: URL?) {
        self.fileURL = fileURL
        load()
    }

    /// A store that never touches disk, filled with the given rules.
    static func inMemory(rules: [AppRule]) -> AppRuleStore {
        let store = AppRuleStore(fileURL: nil)
        store.rules = rules
        return store
    }

    func add(_ rule: AppRule) {
        // One rule per app — replace any existing rule for the same bundle ID.
        rules.removeAll { $0.bundleID == rule.bundleID }
        rules.append(rule)
        save()
        AppRuleMonitor.shared.reload()
    }

    func remove(id: UUID) {
        rules.removeAll { $0.id == id }
        save()
        AppRuleMonitor.shared.reload()
    }

    func rule(for bundleID: String) -> AppRule? {
        rules.first { $0.bundleID == bundleID }
    }

    private func save() {
        guard let fileURL else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(rules) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private func load() {
        guard let fileURL, let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([AppRule].self, from: data) else { return }
        rules = decoded
    }
}
