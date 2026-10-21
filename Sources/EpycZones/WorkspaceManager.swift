import AppKit
import ApplicationServices

/// Saves and restores complete workspace snapshots (all visible windows + their zone positions).
enum WorkspaceManager {

    struct Workspace: Codable, Identifiable, Equatable {
        let id: UUID
        var name: String
        var entries: [Entry]

        init(id: UUID = UUID(), name: String, entries: [Entry]) {
            self.id = id
            self.name = name
            self.entries = entries
        }

        struct Entry: Codable, Equatable {
            let bundleID: String
            let windowTitle: String
            /// Display name; the only display reference in entries saved before 1.1.
            let screenName: String
            /// Display UUID; nil in entries saved before 1.1.
            let displayUUID: String?
            /// Relative position within screen's visible frame.
            let relativeFrame: RelativeRect
        }
    }

    /// What a restore did, for the Settings window to report.
    struct RestoreReport: Equatable {
        let moved: Int
        let total: Int
        /// Names of apps with saved windows that were not found open.
        let missingApps: [String]

        var summary: String {
            var text = "Moved \(moved) of \(total) windows."
            if !missingApps.isEmpty {
                text += " Not found: \(missingApps.joined(separator: ", "))."
            }
            return text
        }
    }

    // MARK: - Persistence

    private static var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("EpycZones", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("workspaces.json")
    }

    static func loadAll() -> [Workspace] {
        guard let data = try? Data(contentsOf: fileURL),
              let workspaces = try? JSONDecoder().decode([Workspace].self, from: data) else { return [] }
        return workspaces
    }

    static func saveAll(_ workspaces: [Workspace]) {
        guard let data = try? JSONEncoder().encode(workspaces) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    // MARK: - Capture

    /// Capture the standard windows of every visible app, EpycZones excluded.
    /// Titles come from Accessibility and need no Screen Recording permission.
    static func captureCurrentWorkspace(name: String) -> Workspace {
        var entries: [Workspace.Entry] = []

        for (window, bundleID) in WindowManager.openAppWindows() {
            guard let frame = WindowManager.frame(of: window),
                  let screen = WindowManager.screenForWindow(window) else { continue }

            entries.append(Workspace.Entry(
                bundleID: bundleID,
                windowTitle: WindowManager.title(of: window) ?? "",
                screenName: screen.localizedName,
                displayUUID: screen.displayUUID(),
                relativeFrame: RelativeRect(frame: frame, in: screen.visibleFrame)
            ))
        }

        return Workspace(name: name, entries: entries)
    }

    // MARK: - Restore

    /// Moves each saved window that is open now back to its saved frame. Every
    /// entry moves at most one window and every window at most once.
    @discardableResult
    static func restore(_ workspace: Workspace) -> RestoreReport {
        guard AccessibilityChecker.isGranted else {
            return RestoreReport(moved: 0, total: workspace.entries.count, missingApps: [])
        }

        let savedApps = Set(workspace.entries.map(\.bundleID))
        let open = WindowManager.openAppWindows { savedApps.contains($0) }
        let matches = WindowMatcher.match(
            saved: workspace.entries.map { WindowMatcher.Window(bundleID: $0.bundleID, title: $0.windowTitle) },
            open: open.map { WindowMatcher.Window(bundleID: $0.bundleID, title: WindowManager.title(of: $0.window) ?? "") }
        )

        var moved = 0
        for (entryIndex, openIndex) in matches.sorted(by: { $0.key < $1.key }) {
            let entry = workspace.entries[entryIndex]
            guard let screen = NSScreen.matching(displayUUID: entry.displayUUID, name: entry.screenName) else {
                continue
            }
            let targetNS = entry.relativeFrame.frame(in: screen.visibleFrame)
            WindowManager.applyFrame(targetNS, to: open[openIndex].window, animated: false, raisesWindow: false)
            moved += 1
        }

        let missingBundleIDs = workspace.entries.indices
            .filter { matches[$0] == nil }
            .map { workspace.entries[$0].bundleID }
        var seen = Set<String>()
        let missingApps = missingBundleIDs.filter { seen.insert($0).inserted }.map(appName(for:))

        return RestoreReport(moved: moved, total: workspace.entries.count, missingApps: missingApps)
    }

    private static func appName(for bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
        return FileManager.default.displayName(atPath: url.path)
            .replacingOccurrences(of: ".app", with: "")
    }
}
