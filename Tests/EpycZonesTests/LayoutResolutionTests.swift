import XCTest
@testable import EpycZones

final class LayoutResolutionTests: XCTestCase {
    private let columns = Layout.twoColumns()
    private let rows = Layout.twoRows()
    private let grid = Layout.grid2x2()

    private func resolve(
        space: String? = "space-1",
        screen: String = "LG HDR 4K",
        spaceLayouts: [String: UUID] = [:],
        screenLayouts: [String: UUID] = [:],
        defaultID: UUID?
    ) -> Layout? {
        LayoutStore.resolveLayout(
            spaceUUID: space,
            screenName: screen,
            layouts: [columns, rows, grid],
            spaceLayouts: spaceLayouts,
            screenLayouts: screenLayouts,
            defaultLayoutID: defaultID
        )
    }

    func testSpaceAssignmentWinsOverScreenAndDefault() {
        let layout = resolve(
            spaceLayouts: ["space-1": rows.id],
            screenLayouts: ["LG HDR 4K": grid.id],
            defaultID: columns.id
        )
        XCTAssertEqual(layout?.id, rows.id)
    }

    func testScreenAssignmentWinsOverDefault() {
        let layout = resolve(screenLayouts: ["LG HDR 4K": grid.id], defaultID: columns.id)
        XCTAssertEqual(layout?.id, grid.id)
    }

    func testDefaultAppliesWithoutAssignments() {
        XCTAssertEqual(resolve(space: nil, defaultID: columns.id)?.id, columns.id)
    }

    func testAssignmentToADeletedLayoutFallsThrough() {
        let layout = resolve(
            spaceLayouts: ["space-1": UUID()],
            screenLayouts: ["LG HDR 4K": UUID()],
            defaultID: columns.id
        )
        XCTAssertEqual(layout?.id, columns.id)
    }

    func testOtherScreensAndSpacesAreIgnored() {
        let layout = resolve(
            spaceLayouts: ["space-2": rows.id],
            screenLayouts: ["LG ULTRAWIDE (1)": grid.id],
            defaultID: nil
        )
        XCTAssertNil(layout)
    }
}
