import AppKit
import Foundation
import Observation
import ServiceManagement

/// Global app settings, persisted to UserDefaults.
@Observable
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

    /// Launch at login.
    var launchAtLogin: Bool {
        didSet {
            UserDefaults.standard.set(launchAtLogin, forKey: "launchAtLogin")
            updateLoginItem()
        }
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

    private init() {
        let defaults = UserDefaults.standard
        // Register defaults
        defaults.register(defaults: [
            "zoneGap": 0.0,
            "animateSnap": true,
            "launchAtLogin": false,
            "edgeSnapEnabled": true,
            "edgeSnapThreshold": 30.0,
            "edgeSnapDelay": 0.2,
            "edgeSnapTopMaximize": false,
            "overlayTheme": "auto",
        ])
        self.zoneGap = defaults.double(forKey: "zoneGap")
        self.animateSnap = defaults.bool(forKey: "animateSnap")
        self.launchAtLogin = defaults.bool(forKey: "launchAtLogin")
        self.edgeSnapEnabled = defaults.bool(forKey: "edgeSnapEnabled")
        self.edgeSnapThreshold = defaults.double(forKey: "edgeSnapThreshold")
        self.edgeSnapDelay = defaults.double(forKey: "edgeSnapDelay")
        self.edgeSnapTopMaximize = defaults.bool(forKey: "edgeSnapTopMaximize")
        self.overlayTheme = defaults.string(forKey: "overlayTheme") ?? "auto"
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

    private func updateLoginItem() {
        if #available(macOS 13.0, *) {
            do {
                if launchAtLogin {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                NSLog("[EpycZones] Login item error: %@", error.localizedDescription)
            }
        }
    }
}
