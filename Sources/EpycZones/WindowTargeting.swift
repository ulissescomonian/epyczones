import AppKit
import ApplicationServices

/// Finding the windows EpycZones acts on: the drag target, the focused
/// window, and the open windows of other apps.
extension WindowManager {

    // MARK: - Drag Target and Focus

    /// The window a drag gesture is moving: the window under the cursor,
    /// falling back to the focused window when hit-testing finds nothing
    /// usable (some app shims publish their AX tree late). Hit-testing keeps a
    /// ⌘-drag of a background window from snapping the focused one instead.
    static func windowForDrag(at point: NSPoint) -> AXUIElement? {
        if let window = window(at: point) {
            let pid = AXWindow.processID(of: window)
            AXWindow.logMessage("drag target pid=\(pid) source=hit-test", key: "drag-target-hit-\(pid)", interval: 30)
            return window
        }
        guard let focused = getFocusedWindow() else { return nil }
        let pid = AXWindow.processID(of: focused)
        AXWindow.logMessage("drag target pid=\(pid) source=focus", key: "drag-target-focus-\(pid)", interval: 30)
        return focused
    }

    /// The usable window under a point in NSScreen coordinates, found by AX
    /// hit-testing. Points over EpycZones' own windows and panels return nil,
    /// so the hit-test never asks this process about itself.
    static func window(at point: NSPoint) -> AXUIElement? {
        guard !NSApp.windows.contains(where: { $0.isVisible && $0.frame.contains(point) }) else { return nil }

        let axPoint = ScreenCoordinates.flipped(point)
        let systemWide = AXUIElementCreateSystemWide()
        var element: AXUIElement?
        let error = AXUIElementCopyElementAtPosition(
            systemWide,
            Float(axPoint.x),
            Float(axPoint.y),
            &element
        )
        guard error == .success, let element else {
            if error != .success && error != .noValue {
                AXWindow.log("hit-test window", error: error, for: systemWide)
            }
            return nil
        }

        guard AXWindow.processID(of: element) != getpid(),
              let window = containingWindow(of: element),
              AXWindow.isUsable(window) else { return nil }
        return window
    }

    /// Upper bound for the parent walk in `containingWindow(of:)`.
    private static let maxAncestorDepth = 32

    /// Walks from a hit-tested element up to the window that contains it.
    private static func containingWindow(of element: AXUIElement) -> AXUIElement? {
        if AXWindow.role(of: element) == kAXWindowRole as String { return element }

        var windowValue: AnyObject?
        if AXUIElementCopyAttributeValue(element, kAXWindowAttribute as CFString, &windowValue) == .success,
           let window = AXWindow.element(from: windowValue) {
            return window
        }

        // Elements without an AXWindow attribute: climb the parent chain.
        var current = element
        for _ in 0..<maxAncestorDepth {
            var parentValue: AnyObject?
            guard AXUIElementCopyAttributeValue(current, kAXParentAttribute as CFString, &parentValue) == .success,
                  let parent = AXWindow.element(from: parentValue) else { return nil }
            if AXWindow.role(of: parent) == kAXWindowRole as String { return parent }
            current = parent
        }
        return nil
    }

    static func getFocusedWindow() -> AXUIElement? {
        struct AppCandidate {
            let element: AXUIElement
            let pid: pid_t
            let bundleID: String?
            let source: String
        }

        var appCandidates: [AppCandidate] = []
        var seenPIDs = Set<pid_t>()

        func addApp(_ element: AXUIElement, source: String) {
            var pid: pid_t = 0
            let pidError = AXUIElementGetPid(element, &pid)
            guard pidError == .success, pid != 0, seenPIDs.insert(pid).inserted else { return }
            let bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
            appCandidates.append(AppCandidate(element: element, pid: pid, bundleID: bundleID, source: source))
        }

        let workspaceApp = NSWorkspace.shared.frontmostApplication
        let workspaceIsChromeAppShim = workspaceApp?.bundleIdentifier?
            .hasPrefix("com.google.Chrome.app.") == true

        // For Chrome PWAs, prefer the concrete workspace App Shim. During startup,
        // the system-wide AX focus may temporarily point at Chrome's browser process.
        if workspaceIsChromeAppShim, let workspaceApp {
            addApp(
                AXUIElementCreateApplication(workspaceApp.processIdentifier),
                source: "workspace-app-shim"
            )
        }

        // Ask the system-wide element first for regular apps. This preserves the AX
        // server's view of focus when it differs from NSWorkspace during activation.
        let systemWide = AXUIElementCreateSystemWide()
        var focusedApp: AnyObject?
        let focusedAppError = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedApplicationAttribute as CFString,
            &focusedApp
        )
        if focusedAppError == .success, let app = AXWindow.element(from: focusedApp) {
            addApp(app, source: "system-wide")
        } else if focusedAppError != .success {
            AXWindow.log("read focused application", error: focusedAppError, for: systemWide)
        }

        // Also consider NSWorkspace. Electron launchers can expose a different
        // process identity from the actual window-owning process.
        if !workspaceIsChromeAppShim, let workspaceApp {
            addApp(
                AXUIElementCreateApplication(workspaceApp.processIdentifier),
                source: "workspace"
            )
        }

        for app in appCandidates {
            // Reading AXRole intentionally wakes Chromium's lazy accessibility tree.
            var appRole: AnyObject?
            let roleError = AXUIElementCopyAttributeValue(
                app.element,
                kAXRoleAttribute as CFString,
                &appRole
            )
            if roleError != .success {
                AXWindow.log(
                    "initialize app accessibility",
                    error: roleError,
                    pid: app.pid,
                    bundleID: app.bundleID,
                    path: app.source
                )
            }

            var seenWindows = Set<CFHashCode>()
            let directAttributes: [(CFString, String)] = [
                (kAXFocusedWindowAttribute as CFString, "focusedWindow"),
                (kAXMainWindowAttribute as CFString, "mainWindow")
            ]

            for (attribute, path) in directAttributes {
                var value: AnyObject?
                let error = AXUIElementCopyAttributeValue(app.element, attribute, &value)
                if error == .success, let window = AXWindow.element(from: value) {
                    let hash = CFHash(window)
                    guard seenWindows.insert(hash).inserted else { continue }
                    if AXWindow.isUsable(window) {
                        AXWindow.logSelection(pid: app.pid, bundleID: app.bundleID, path: "\(app.source).\(path)")
                        return window
                    }
                } else if error != .noValue && error != .attributeUnsupported {
                    AXWindow.log(
                        "read \(path)",
                        error: error,
                        pid: app.pid,
                        bundleID: app.bundleID,
                        path: app.source
                    )
                }
            }

            var windowsValue: AnyObject?
            let windowsError = AXUIElementCopyAttributeValue(
                app.element,
                kAXWindowsAttribute as CFString,
                &windowsValue
            )
            if windowsError == .success, let rawWindows = windowsValue as? [AnyObject] {
                for rawWindow in rawWindows {
                    guard let window = AXWindow.element(from: rawWindow) else { continue }
                    let hash = CFHash(window)
                    guard seenWindows.insert(hash).inserted else { continue }
                    if AXWindow.isUsable(window) {
                        AXWindow.logSelection(pid: app.pid, bundleID: app.bundleID, path: "\(app.source).windows")
                        return window
                    }
                }
            } else if windowsError != .noValue && windowsError != .attributeUnsupported {
                AXWindow.log(
                    "read windows",
                    error: windowsError,
                    pid: app.pid,
                    bundleID: app.bundleID,
                    path: app.source
                )
            }
        }

        let identities = appCandidates.map {
            "\($0.pid):\($0.bundleID ?? "unknown")[\($0.source)]"
        }.joined(separator: ",")
        AXWindow.logMessage("no usable focused window apps=\(identities)", key: "no-window-\(identities)")
        return nil
    }

    // MARK: - Window Enumeration

    /// Standard, visible windows of a running app that can be moved and
    /// resized, in the app's AX order (front to back).
    static func usableWindows(ofProcess pid: pid_t) -> [AXUIElement] {
        var value: AnyObject?
        let app = AXUIElementCreateApplication(pid)
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let rawWindows = value as? [AnyObject] else { return [] }

        return rawWindows.compactMap { AXWindow.element(from: $0) }.filter {
            AXWindow.isStandard($0) && AXWindow.isUsable($0)
        }
    }

    /// Usable windows of every regular, visible app except EpycZones itself,
    /// optionally limited to some bundle identifiers.
    static func openAppWindows(
        includingBundleID include: (String) -> Bool = { _ in true }
    ) -> [(window: AXUIElement, bundleID: String)] {
        var result: [(window: AXUIElement, bundleID: String)] = []
        for app in NSWorkspace.shared.runningApplications
        where app.activationPolicy == .regular && !app.isHidden && app.processIdentifier != getpid() {
            guard let bundleID = app.bundleIdentifier, include(bundleID) else { continue }
            for window in usableWindows(ofProcess: app.processIdentifier) {
                result.append((window, bundleID))
            }
        }
        return result
    }

    /// The screen that contains the window's center.
    static func screenForWindow(_ window: AXUIElement) -> NSScreen? {
        guard let frame = AXWindow.frame(of: window) else { return nil }
        let center = NSPoint(x: frame.midX, y: frame.midY)
        return NSScreen.screens.first { $0.frame.contains(center) }
    }
}
