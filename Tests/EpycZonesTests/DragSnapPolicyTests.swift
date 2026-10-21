import XCTest
@testable import EpycZones

final class DragSnapPolicyTests: XCTestCase {
    private func mode(
        moving: Bool,
        shift: Bool = false,
        suppressed: Bool = false,
        edgeSnap: Bool = true
    ) -> DragSnapMode {
        DragSnapPolicy.mode(
            windowIsMoving: moving,
            shiftHeld: shift,
            suppressed: suppressed,
            edgeSnapEnabled: edgeSnap
        )
    }

    /// Shift + drag that selects text, files or a shape: the window stays put.
    func testShiftWithoutWindowMovementNeverShowsZones() {
        XCTAssertEqual(mode(moving: false, shift: true), .none)
    }

    func testShiftWhileMovingAWindowShowsZones() {
        XCTAssertEqual(mode(moving: true, shift: true), .zones)
    }

    func testPlainWindowDragUsesEdgeSnapWhenEnabled() {
        XCTAssertEqual(mode(moving: true), .edge)
        XCTAssertEqual(mode(moving: true, edgeSnap: false), .none)
    }

    func testPlainDragWithoutWindowMovementDoesNothing() {
        XCTAssertEqual(mode(moving: false), .none)
    }

    func testEscapeSuppressesEverySnap() {
        XCTAssertEqual(mode(moving: true, shift: true, suppressed: true), .none)
        XCTAssertEqual(mode(moving: true, suppressed: true), .none)
    }
}
