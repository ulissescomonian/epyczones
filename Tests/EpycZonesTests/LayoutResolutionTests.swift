import XCTest
@testable import EpycZones

final class LayoutResolutionTests: XCTestCase {
    private let columns = Layout.twoColumns()
    private let rows = Layout.twoRows()
    private let grid = Layout.grid2x2()

    private func resolve(
        space: String? = "space-1",
        display: String? = "display-4k",
        name: String = "LG HDR 4K",
        spaceLayouts: [String: UUID] = [:],
        displayLayouts: [String: UUID] = [:],
        legacy: [String: UUID] = [:],
        defaultID: UUID?
    ) -> Layout? {
        LayoutStore.resolveLayout(
            spaceUUID: space,
            displayUUID: display,
            screenName: name,
            layouts: [columns, rows, grid],
            spaceLayouts: spaceLayouts,
            displayLayouts: displayLayouts,
            legacyScreenLayouts: legacy,
            defaultLayoutID: defaultID
        )
    }

    // MARK: - Precedence

    func testSpaceAssignmentWinsOverDisplayAndDefault() {
        let layout = resolve(
            spaceLayouts: ["space-1": rows.id],
            displayLayouts: ["display-4k": grid.id],
            defaultID: columns.id
        )
        XCTAssertEqual(layout?.id, rows.id)
    }

    func testDisplayAssignmentWinsOverDefault() {
        let layout = resolve(displayLayouts: ["display-4k": grid.id], defaultID: columns.id)
        XCTAssertEqual(layout?.id, grid.id)
    }

    func testDisplayAssignmentWinsOverAnUnmigratedName() {
        let layout = resolve(
            displayLayouts: ["display-4k": grid.id],
            legacy: ["LG HDR 4K": rows.id],
            defaultID: columns.id
        )
        XCTAssertEqual(layout?.id, grid.id)
    }

    func testUnmigratedNameStillAppliesBeforeTheDefault() {
        let layout = resolve(legacy: ["LG HDR 4K": rows.id], defaultID: columns.id)
        XCTAssertEqual(layout?.id, rows.id)
    }

    func testDefaultAppliesWithoutAssignments() {
        XCTAssertEqual(resolve(space: nil, display: nil, defaultID: columns.id)?.id, columns.id)
    }

    func testAssignmentToADeletedLayoutFallsThrough() {
        let layout = resolve(
            spaceLayouts: ["space-1": UUID()],
            displayLayouts: ["display-4k": UUID()],
            defaultID: columns.id
        )
        XCTAssertEqual(layout?.id, columns.id)
    }

    func testOtherDisplaysAndSpacesAreIgnored() {
        let layout = resolve(
            spaceLayouts: ["space-2": rows.id],
            displayLayouts: ["display-portrait": grid.id],
            defaultID: nil
        )
        XCTAssertNil(layout)
    }

    // MARK: - Migration from names

    func testConnectedDisplaysTakeOverTheirNamedAssignments() {
        let result = LayoutStore.migrateLegacyAssignments(
            ["LG ULTRAWIDE (1)": rows.id, "ARZOPA (1)": columns.id],
            into: [:],
            connectedDisplays: [(name: "LG ULTRAWIDE (1)", uuid: "uuid-left")]
        )
        XCTAssertEqual(result.displayLayouts, ["uuid-left": rows.id])
        // A display that is not connected keeps its assignment for later.
        XCTAssertEqual(result.legacy, ["ARZOPA (1)": columns.id])
    }

    func testAnExistingDisplayAssignmentIsNotOverwritten() {
        let result = LayoutStore.migrateLegacyAssignments(
            ["LG HDR 4K": rows.id],
            into: ["uuid-4k": grid.id],
            connectedDisplays: [(name: "LG HDR 4K", uuid: "uuid-4k")]
        )
        XCTAssertEqual(result.displayLayouts, ["uuid-4k": grid.id])
        XCTAssertEqual(result.legacy, [:])
    }

    // MARK: - Cycling

    func testCyclingChangesOnlyTheScopeThatDecidesTheScreen() {
        let layouts = [columns, rows, grid]
        XCTAssertEqual(
            LayoutStore.effectiveScope(
                spaceUUID: "space-1",
                displayUUID: "display-4k",
                layouts: layouts,
                spaceLayouts: [:],
                displayLayouts: ["display-4k": grid.id]
            ),
            .display("display-4k")
        )
        XCTAssertEqual(
            LayoutStore.effectiveScope(
                spaceUUID: "space-1",
                displayUUID: "display-4k",
                layouts: layouts,
                spaceLayouts: ["space-1": rows.id],
                displayLayouts: ["display-4k": grid.id]
            ),
            .space("space-1")
        )
        XCTAssertEqual(
            LayoutStore.effectiveScope(
                spaceUUID: nil,
                displayUUID: "display-4k",
                layouts: layouts,
                spaceLayouts: [:],
                displayLayouts: ["display-4k": UUID()]
            ),
            .global
        )
    }

    func testNextLayoutWrapsAround() {
        let layouts = [columns, rows, grid]
        XCTAssertEqual(LayoutStore.nextLayoutID(after: columns.id, in: layouts), rows.id)
        XCTAssertEqual(LayoutStore.nextLayoutID(after: grid.id, in: layouts), columns.id)
        XCTAssertEqual(LayoutStore.nextLayoutID(after: nil, in: layouts), columns.id)
        XCTAssertNil(LayoutStore.nextLayoutID(after: nil, in: []))
    }
}
