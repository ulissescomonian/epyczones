import Observation

/// Requests to show a place inside a window, made from outside it, such as
/// the menu bar asking the Layouts window for one display. The window
/// reads the request when it appears or changes, and clears it.
@Observable
@MainActor
final class AppNavigation {
    static let shared = AppNavigation()

    /// The Settings pane to show.
    var settingsPane: SettingsPane?
    /// The display, by UUID, to select in the Layouts window.
    var layoutsDisplayID: String?

    private init() {}
}
