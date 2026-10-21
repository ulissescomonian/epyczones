import CoreGraphics
import XCTest
@testable import EpycZones

final class RelativeRectTests: XCTestCase {
    private let screen = CGRect(x: 100, y: 50, width: 1000, height: 800)

    func testFrameFlipsTheTopLeftOriginIntoNSScreenCoordinates() {
        let topRight = RelativeRect(x: 0.5, y: 0, width: 0.5, height: 0.5)
        XCTAssertEqual(topRight.frame(in: screen), CGRect(x: 600, y: 450, width: 500, height: 400))
    }

    func testGapInsetsEverySide() {
        let topRight = RelativeRect(x: 0.5, y: 0, width: 0.5, height: 0.5)
        XCTAssertEqual(topRight.frame(in: screen, gap: 10), CGRect(x: 610, y: 460, width: 480, height: 380))
    }

    func testClampKeepsTheRectInsideTheUnitSquare() {
        var rect = RelativeRect(x: 0.8, y: -0.2, width: 0.5, height: 0.5)
        rect.clamp()
        XCTAssertEqual(rect.x, 0.5, accuracy: 1e-9)
        XCTAssertEqual(rect.y, 0, accuracy: 1e-9)
        XCTAssertLessThanOrEqual(rect.x + rect.width, 1 + 1e-9)
        XCTAssertLessThanOrEqual(rect.y + rect.height, 1 + 1e-9)
    }

    func testClampEnforcesAMinimumSize() {
        var rect = RelativeRect(x: 0.2, y: 0.2, width: 0.001, height: 0)
        rect.clamp()
        XCTAssertEqual(rect.width, 0.05, accuracy: 1e-9)
        XCTAssertEqual(rect.height, 0.05, accuracy: 1e-9)
    }

    func testSnapToGridRoundsToTheNearestDivision() {
        var rect = RelativeRect(x: 0.26, y: 0.49, width: 0.24, height: 0.51)
        rect.snapToGrid(divisions: 4)
        XCTAssertEqual(rect.x, 0.25, accuracy: 1e-9)
        XCTAssertEqual(rect.y, 0.5, accuracy: 1e-9)
        XCTAssertEqual(rect.width, 0.25, accuracy: 1e-9)
        XCTAssertEqual(rect.height, 0.5, accuracy: 1e-9)
    }

    func testRelativeFrameIsTheInverseOfFrameIn() {
        let window = CGRect(x: 350, y: 210, width: 420, height: 300)
        let relative = RelativeRect(frame: window, in: screen)
        let back = relative.frame(in: screen)
        XCTAssertEqual(back.origin.x, window.origin.x, accuracy: 1e-9)
        XCTAssertEqual(back.origin.y, window.origin.y, accuracy: 1e-9)
        XCTAssertEqual(back.width, window.width, accuracy: 1e-9)
        XCTAssertEqual(back.height, window.height, accuracy: 1e-9)
        // Top-left origin: the window's top edge is 340 pt below the screen's top.
        XCTAssertEqual(relative.y, 340.0 / 800.0, accuracy: 1e-9)
    }

    func testBoundingCoversEveryZone() {
        let grid = Layout.grid2x2().zones
        XCTAssertEqual(RelativeRect.bounding(grid), RelativeRect.full)
        XCTAssertEqual(
            RelativeRect.bounding([grid[0], grid[1]]),
            RelativeRect(x: 0, y: 0, width: 1, height: 0.5)
        )
        XCTAssertEqual(RelativeRect.bounding([]), RelativeRect.zero)
    }
}
