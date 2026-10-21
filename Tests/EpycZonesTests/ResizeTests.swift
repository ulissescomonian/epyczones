import CoreGraphics
import XCTest
@testable import EpycZones

/// Make Larger and Make Smaller keep the window inside its display.
final class ResizeTests: XCTestCase {
    /// The LG HDR 4K visible area in AppKit coordinates.
    private let visible = CGRect(x: 0, y: 90, width: 3840, height: 2040)

    func testGrowingAWindowAtTheEdgeStaysOnScreen() {
        // 2560 pt wide against the left edge: growing 10% used to reach x = -128.
        let frame = CGRect(x: 0, y: 90, width: 2560, height: 2040)
        let grown = WindowManager.scaled(frame, by: 1.1, within: visible)
        XCTAssertEqual(grown, CGRect(x: 0, y: 90, width: 2816, height: 2040))
    }

    func testGrowingInTheMiddleStaysCentered() {
        let frame = CGRect(x: 1000, y: 500, width: 1000, height: 800)
        let grown = WindowManager.scaled(frame, by: 1.1, within: visible)
        XCTAssertEqual(grown.midX, frame.midX, accuracy: 1e-9)
        XCTAssertEqual(grown.midY, frame.midY, accuracy: 1e-9)
        XCTAssertEqual(grown.width, 1100, accuracy: 1e-9)
    }

    func testAWindowNeverGrowsPastTheVisibleArea() {
        let grown = WindowManager.scaled(visible, by: 1.1, within: visible)
        XCTAssertEqual(grown, visible)
    }

    func testShrinkingKeepsTheCenter() {
        let frame = CGRect(x: 1000, y: 500, width: 1000, height: 800)
        let shrunk = WindowManager.scaled(frame, by: 0.9, within: visible)
        XCTAssertEqual(shrunk.midX, frame.midX, accuracy: 1e-9)
        XCTAssertEqual(shrunk.width, 900, accuracy: 1e-9)
    }
}
