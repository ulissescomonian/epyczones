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
            let screenName: String
            /// Relative position within screen's visible frame.
            let relativeFrame: RelativeRect
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

    /// Capture current window arrangement as a workspace.
    static func captureCurrentWorkspace(name: String) -> Workspace {
        var entries: [Workspace.Entry] = []

        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return Workspace(name: name, entries: []) }

        let primaryHeight = NSScreen.screens[0].frame.height

        for info in windowList {
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  let app = NSRunningApplication(processIdentifier: pid),
                  let bundleID = app.bundleIdentifier,
                  let boundsDict = info[kCGWindowBounds as String] as? [String: CGFloat] else { continue }

            let title = info[kCGWindowName as String] as? String ?? ""

            // CG window bounds are in CG coords (top-left origin)
            let cgRect = CGRect(
                x: boundsDict["X"] ?? 0,
                y: boundsDict["Y"] ?? 0,
                width: boundsDict["Width"] ?? 0,
                height: boundsDict["Height"] ?? 0
            )

            // Convert to NSScreen coords
            let nsX = cgRect.origin.x
            let nsY = primaryHeight - cgRect.origin.y - cgRect.height

            // Find which screen this window is on
            let centerNS = NSPoint(x: nsX + cgRect.width / 2, y: nsY + cgRect.height / 2)
            guard let screen = NSScreen.screens.first(where: { $0.frame.contains(centerNS) }) else { continue }
            let vf = screen.visibleFrame

            // Convert to relative coords within visible frame
            let relRect = RelativeRect(
                x: (nsX - vf.origin.x) / vf.width,
                y: 1.0 - (nsY - vf.origin.y + cgRect.height) / vf.height,
                width: cgRect.width / vf.width,
                height: cgRect.height / vf.height
            )

            entries.append(Workspace.Entry(
                bundleID: bundleID,
                windowTitle: title,
                screenName: screen.localizedName,
                relativeFrame: relRect
            ))
        }

        return Workspace(name: name, entries: entries)
    }

    // MARK: - Restore

    /// Restore a workspace by moving/resizing all matching windows.
    static func restore(_ workspace: Workspace) {
        guard AccessibilityChecker.isGranted else { return }
        let primaryHeight = NSScreen.screens[0].frame.height

        for entry in workspace.entries {
            guard let screen = NSScreen.screens.first(where: { $0.localizedName == entry.screenName }) else { continue }
            let vf = screen.visibleFrame
            let targetNS = entry.relativeFrame.frame(in: vf)

            // Find the running app and its window
            let apps = NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier == entry.bundleID }
            for app in apps {
                let appElement = AXUIElementCreateApplication(app.processIdentifier)
                var windowsRef: AnyObject?
                guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
                      let windows = windowsRef as? [AXUIElement] else { continue }

                for window in windows {
                    var titleRef: AnyObject?
                    let windowTitle: String
                    if AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef) == .success,
                       let t = titleRef as? String {
                        windowTitle = t
                    } else {
                        windowTitle = ""
                    }

                    if entry.windowTitle.isEmpty || windowTitle == entry.windowTitle || windowTitle.contains(entry.windowTitle) {
                        var pos = CGPoint(x: targetNS.origin.x, y: primaryHeight - targetNS.origin.y - targetNS.height)
                        if let val = AXValueCreate(.cgPoint, &pos) {
                            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, val)
                        }
                        var size = CGSize(width: targetNS.width, height: targetNS.height)
                        if let val = AXValueCreate(.cgSize, &size) {
                            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, val)
                        }
                        break
                    }
                }
            }
        }
    }
}
