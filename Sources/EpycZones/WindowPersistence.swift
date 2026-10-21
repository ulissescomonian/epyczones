import AppKit
import ApplicationServices
import OSLog

/// Records which windows were snapped to which zones and restores them on launch.
@MainActor
enum WindowPersistence {

    // MARK: - Data Model

    struct Record: Codable, Equatable {
        let bundleID: String
        let windowTitle: String
        /// Display name; the only display reference in records written before 1.1.
        let screenName: String
        /// Display UUID; nil in records written before 1.1.
        let displayUUID: String?
        let layoutID: UUID
        let zoneIndex: Int
    }

    private static var records: [Record] = []
    private static let maxRecords = 200

    // MARK: - Persistence

    private static let fileURL = AppPaths.file("window-zones.json")

    static func save() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    static func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([Record].self, from: data) else { return }
        records = decoded
    }

    // MARK: - Recording

    /// Record that a window was snapped to a zone.
    static func record(window: AXUIElement, zoneIndex: Int, screen: NSScreen, layoutID: UUID) {
        guard let bundleID = bundleID(of: window) else { return }
        let title = AXWindow.title(of: window) ?? ""

        // Remove old record for this window
        records.removeAll { $0.bundleID == bundleID && $0.windowTitle == title }

        records.append(Record(
            bundleID: bundleID,
            windowTitle: title,
            screenName: screen.localizedName,
            displayUUID: screen.displayUUID(),
            layoutID: layoutID,
            zoneIndex: zoneIndex
        ))

        // Cap size
        if records.count > maxRecords {
            records = Array(records.suffix(maxRecords))
        }

        save()
    }

    // MARK: - Restoring

    /// Moves open windows back to their last recorded zones.
    ///
    /// Titles come from Accessibility, so this needs no Screen Recording
    /// permission; CGWindowList titles do, and without them nothing was ever
    /// restored. Matching follows `WindowMatcher`, so an untitled record never
    /// moves an arbitrary window of its app.
    static func restoreAll() {
        guard AccessibilityChecker.isGranted, !records.isEmpty else { return }

        let recordedApps = Set(records.map(\.bundleID))
        let open = WindowManager.openAppWindows { recordedApps.contains($0) }
        let matches = WindowMatcher.match(
            saved: records.map { WindowMatcher.Window(bundleID: $0.bundleID, title: $0.windowTitle) },
            open: open.map { WindowMatcher.Window(bundleID: $0.bundleID, title: AXWindow.title(of: $0.window) ?? "") }
        )

        var restored = 0
        for (recordIndex, openIndex) in matches {
            let record = records[recordIndex]
            guard let screen = NSScreen.matching(displayUUID: record.displayUUID, name: record.screenName),
                  let layout = LayoutStore.shared.layout(id: record.layoutID),
                  layout.zones.indices.contains(record.zoneIndex) else { continue }

            let targetNS = layout.zones[record.zoneIndex].rect.frame(
                in: screen.visibleFrame,
                gap: AppSettings.shared.zoneGap
            )
            WindowManager.applyFrame(targetNS, to: open[openIndex].window, animated: false, raisesWindow: false)
            restored += 1
        }
        Log.app.notice("Restored \(restored) of \(open.count) open windows from \(records.count) records")
    }

    // MARK: - AX Helpers

    private static func bundleID(of window: AXUIElement) -> String? {
        var pid: pid_t = 0
        guard AXUIElementGetPid(window, &pid) == .success else { return nil }
        return NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
    }
}
