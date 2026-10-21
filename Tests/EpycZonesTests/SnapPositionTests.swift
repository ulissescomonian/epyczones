import CoreGraphics
import XCTest
@testable import EpycZones

final class SnapPositionTests: XCTestCase {
    /// A visible frame that does not start at the origin, as on a secondary display.
    private let area = CGRect(x: 100, y: 50, width: 1000, height: 800)

    func testHalvesSplitTheAreaInNSScreenCoordinates() {
        assertFrame(SnapPosition.leftHalf.frame(in: area), CGRect(x: 100, y: 50, width: 500, height: 800))
        assertFrame(SnapPosition.rightHalf.frame(in: area), CGRect(x: 600, y: 50, width: 500, height: 800))
        // Bottom-left origin: the top half starts halfway up.
        assertFrame(SnapPosition.topHalf.frame(in: area), CGRect(x: 100, y: 450, width: 1000, height: 400))
        assertFrame(SnapPosition.bottomHalf.frame(in: area), CGRect(x: 100, y: 50, width: 1000, height: 400))
    }

    func testThirdsAndTwoThirdsTileTheWidth() {
        let third = 1000.0 / 3.0
        assertFrame(SnapPosition.firstThird.frame(in: area), CGRect(x: 100, y: 50, width: third, height: 800))
        assertFrame(SnapPosition.centerThird.frame(in: area), CGRect(x: 100 + third, y: 50, width: third, height: 800))
        assertFrame(SnapPosition.lastThird.frame(in: area), CGRect(x: 100 + 2 * third, y: 50, width: third, height: 800))
        assertFrame(SnapPosition.lastTwoThirds.frame(in: area), CGRect(x: 100 + third, y: 50, width: 2 * third, height: 800))
    }

    func testQuartersUseTheMatchingCorner() {
        assertFrame(SnapPosition.topLeftQuarter.frame(in: area), CGRect(x: 100, y: 450, width: 500, height: 400))
        assertFrame(SnapPosition.bottomRightQuarter.frame(in: area), CGRect(x: 600, y: 50, width: 500, height: 400))
    }

    func testEveryPositionStaysInsideTheArea() {
        for position in SnapPosition.allCases {
            let frame = position.frame(in: area)
            XCTAssertTrue(
                area.insetBy(dx: -1e-9, dy: -1e-9).contains(frame),
                "\(position) leaves the visible frame: \(frame)"
            )
        }
    }

    /// Monitor flow relies on arrival positions mirroring the departure edge.
    func testArrivalPositionMirrorsEveryFlowingPosition() {
        for position in SnapPosition.allCases where position.flowDirection != .none {
            let arrival = position.arrivalPosition
            XCTAssertEqual(arrival.arrivalPosition, position, "\(position) does not round-trip")
            XCTAssertEqual(arrival.flowDirection, opposite(of: position.flowDirection), "\(position)")
        }
    }

    // MARK: - Helpers

    private func opposite(of direction: WindowManager.FlowDirection) -> WindowManager.FlowDirection {
        switch direction {
        case .left: return .right
        case .right: return .left
        case .up: return .down
        case .down: return .up
        case .none: return .none
        }
    }

    private func assertFrame(_ actual: CGRect, _ expected: CGRect, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.origin.x, expected.origin.x, accuracy: 1e-9, file: file, line: line)
        XCTAssertEqual(actual.origin.y, expected.origin.y, accuracy: 1e-9, file: file, line: line)
        XCTAssertEqual(actual.width, expected.width, accuracy: 1e-9, file: file, line: line)
        XCTAssertEqual(actual.height, expected.height, accuracy: 1e-9, file: file, line: line)
    }
}
