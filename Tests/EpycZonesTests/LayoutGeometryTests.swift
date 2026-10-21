import XCTest
@testable import EpycZones

final class LayoutGeometryTests: XCTestCase {
    private func zone(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> Zone {
        Zone(rect: RelativeRect(x: x, y: y, width: w, height: h))
    }

    private func assertRect(
        _ rect: RelativeRect?, _ x: Double, _ y: Double, _ w: Double, _ h: Double,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        guard let rect else { return XCTFail("No rect", file: file, line: line) }
        XCTAssertEqual(rect.x, x, accuracy: 1e-9, file: file, line: line)
        XCTAssertEqual(rect.y, y, accuracy: 1e-9, file: file, line: line)
        XCTAssertEqual(rect.width, w, accuracy: 1e-9, file: file, line: line)
        XCTAssertEqual(rect.height, h, accuracy: 1e-9, file: file, line: line)
    }

    // MARK: - Templates

    func testEveryTemplateTilesTheDisplayExactly() {
        for template in Layout.templates {
            XCTAssertEqual(LayoutGeometry.issues(in: template.zones), [], template.name)
        }
    }

    func testTemplateIdentifiersAreFixedAndDistinct() {
        let ids = Layout.templates.map(\.id) + Layout.templates.flatMap { $0.zones.map(\.id) }
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertEqual(Layout.template(.twoColumns).id.uuidString, "EC000001-0000-4000-8000-000000000000")
        XCTAssertEqual(Layout.template(.grid).id, LayoutTemplate.grid.layout.id)
        XCTAssertTrue(Layout.template(.threeRows).isTemplate)
        XCTAssertFalse(Layout(name: "Mine", zones: []).isTemplate)
    }

    // MARK: - Split

    func testSplittingIntoColumnsKeepsTheZoneAndAppendsTheOtherHalf() throws {
        let full = zone(0, 0, 1, 1)
        let other = zone(0, 0, 0.1, 0.1)
        let result = try XCTUnwrap(LayoutGeometry.split([full, other], zoneID: full.id, by: .vertical))
        XCTAssertEqual(result.zones.map(\.id), [full.id, other.id, result.newZoneID])
        assertRect(result.zones[0].rect, 0, 0, 0.5, 1)
        assertRect(result.zones[2].rect, 0.5, 0, 0.5, 1)
    }

    func testSplittingIntoRowsHalvesTheHeight() throws {
        let top = zone(0, 0, 1, 0.625)
        let result = try XCTUnwrap(LayoutGeometry.split([top], zoneID: top.id, by: .horizontal))
        assertRect(result.zones[0].rect, 0, 0, 1, 0.3125)
        assertRect(result.zones[1].rect, 0, 0.3125, 1, 0.3125)
    }

    func testAZoneTooNarrowToSplitStaysWhole() {
        let narrow = zone(0, 0, LayoutGeometry.minimumSpan, 1)
        XCTAssertNil(LayoutGeometry.split([narrow], zoneID: narrow.id, by: .vertical))
    }

    // MARK: - Merge

    func testOnlyNeighborsSharingAWholeEdgeCanMerge() {
        let grid = Layout.template(.grid).zones
        let neighbors = LayoutGeometry.mergeableNeighbors(of: grid[0].id, in: grid)
        XCTAssertEqual(neighbors, [
            .init(zoneID: grid[1].id, side: .right),
            .init(zoneID: grid[2].id, side: .bottom),
        ])
        XCTAssertNil(LayoutGeometry.merge(grid, zoneID: grid[0].id, with: grid[3].id))
    }

    func testMergingKeepsTheLowerNumberAndItsName() throws {
        var grid = Layout.template(.grid).zones
        grid[2].name = "Terminal"
        let merged = try XCTUnwrap(LayoutGeometry.merge(grid, zoneID: grid[2].id, with: grid[0].id))
        XCTAssertEqual(merged.map(\.id), [grid[0].id, grid[1].id, grid[3].id])
        assertRect(merged[0].rect, 0, 0, 0.5, 1)
        XCTAssertEqual(merged[0].name, "Terminal")
    }

    // MARK: - Dividers

    func testTwoColumnsShareOneFullHeightDivider() {
        let columns = Layout.template(.twoColumns).zones
        let dividers = LayoutGeometry.dividers(in: columns)
        XCTAssertEqual(dividers.count, 1)
        XCTAssertEqual(dividers[0].orientation, .vertical)
        XCTAssertEqual(dividers[0].position, 0.5, accuracy: 1e-9)
        XCTAssertEqual(dividers[0].start, 0, accuracy: 1e-9)
        XCTAssertEqual(dividers[0].end, 1, accuracy: 1e-9)
        XCTAssertEqual(dividers[0].leading, [columns[0].id])
        XCTAssertEqual(dividers[0].trailing, [columns[1].id])
    }

    func testAGridHasOneDividerPerRowAndColumnJoinedIntoLines() throws {
        let grid = Layout.template(.grid).zones
        let dividers = LayoutGeometry.dividers(in: grid)
        XCTAssertEqual(dividers.filter { $0.orientation == .vertical }.count, 2)
        XCTAssertEqual(dividers.filter { $0.orientation == .horizontal }.count, 2)

        let top = try XCTUnwrap(dividers.first { $0.orientation == .vertical && $0.start == 0 })
        XCTAssertEqual(top.zoneIDs, [grid[0].id, grid[1].id])
        let line = LayoutGeometry.line(through: top, in: grid)
        XCTAssertEqual(line.zoneIDs, Set(grid.map(\.id)))
        XCTAssertEqual(line.end, 1, accuracy: 1e-9)
    }

    func testAZoneFacingTwoZonesMakesOneDivider() throws {
        let layout = Layout.template(.mainAndStack).zones
        let vertical = try XCTUnwrap(LayoutGeometry.dividers(in: layout).first { $0.orientation == .vertical })
        XCTAssertEqual(vertical.leading, [layout[0].id])
        XCTAssertEqual(vertical.trailing, [layout[1].id, layout[2].id])
        let horizontal = try XCTUnwrap(LayoutGeometry.dividers(in: layout).first { $0.orientation == .horizontal })
        XCTAssertEqual(horizontal.start, 2.0 / 3.0, accuracy: 1e-9)
    }

    func testMovingADividerResizesBothSides() {
        let columns = Layout.template(.twoColumns).zones
        let divider = LayoutGeometry.dividers(in: columns)[0]
        let moved = LayoutGeometry.move(divider, to: 0.625, in: columns)
        assertRect(moved[0].rect, 0, 0, 0.625, 1)
        assertRect(moved[1].rect, 0.625, 0, 0.375, 1)
    }

    func testMovingTheWholeLineKeepsAGridAligned() throws {
        let grid = Layout.template(.grid).zones
        let segment = try XCTUnwrap(LayoutGeometry.dividers(in: grid).first { $0.orientation == .horizontal })
        let moved = LayoutGeometry.move(LayoutGeometry.line(through: segment, in: grid), to: 0.625, in: grid)
        XCTAssertEqual(moved.map(\.rect.height), [0.625, 0.625, 0.375, 0.375])
        XCTAssertEqual(LayoutGeometry.issues(in: moved), [])
    }

    func testADividerKeepsEachSideAtTheMinimumSpan() {
        let columns = Layout.template(.twoColumns).zones
        let divider = LayoutGeometry.dividers(in: columns)[0]
        let range = LayoutGeometry.range(of: divider, in: columns)
        XCTAssertEqual(range.lowerBound, LayoutGeometry.minimumSpan, accuracy: 1e-9)
        XCTAssertEqual(range.upperBound, 1 - LayoutGeometry.minimumSpan, accuracy: 1e-9)
        assertRect(LayoutGeometry.move(divider, to: 0.99, in: columns)[1].rect, 1 - LayoutGeometry.minimumSpan, 0, LayoutGeometry.minimumSpan, 1)
    }

    func testADividerStopsAtAZoneThatIsNotPartOfIt() throws {
        // Left zone over the full height; right side has a top zone and,
        // below a gap, a zone starting at 75%.
        let left = zone(0, 0, 0.5, 1)
        let topRight = zone(0.5, 0, 0.5, 0.5)
        let bottomRight = zone(0.75, 0.5, 0.25, 0.5)
        let zones = [left, topRight, bottomRight]
        let divider = try XCTUnwrap(LayoutGeometry.dividers(in: zones).first { $0.orientation == .vertical })
        let range = LayoutGeometry.range(of: divider, in: zones)
        XCTAssertEqual(range.upperBound, 0.75, accuracy: 1e-9)
        XCTAssertFalse(LayoutGeometry.move(divider, to: 0.9, in: zones)[0].rect.overlaps(bottomRight.rect))
    }

    // MARK: - Checks

    func testAGapIsReportedWithItsShare() {
        let zones = [zone(0, 0, 0.5, 1), zone(0.5, 0, 0.5, 0.5), zone(0.75, 0.5, 0.25, 0.5)]
        guard case .uncovered(let fraction) = LayoutGeometry.issues(in: zones).first else {
            return XCTFail("Expected a gap")
        }
        XCTAssertEqual(fraction, 0.125, accuracy: 1e-9)
        let regions = LayoutGeometry.uncoveredRegions(in: zones)
        XCTAssertEqual(regions.count, 1)
        assertRect(regions.first, 0.5, 0.5, 0.25, 0.5)
    }

    func testOverlapsEmptyLayoutsAndExtraZonesAreReported() {
        XCTAssertEqual(LayoutGeometry.issues(in: []), [.empty])
        XCTAssertEqual(LayoutGeometry.issues(in: [zone(0, 0, 1, 1), zone(0.25, 0.25, 0.5, 0.5)]), [.overlap(0, 1)])

        let strips = (0..<10).map { zone(Double($0) / 10, 0, 0.1, 1) }
        XCTAssertEqual(LayoutGeometry.issues(in: strips), [.withoutShortcut(count: 1)])
    }

    func testZonesThatOnlyTouchDoNotOverlap() {
        XCTAssertFalse(zone(0, 0, 0.5, 1).rect.overlaps(zone(0.5, 0, 0.5, 1).rect))
    }

    // MARK: - Order and Snapping

    func testSortingByPositionReadsTopToBottomThenLeftToRight() {
        let grid = Layout.template(.grid).zones
        let shuffled = [grid[3], grid[1], grid[2], grid[0]]
        XCTAssertEqual(LayoutGeometry.sortedByPosition(shuffled).map(\.id), grid.map(\.id))
    }

    func testSnappingUsesTheGridOrNearbyEdges() {
        XCTAssertEqual(LayoutGeometry.snap(0.63, grid: true), 15.0 / 24.0, accuracy: 1e-9)
        XCTAssertEqual(LayoutGeometry.snap(0.505, grid: false, edges: [0.5]), 0.5, accuracy: 1e-9)
        XCTAssertEqual(LayoutGeometry.snap(0.55, grid: false, edges: [0.5]), 0.55, accuracy: 1e-9)
    }

    func testFreeZonesStayInsideTheDisplay() {
        let rect = RelativeRect(x: 0.5, y: 0.6, width: 0.5, height: 0.4)
        assertRect(LayoutGeometry.move(rect, dx: 0.3, dy: 0.3, grid: false), 0.5, 0.6, 0.5, 0.4)
        let shrunk = LayoutGeometry.resize(rect, edges: .right, dx: -0.9, dy: 0, grid: false)
        XCTAssertEqual(shrunk.width, LayoutGeometry.minimumSpan, accuracy: 1e-9)
        let grown = LayoutGeometry.resize(rect, edges: [.left, .top], dx: -1, dy: -1, grid: true)
        assertRect(grown, 0, 0, 1, 1)
    }
}
