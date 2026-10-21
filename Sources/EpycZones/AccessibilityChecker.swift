import ApplicationServices
import AppKit
import OSLog

enum AccessibilityChecker {
    /// Upper bound, in seconds, for each Accessibility request this process
    /// sends. AX calls run synchronously on the main thread, so the system
    /// default of 6 s lets one unresponsive app freeze drag tracking, hotkeys
    /// and snapping. Starting point; tune it against slow Electron and
    /// Chromium apps during manual validation.
    static let messagingTimeout: Float = 1.0

    static var isGranted: Bool {
        AXIsProcessTrusted()
    }

    /// Applies `messagingTimeout` globally. Setting it on the system-wide
    /// element covers every AXUIElement the process uses.
    static func configureMessagingTimeout() {
        let error = AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), messagingTimeout)
        if error != .success {
            Log.accessibility.error("Could not set AX messaging timeout error=\(error.rawValue)")
        }
    }

    /// Show the Accessibility prompt if permission is not granted.
    static func requestAccess() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }
}
