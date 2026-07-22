import ApplicationServices
import AppKit

enum AccessibilityChecker {
    static var isGranted: Bool {
        AXIsProcessTrusted()
    }

    /// Show the Accessibility prompt if permission is not granted.
    static func requestAccess() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }
}
