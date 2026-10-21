import XCTest
@testable import EpycZones

final class AppPathsTests: XCTestCase {
    /// Tests and screen renders must never read or migrate the user's layouts.
    func testTestsNeverUseTheRealApplicationSupportFolder() {
        let real = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("EpycZones", isDirectory: true)
        XCTAssertTrue(AppPaths.isRunningTests)
        XCTAssertNotEqual(AppPaths.dataDirectory.standardizedFileURL, real.standardizedFileURL)
        XCTAssertFalse(AppPaths.file("layouts.json").path.hasPrefix(real.path))
    }
}
