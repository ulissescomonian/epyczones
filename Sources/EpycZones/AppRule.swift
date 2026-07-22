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
            case .zone(let i):     return "Zone \(i + 1) (active layout)"
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
final class AppRuleStore {
    static let shared = AppRuleStore()

    private(set) var rules: [AppRule] = []

    private var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("EpycZones", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("app-rules.json")
    }

    private init() {
        load()
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
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(rules) else { return }
        try? data.write(to: fileURL)
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([AppRule].self, from: data) else { return }
        rules = decoded
    }
}
