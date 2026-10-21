import ApplicationServices
import AppKit
import Observation
import OSLog

@MainActor
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

    static let privacySettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    )!

    /// Adds EpycZones to the Accessibility list and opens it there.
    static func openPrivacySettings() {
        requestAccess()
        NSWorkspace.shared.open(privacySettingsURL)
    }

    /// Show the Accessibility prompt if permission is not granted.
    static func requestAccess() {
        // The value of kAXTrustedCheckOptionPrompt, spelled out: the imported
        // global is a mutable C variable that strict concurrency rejects.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }
}

/// Whether Accessibility is allowed, as views can observe it. The app
/// delegate refreshes it, since changes arrive from System Settings.
@Observable
@MainActor
final class AccessibilityStatus {
    static let shared = AccessibilityStatus()

    private(set) var isGranted = AccessibilityChecker.isGranted

    private init() {}

    func refresh() {
        let granted = AccessibilityChecker.isGranted
        if granted != isGranted {
            isGranted = granted
        }
    }
}
