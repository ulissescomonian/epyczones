import CoreGraphics
import XCTest
@testable import EpycZones

/// `frameReachedOrAdvanced` decides whether a post-drag snap succeeded for
/// windows that cannot reach the requested frame exactly.
final class PostDragProgressTests: XCTestCase {
    private let dropped = CGRect(x: 0, y: 0, width: 800, height: 600)
    private let target = CGRect(x: 1000, y: 0, width: 400, height: 600)

    func testReachingTheTargetWithinToleranceSucceeds() {
        let actual = CGRect(x: 999, y: 1, width: 401, height: 600)
        XCTAssertTrue(WindowManager.frameReachedOrAdvanced(from: dropped, to: actual, toward: target))
    }

    func testClampedSizeThatMovedTowardTheTargetSucceeds() {
        // The app enforces a 500 pt minimum width but did move and shrink.
        let actual = CGRect(x: 1000, y: 0, width: 500, height: 600)
        XCTAssertTrue(WindowManager.frameReachedOrAdvanced(from: dropped, to: actual, toward: target))
    }

    func testAWindowThatDidNotMoveFails() {
        XCTAssertFalse(WindowManager.frameReachedOrAdvanced(from: dropped, to: dropped, toward: target))
    }

    func testMovingAwayFromTheTargetFails() {
        let actual = CGRect(x: -200, y: 0, width: 800, height: 600)
        XCTAssertFalse(WindowManager.frameReachedOrAdvanced(from: dropped, to: actual, toward: target))
    }
}
