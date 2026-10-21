import OSLog

/// Unified logging categories. Diagnostic fields such as PIDs, bundle
/// identifiers and AX error codes are interpolated with `privacy: .public` so
/// Console shows them; window titles must never be logged publicly.
enum Log {
    private static let subsystem = "com.ulisses.epyczones"

    static let accessibility = Logger(subsystem: subsystem, category: "accessibility")
    static let drag = Logger(subsystem: subsystem, category: "drag")
    static let hotKeys = Logger(subsystem: subsystem, category: "hotkeys")
    static let app = Logger(subsystem: subsystem, category: "app")
}
