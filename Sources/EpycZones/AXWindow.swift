import AppKit
import ApplicationServices
import OSLog

/// Accessibility primitives for other apps' windows: reading and writing
/// geometry, identity and state, plus throttled diagnostics. Frames are in
/// AppKit coordinates unless a name says AX.
@MainActor
enum AXWindow {

    // MARK: - Geometry

    /// The window's top-left corner in AX coordinates.
    static func position(of window: AXUIElement) -> CGPoint? {
        var value: AnyObject?
        let error = AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &value)
        guard error == .success, let axValue = axValue(from: value), AXValueGetType(axValue) == .cgPoint else {
            return nil
        }
        var point = CGPoint.zero
        guard AXValueGetValue(axValue, .cgPoint, &point) else { return nil }
        return point
    }

    static func size(of window: AXUIElement) -> CGSize? {
        var value: AnyObject?
        let error = AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &value)
        guard error == .success, let axValue = axValue(from: value), AXValueGetType(axValue) == .cgSize else {
            return nil
        }
        var size = CGSize.zero
        guard AXValueGetValue(axValue, .cgSize, &size) else { return nil }
        return size
    }

    /// The window's frame in AppKit coordinates (bottom-left origin).
    static func frame(of window: AXUIElement) -> CGRect? {
        guard let axOrigin = position(of: window), let size = size(of: window) else { return nil }
        return ScreenCoordinates.nsFrame(axOrigin: axOrigin, size: size)
    }

    /// Moves the window's top-left corner to `point`, in AX coordinates.
    @discardableResult
    static func setPosition(of window: AXUIElement, to point: CGPoint) -> AXError {
        var p = point
        guard let value = AXValueCreate(.cgPoint, &p) else {
            log("create position value", error: .failure, for: window)
            return .failure
        }
        let error = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value)
        if error != .success {
            log("set position", error: error, for: window)
        }
        return error
    }

    @discardableResult
    static func setSize(of window: AXUIElement, to size: CGSize) -> AXError {
        var s = size
        guard let value = AXValueCreate(.cgSize, &s) else {
            log("create size value", error: .failure, for: window)
            return .failure
        }
        let error = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, value)
        if error != .success {
            log("set size", error: error, for: window)
        }
        return error
    }

    /// Writes a whole frame (AppKit coordinates) as SIZE → POSITION → SIZE,
    /// Rectangle's approach: macOS clamps sizes to fit the current display,
    /// so the first size shrinks the window before the move can be clamped,
    /// and the second corrects any limit the old position imposed.
    @discardableResult
    static func setFrame(_ nsFrame: CGRect, of window: AXUIElement) -> Bool {
        let firstSize = setSize(of: window, to: nsFrame.size)
        let position = setPosition(of: window, to: ScreenCoordinates.axOrigin(of: nsFrame))
        let finalSize = setSize(of: window, to: nsFrame.size)
        return firstSize == .success && position == .success && finalSize == .success
    }

    static func raise(_ window: AXUIElement) {
        let error = AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        if error != .success {
            log("raise window", error: error, for: window)
        }
    }

    // MARK: - Identity and State

    static func processID(of element: AXUIElement) -> pid_t {
        var pid: pid_t = 0
        _ = AXUIElementGetPid(element, &pid)
        return pid
    }

    /// The window's title as Accessibility reports it. Unlike CGWindowList
    /// titles, this needs no Screen Recording permission.
    static func title(of window: AXUIElement) -> String? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }

    static func role(of element: AXUIElement) -> String? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }

    /// A document window, as opposed to a dialog, sheet or floating panel.
    static func isStandard(_ window: AXUIElement) -> Bool {
        var subrole: AnyObject?
        AXUIElementCopyAttributeValue(window, kAXSubroleAttribute as CFString, &subrole)
        return (subrole as? String) == (kAXStandardWindowSubrole as String)
    }

    /// A window, not minimized, whose frame can be read, moved and resized.
    static func isUsable(_ window: AXUIElement) -> Bool {
        let pid = processID(of: window)

        var roleValue: AnyObject?
        let roleError = AXUIElementCopyAttributeValue(
            window,
            kAXRoleAttribute as CFString,
            &roleValue
        )
        guard roleError == .success,
              let role = roleValue as? String,
              role == (kAXWindowRole as String) else {
            if roleError != .success {
                log("validate window role", error: roleError, for: window)
            }
            return false
        }

        var minimizedValue: AnyObject?
        let minimizedError = AXUIElementCopyAttributeValue(
            window,
            kAXMinimizedAttribute as CFString,
            &minimizedValue
        )
        if minimizedError == .success, (minimizedValue as? Bool) == true {
            return false
        }
        if minimizedError != .success,
           minimizedError != .noValue,
           minimizedError != .attributeUnsupported {
            log("read minimized state", error: minimizedError, for: window)
            return false
        }

        guard position(of: window) != nil, size(of: window) != nil else {
            logMessage("rejected window pid=\(pid) reason=unreadable-frame", key: "unreadable-frame-\(pid)")
            return false
        }

        var positionSettable = DarwinBoolean(false)
        let positionError = AXUIElementIsAttributeSettable(
            window,
            kAXPositionAttribute as CFString,
            &positionSettable
        )
        guard positionError == .success, positionSettable.boolValue else {
            if positionError != .success {
                log("check position settable", error: positionError, for: window)
            }
            return false
        }

        var sizeSettable = DarwinBoolean(false)
        let sizeError = AXUIElementIsAttributeSettable(
            window,
            kAXSizeAttribute as CFString,
            &sizeSettable
        )
        guard sizeError == .success, sizeSettable.boolValue else {
            if sizeError != .success {
                log("check size settable", error: sizeError, for: window)
            }
            return false
        }

        return true
    }

    static func isChromeAppShim(pid: pid_t) -> Bool {
        NSRunningApplication(processIdentifier: pid)?.bundleIdentifier?.hasPrefix("com.google.Chrome.app.") == true
    }

    // MARK: - CF Bridging

    static func element(from value: AnyObject?) -> AXUIElement? {
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeBitCast(value, to: AXUIElement.self)
    }

    private static func axValue(from value: AnyObject?) -> AXValue? {
        guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        return unsafeBitCast(value, to: AXValue.self)
    }

    // MARK: - Enhanced User Interface

    private static let kAXEnhancedUserInterface = "AXEnhancedUserInterface" as CFString

    static func appElement(for window: AXUIElement) -> AXUIElement? {
        let pid = processID(of: window)
        guard pid != 0 else { return nil }
        return AXUIElementCreateApplication(pid)
    }

    /// Chrome PWAs use an app-shim process whose accessibility tree is enabled
    /// asynchronously. Toggling Enhanced UI while it starts can invalidate the
    /// remote window proxy, so leave that attribute untouched for app shims.
    static func managesEnhancedUI(for window: AXUIElement) -> Bool {
        var pid: pid_t = 0
        guard AXUIElementGetPid(window, &pid) == .success,
              let bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier else {
            return true
        }
        return !bundleID.hasPrefix("com.google.Chrome.app.")
    }

    /// AXEnhancedUserInterface (set by Terminal, Xcode and assistive apps such
    /// as VoiceOver) blocks programmatic resizing while it is on.
    static func isEnhancedUIEnabled(_ app: AXUIElement?) -> Bool {
        guard let app else { return false }
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(app, kAXEnhancedUserInterface, &value) == .success else { return false }
        return (value as? Bool) ?? false
    }

    static func setEnhancedUI(_ app: AXUIElement?, enabled: Bool) {
        guard let app else { return }
        let error = AXUIElementSetAttributeValue(app, kAXEnhancedUserInterface, enabled as CFBoolean)
        if error != .success {
            log("set enhanced UI=\(enabled)", error: error, for: app)
        }
    }

    // MARK: - Diagnostics

    private static var lastLogTimes: [String: TimeInterval] = [:]
    /// A plain constant; nonisolated so it can serve as a default argument.
    nonisolated private static let logThrottleInterval: TimeInterval = 5

    static func log(_ operation: String, error: AXError, for element: AXUIElement) {
        let pid = processID(of: element)
        let bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
        log(operation, error: error, pid: pid, bundleID: bundleID, path: nil)
    }

    static func log(
        _ operation: String,
        error: AXError,
        pid: pid_t,
        bundleID: String?,
        path: String?
    ) {
        let pathDescription = path.map { " path=\($0)" } ?? ""
        let message = "AX \(operation) failed error=\(error.rawValue) pid=\(pid) "
            + "bundle=\(bundleID ?? "unknown")\(pathDescription)"
        logMessage(message, key: "\(operation)-\(error.rawValue)-\(pid)-\(path ?? "")")
    }

    static func logSelection(pid: pid_t, bundleID: String?, path: String) {
        logMessage(
            "AX window selected pid=\(pid) bundle=\(bundleID ?? "unknown") path=\(path)",
            key: "selection-\(pid)-\(path)",
            interval: 30
        )
    }

    /// Logs at most once per `interval` for each `key`.
    static func logMessage(
        _ message: String,
        key: String,
        interval: TimeInterval = logThrottleInterval
    ) {
        let now = Date.timeIntervalSinceReferenceDate
        if let last = lastLogTimes[key], now - last < interval { return }
        lastLogTimes[key] = now
        // Messages carry operations, PIDs, bundle IDs and AX error codes only.
        Log.accessibility.notice("\(message, privacy: .public)")
    }
}
