import XCTest
@testable import EpycZones

final class LayoutResolutionTests: XCTestCase {
    /// User layouts with their own identifiers, as copies of templates are.
    private let columns = Layout(name: "Columns", zones: Layout.template(.twoColumns).zones)
    private let rows = Layout(name: "Rows", zones: Layout.template(.twoRows).zones)
    private let grid = Layout(name: "Grid", zones: Layout.template(.grid).zones)

    private func resolve(
        space: String? = "space-1",
        display: String? = "display-4k",
        name: String = "LG HDR 4K",
        spaceLayouts: [String: UUID] = [:],
        displayLayouts: [String: UUID] = [:],
        legacy: [String: UUID] = [:],
        defaultID: UUID?
    ) -> LayoutStore.Resolution {
        LayoutStore.resolve(
            spaceUUID: space,
            displayUUID: display,
            screenName: name,
            library: [columns, rows, grid] + Layout.templates,
            spaceLayouts: spaceLayouts,
            displayLayouts: displayLayouts,
            legacyScreenLayouts: legacy,
            defaultLayoutID: defaultID
        )
    }

    // MARK: - Precedence

    func testSpaceAssignmentWinsOverDisplayAndDefault() {
        let result = resolve(
            spaceLayouts: ["space-1": rows.id],
            displayLayouts: ["display-4k": grid.id],
            defaultID: columns.id
        )
        XCTAssertEqual(result, LayoutStore.Resolution(layout: rows, source: .space))
    }

    func testDisplayAssignmentWinsOverDefault() {
        let result = resolve(displayLayouts: ["display-4k": grid.id], defaultID: columns.id)
        XCTAssertEqual(result, LayoutStore.Resolution(layout: grid, source: .display))
    }

    func testDisplayAssignmentWinsOverAnUnmigratedName() {
        let result = resolve(
            displayLayouts: ["display-4k": grid.id],
            legacy: ["LG HDR 4K": rows.id],
            defaultID: columns.id
        )
        XCTAssertEqual(result.layout.id, grid.id)
    }

    func testUnmigratedNameStillAppliesBeforeTheDefault() {
        let result = resolve(legacy: ["LG HDR 4K": rows.id], defaultID: columns.id)
        XCTAssertEqual(result, LayoutStore.Resolution(layout: rows, source: .display))
    }

    func testDefaultAppliesWithoutAssignments() {
        let result = resolve(space: nil, display: nil, defaultID: columns.id)
        XCTAssertEqual(result, LayoutStore.Resolution(layout: columns, source: .defaultLayout))
    }

    func testAssignmentToADeletedLayoutFallsThrough() {
        let result = resolve(
            spaceLayouts: ["space-1": UUID()],
            displayLayouts: ["display-4k": UUID()],
            defaultID: columns.id
        )
        XCTAssertEqual(result.layout.id, columns.id)
    }

    func testWithoutAnyDefaultTheFallbackTemplateApplies() {
        let result = resolve(
            spaceLayouts: ["space-2": rows.id],
            displayLayouts: ["display-portrait": grid.id],
            defaultID: nil
        )
        XCTAssertEqual(result, LayoutStore.Resolution(layout: LayoutStore.fallbackLayout, source: .defaultLayout))
    }

    func testTemplatesResolveByTheirFixedIdentifiers() {
        let template = Layout.template(.mainAndStack)
        let result = resolve(displayLayouts: ["display-4k": template.id], defaultID: nil)
        XCTAssertEqual(result, LayoutStore.Resolution(layout: template, source: .display))
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

    func testCyclingStepsThroughTheUsersLayoutsWhenThereAreSeveral() {
        XCTAssertEqual(LayoutStore.cycleCandidates(userLayouts: [columns, rows]), [columns, rows])
    }

    func testCyclingAddsTheTemplatesWhenTheUserHasFewLayouts() {
        XCTAssertEqual(LayoutStore.cycleCandidates(userLayouts: []), Layout.templates)
        XCTAssertEqual(LayoutStore.cycleCandidates(userLayouts: [grid]), [grid] + Layout.templates)
    }

    func testNextLayoutWrapsAround() {
        let layouts = [columns, rows, grid]
        XCTAssertEqual(LayoutStore.nextLayoutID(after: columns.id, in: layouts), rows.id)
        XCTAssertEqual(LayoutStore.nextLayoutID(after: grid.id, in: layouts), columns.id)
        XCTAssertEqual(LayoutStore.nextLayoutID(after: nil, in: layouts), columns.id)
        // A layout outside the cycle, such as a template, restarts it.
        XCTAssertEqual(LayoutStore.nextLayoutID(after: Layout.template(.grid).id, in: layouts), columns.id)
        XCTAssertNil(LayoutStore.nextLayoutID(after: nil, in: []))
    }
}
