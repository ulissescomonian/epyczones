import AppKit
import ApplicationServices

/// Records which windows were snapped to which zones and restores them on launch.
enum WindowPersistence {

    // MARK: - Data Model

    struct Record: Codable, Equatable {
        let bundleID: String
        let windowTitle: String
        let screenName: String
        let layoutID: UUID
        let zoneIndex: Int
    }

    private static var records: [Record] = []
    private static let maxRecords = 200

    // MARK: - Persistence

    private static var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("EpycZones", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("window-zones.json")
    }

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
        let title = windowTitle(of: window) ?? ""
        let screenName = screen.localizedName

        // Remove old record for this window
        records.removeAll { $0.bundleID == bundleID && $0.windowTitle == title }

        // Add new record
        let newRecord = Record(
            bundleID: bundleID,
            windowTitle: title,
            screenName: screenName,
            layoutID: layoutID,
            zoneIndex: zoneIndex
        )
        records.append(newRecord)

        // Cap size
        if records.count > maxRecords {
            records = Array(records.suffix(maxRecords))
        }

        save()
    }

    // MARK: - Restoring

    /// Restore all visible windows to their last recorded zones.
    static func restoreAll() {
        guard AccessibilityChecker.isGranted else { return }
        guard !records.isEmpty else { return }

        let store = LayoutStore.shared

        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return }

        for windowInfo in windowList {
            guard let layer = windowInfo[kCGWindowLayer as String] as? Int, layer == 0,
                  let ownerPID = windowInfo[kCGWindowOwnerPID as String] as? pid_t,
                  let windowName = windowInfo[kCGWindowName as String] as? String,
                  let app = NSRunningApplication(processIdentifier: ownerPID),
                  let bundleID = app.bundleIdentifier else { continue }

            // Find matching record
            guard let record = records.first(where: {
                $0.bundleID == bundleID && ($0.windowTitle == windowName || $0.windowTitle.isEmpty)
            }) else { continue }

            // Find the target screen and layout
            guard let screen = NSScreen.screens.first(where: { $0.localizedName == record.screenName }),
                  let layout = store.layouts.first(where: { $0.id == record.layoutID }),
                  record.zoneIndex < layout.zones.count else { continue }

            // Get the AXUIElement for this window
            let appElement = AXUIElementCreateApplication(ownerPID)
            guard let window = findWindow(titled: windowName, in: appElement) else { continue }

            // Snap to zone
            let zone = layout.zones[record.zoneIndex]
            let targetNS = zone.rect.frame(in: screen.visibleFrame)
            let primaryHeight = NSScreen.screens[0].frame.height
            var position = CGPoint(x: targetNS.origin.x, y: primaryHeight - targetNS.origin.y - targetNS.height)
            if let val = AXValueCreate(.cgPoint, &position) {
                AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, val)
            }
            var size = CGSize(width: targetNS.width, height: targetNS.height)
            if let val = AXValueCreate(.cgSize, &size) {
                AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, val)
            }
        }
    }

    // MARK: - AX Helpers

    private static func bundleID(of window: AXUIElement) -> String? {
        var pid: pid_t = 0
        guard AXUIElementGetPid(window, &pid) == .success else { return nil }
        return NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
    }

    private static func windowTitle(of window: AXUIElement) -> String? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }

    private static func findWindow(titled title: String, in app: AXUIElement) -> AXUIElement? {
        var windowsRef: AnyObject?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement] else { return nil }

        for window in windows {
            var titleRef: AnyObject?
            if AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef) == .success,
               let windowTitle = titleRef as? String, windowTitle == title {
                return window
            }
        }
        // Fallback: return first window if no title match
        return windows.first
    }
}
