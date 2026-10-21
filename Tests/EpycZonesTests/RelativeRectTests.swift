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
        let grid = Layout.template(.grid).zones
        XCTAssertEqual(RelativeRect.bounding(grid), RelativeRect.full)
        XCTAssertEqual(
            RelativeRect.bounding([grid[0], grid[1]]),
            RelativeRect(x: 0, y: 0, width: 1, height: 0.5)
        )
        XCTAssertEqual(RelativeRect.bounding([]), RelativeRect.zero)
    }
}
