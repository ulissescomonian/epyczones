import CoreGraphics
import XCTest
@testable import EpycZones

/// Values from the LG HDR 4K primary display: 3840 x 2160 pt, a 30 pt menu
/// bar on top and a 90 pt Dock below.
final class ScreenCoordinatesTests: XCTestCase {
    private let primaryHeight: CGFloat = 2160

    func testVisibleAreaStartsBelowTheMenuBarInAXCoordinates() {
        let visibleNS = CGRect(x: 0, y: 90, width: 3840, height: 2040)
        XCTAssertEqual(
            ScreenCoordinates.axOrigin(of: visibleNS, primaryHeight: primaryHeight),
            CGPoint(x: 0, y: 30)
        )
    }

    func testAXPositionAndSizeConvertBackToTheSameFrame() {
        let nsFrame = CGRect(x: -1080, y: 865, width: 1080, height: 1265)
        let axOrigin = ScreenCoordinates.axOrigin(of: nsFrame, primaryHeight: primaryHeight)
        XCTAssertEqual(axOrigin, CGPoint(x: -1080, y: 30))
        XCTAssertEqual(
            ScreenCoordinates.nsFrame(axOrigin: axOrigin, size: nsFrame.size, primaryHeight: primaryHeight),
            nsFrame
        )
    }

    func testFlippingAPointTwiceReturnsIt() {
        let point = CGPoint(x: 2880, y: 540)
        let flipped = ScreenCoordinates.flipped(point, primaryHeight: primaryHeight)
        XCTAssertEqual(flipped, CGPoint(x: 2880, y: 1620))
        XCTAssertEqual(ScreenCoordinates.flipped(flipped, primaryHeight: primaryHeight), point)
    }

    func testRectsWithinToleranceAreClose() {
        let frame = CGRect(x: 0, y: 30, width: 1920, height: 2040)
        XCTAssertTrue(frame.isClose(to: CGRect(x: 1, y: 30, width: 1920, height: 2039), tolerance: 2))
        XCTAssertFalse(frame.isClose(to: CGRect(x: 0, y: 30, width: 1280, height: 2040), tolerance: 15))
    }
}
