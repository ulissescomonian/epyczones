import AppKit
import Foundation
import Observation
import OSLog
import ServiceManagement

/// Global app settings, persisted to UserDefaults.
@Observable
@MainActor
final class AppSettings {
    static let shared = AppSettings()

    /// Gap in points between zones when snapping.
    var zoneGap: Double {
        didSet { UserDefaults.standard.set(zoneGap, forKey: "zoneGap") }
    }

    /// Whether to animate window snapping.
    var animateSnap: Bool {
        didSet { UserDefaults.standard.set(animateSnap, forKey: "animateSnap") }
    }

    /// Launch at login, read from the system's login items rather than a
    /// stored preference, so the switch shows what macOS will actually do.
    var launchAtLogin: Bool {
        didSet {
            // Also ends the correction below if it re-enters this observer.
            guard launchAtLogin != Self.loginItemIsEnabled else { return }
            updateLoginItem()
            // Show what macOS accepted, e.g. after a failed registration.
            let actual = Self.loginItemIsEnabled
            if launchAtLogin != actual {
                launchAtLogin = actual
            }
        }
    }

    /// Move open windows back to their last recorded zones when EpycZones starts.
    var restoreWindowsOnLaunch: Bool {
        didSet { UserDefaults.standard.set(restoreWindowsOnLaunch, forKey: "restoreWindowsOnLaunch") }
    }

    /// Show the layout's zones while a window is dragged with `zoneDragModifier` held.
    var zoneDragEnabled: Bool {
        didSet { UserDefaults.standard.set(zoneDragEnabled, forKey: "zoneDragEnabled") }
    }

    /// The key that reveals zones during a drag.
    var zoneDragModifier: ZoneDragModifier {
        didSet { UserDefaults.standard.set(zoneDragModifier.rawValue, forKey: "zoneDragModifier") }
    }

    /// Modifiers of the zone shortcuts 1–9. Callers reload hotkeys after changing it.
    var zoneHotKeyModifiers: ZoneShortcutModifiers {
        didSet { UserDefaults.standard.set(Int(zoneHotKeyModifiers.rawValue), forKey: "zoneHotKeyModifiers") }
    }

    /// Enable edge snapping (drag near screen edge without modifier → halves/quarters).
    var edgeSnapEnabled: Bool {
        didSet { UserDefaults.standard.set(edgeSnapEnabled, forKey: "edgeSnapEnabled") }
    }

    /// Edge snap trigger distance in points.
    var edgeSnapThreshold: Double {
        didSet { UserDefaults.standard.set(edgeSnapThreshold, forKey: "edgeSnapThreshold") }
    }

    /// Delay in seconds before edge snap triggers.
    var edgeSnapDelay: Double {
        didSet { UserDefaults.standard.set(edgeSnapDelay, forKey: "edgeSnapDelay") }
    }

    /// Edge snap ignores stretches of edge that another display continues
    /// past, so moving a window between displays never snaps it on the way.
    var edgeSnapIgnoresSharedEdges: Bool {
        didSet { UserDefaults.standard.set(edgeSnapIgnoresSharedEdges, forKey: "edgeSnapIgnoresSharedEdges") }
    }

    /// Edge snap: dragging to the top-center maximizes instead of top half.
    var edgeSnapTopMaximize: Bool {
        didSet { UserDefaults.standard.set(edgeSnapTopMaximize, forKey: "edgeSnapTopMaximize") }
    }

    /// Overlay theme: "auto", "dark", "light".
    var overlayTheme: String {
        didSet { UserDefaults.standard.set(overlayTheme, forKey: "overlayTheme") }
    }

    /// Custom hotkey bindings. Key = action name, value = key code + modifier string.
    var customHotKeys: [String: HotKeyBinding] {
        didSet {
            if let data = try? JSONEncoder().encode(customHotKeys) {
                UserDefaults.standard.set(data, forKey: "customHotKeys")
            }
        }
    }

    /// Preferences written by 1.0.x that nothing reads anymore.
    /// True once the welcome window has run, or for a copy that was already
    /// set up before it existed.
    var hasCompletedOnboarding: Bool {
        didSet { UserDefaults.standard.set(hasCompletedOnboarding, forKey: "hasCompletedOnboarding") }
    }

    private static let retiredKeys = ["hasPromptedAccessibility", "launchAtLogin"]

    private init() {
        let defaults = UserDefaults.standard
        Self.retiredKeys.forEach(defaults.removeObject(forKey:))

        // Register defaults
        defaults.register(defaults: [
            "zoneGap": 0.0,
            "animateSnap": true,
            "restoreWindowsOnLaunch": true,
            "zoneDragEnabled": true,
            "zoneDragModifier": ZoneDragModifier.shift.rawValue,
            "zoneHotKeyModifiers": Int(ZoneShortcutModifiers.default.rawValue),
            "edgeSnapEnabled": true,
            "edgeSnapThreshold": 30.0,
            "edgeSnapDelay": 0.2,
            "edgeSnapTopMaximize": false,
            "edgeSnapIgnoresSharedEdges": true,
            "overlayTheme": "auto",
        ])
        self.zoneGap = defaults.double(forKey: "zoneGap")
        self.animateSnap = defaults.bool(forKey: "animateSnap")
        self.launchAtLogin = Self.loginItemIsEnabled
        self.restoreWindowsOnLaunch = defaults.bool(forKey: "restoreWindowsOnLaunch")
        self.zoneDragEnabled = defaults.bool(forKey: "zoneDragEnabled")
        self.zoneDragModifier = defaults.string(forKey: "zoneDragModifier")
            .flatMap(ZoneDragModifier.init(rawValue:)) ?? .shift
        self.zoneHotKeyModifiers = ZoneShortcutModifiers(rawValue: UInt32(defaults.integer(forKey: "zoneHotKeyModifiers")))
            ?? .default
        self.edgeSnapEnabled = defaults.bool(forKey: "edgeSnapEnabled")
        self.edgeSnapThreshold = defaults.double(forKey: "edgeSnapThreshold")
        self.edgeSnapDelay = defaults.double(forKey: "edgeSnapDelay")
        self.edgeSnapTopMaximize = defaults.bool(forKey: "edgeSnapTopMaximize")
        self.edgeSnapIgnoresSharedEdges = defaults.bool(forKey: "edgeSnapIgnoresSharedEdges")
        self.overlayTheme = defaults.string(forKey: "overlayTheme") ?? "auto"
        self.hasCompletedOnboarding = defaults.bool(forKey: "hasCompletedOnboarding")
        if let data = defaults.data(forKey: "customHotKeys"),
           let decoded = try? JSONDecoder().decode([String: HotKeyBinding].self, from: data) {
            self.customHotKeys = decoded
        } else {
            self.customHotKeys = [:]
        }
    }

    /// Resolve whether overlay should use dark colors based on theme setting + system appearance.
    var overlayIsDark: Bool {
        switch overlayTheme {
        case "dark": return true
        case "light": return false
        default:
            // NSApp.effectiveAppearance is unreliable for accessory (menu bar) apps.
            // Use the system-level UserDefaults setting instead.
            return UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
        }
    }

    /// Registered as a login item. Awaiting the user's approval in System
    /// Settings still counts: the registration exists.
    private static var loginItemIsEnabled: Bool {
        switch SMAppService.mainApp.status {
        case .enabled, .requiresApproval:
            return true
        default:
            return false
        }
    }

    private func updateLoginItem() {
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            Log.app.error("Login item error: \(error.localizedDescription, privacy: .public)")
        }
    }
}
