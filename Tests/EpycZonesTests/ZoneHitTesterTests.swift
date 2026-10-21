import CoreGraphics
import XCTest
@testable import EpycZones

final class ZoneHitTesterTests: XCTestCase {
    private let threshold = 0.02

    private func hit(_ x: Double, _ y: Double, in zones: [Zone]) -> Set<Int> {
        ZoneHitTester.zoneIndices(at: CGPoint(x: x, y: y), in: zones, threshold: threshold)
    }

    func testInteriorPointSelectsOneZone() {
        let columns = Layout.template(.twoColumns).zones
        XCTAssertEqual(hit(0.25, 0.5, in: columns), [0])
        XCTAssertEqual(hit(0.75, 0.5, in: columns), [1])
    }

    func testSharedBorderSpansBothZonesFromEitherSide() {
        let columns = Layout.template(.twoColumns).zones
        XCTAssertEqual(hit(0.49, 0.5, in: columns), [0, 1])
        XCTAssertEqual(hit(0.51, 0.5, in: columns), [0, 1])
    }

    func testGridCentreSpansAllFourZones() {
        let grid = Layout.template(.grid).zones
        XCTAssertEqual(hit(0.49, 0.49, in: grid), [0, 1, 2, 3])
    }

    func testGridEdgeMidpointSpansTwoZones() {
        let grid = Layout.template(.grid).zones
        // On the vertical divider, well above the horizontal one.
        XCTAssertEqual(hit(0.49, 0.2, in: grid), [0, 1])
    }

    func testOuterScreenEdgeDoesNotAddZones() {
        let columns = Layout.template(.twoColumns).zones
        XCTAssertEqual(hit(0.005, 0.5, in: columns), [0])
    }

    func testPointOutsideEveryZoneSelectsNothing() {
        let leftOnly = [Zone(rect: RelativeRect(x: 0, y: 0, width: 0.5, height: 1))]
        XCTAssertEqual(hit(0.75, 0.5, in: leftOnly), [])
        XCTAssertEqual(hit(0.5, 0.5, in: []), [])
    }
}
