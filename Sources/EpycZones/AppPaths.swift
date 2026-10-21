import Foundation

/// Where EpycZones keeps its JSON data.
///
/// The app uses ~/Library/Application Support/EpycZones. A test process
/// never does: it gets a private temporary folder, so running the tests or
/// rendering screens can never read, migrate or overwrite the user's layouts.
/// EPYCZONES_DATA_DIR overrides both.
enum AppPaths {
    static let dataDirectory: URL = {
        let directory: URL
        if let override = ProcessInfo.processInfo.environment["EPYCZONES_DATA_DIR"], !override.isEmpty {
            directory = URL(fileURLWithPath: override, isDirectory: true)
        } else if isRunningTests {
            directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("EpycZonesTests-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
        } else {
            directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("EpycZones", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }()

    static func file(_ name: String) -> URL {
        dataDirectory.appendingPathComponent(name)
    }

    /// XCTest is loaded only into test processes, never into the app.
    static var isRunningTests: Bool {
        NSClassFromString("XCTestCase") != nil
    }
}
