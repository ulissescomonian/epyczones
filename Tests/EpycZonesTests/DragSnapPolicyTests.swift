import XCTest
@testable import EpycZones

final class DragSnapPolicyTests: XCTestCase {
    private func mode(
        moving: Bool,
        zoneKey: Bool = false,
        suppressed: Bool = false,
        edgeSnap: Bool = true
    ) -> DragSnapMode {
        DragSnapPolicy.mode(
            windowIsMoving: moving,
            zoneKeyHeld: zoneKey,
            suppressed: suppressed,
            edgeSnapEnabled: edgeSnap
        )
    }

    /// Zone key (Shift by default) + drag that selects text, files or a shape: the window stays put.
    func testShiftWithoutWindowMovementNeverShowsZones() {
        XCTAssertEqual(mode(moving: false, zoneKey: true), .none)
    }

    func testShiftWhileMovingAWindowShowsZones() {
        XCTAssertEqual(mode(moving: true, zoneKey: true), .zones)
    }

    func testPlainWindowDragUsesEdgeSnapWhenEnabled() {
        XCTAssertEqual(mode(moving: true), .edge)
        XCTAssertEqual(mode(moving: true, edgeSnap: false), .none)
    }

    func testPlainDragWithoutWindowMovementDoesNothing() {
        XCTAssertEqual(mode(moving: false), .none)
    }

    func testEscapeSuppressesEverySnap() {
        XCTAssertEqual(mode(moving: true, zoneKey: true, suppressed: true), .none)
        XCTAssertEqual(mode(moving: true, suppressed: true), .none)
    }
}
