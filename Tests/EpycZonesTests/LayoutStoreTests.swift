import XCTest
@testable import EpycZones

@MainActor
final class LayoutStoreTests: XCTestCase {
    private let grid = Layout(name: "Grid 2×2", zones: Layout.template(.grid).zones)
    private let rows = Layout(name: "2 Rows", zones: Layout.template(.twoRows).zones)

    func testUniqueNamesCountUpFromTwo() {
        XCTAssertEqual(LayoutStore.uniqueName("Coding", among: ["Writing"]), "Coding")
        XCTAssertEqual(LayoutStore.uniqueName("Coding", among: ["Coding"]), "Coding 2")
        XCTAssertEqual(LayoutStore.uniqueName("Coding", among: ["Coding", "Coding 2"]), "Coding 3")
    }

    func testACopyHasNewIdentifiersAndItsOwnName() {
        let store = LayoutStore.inMemory(layouts: [grid], defaultLayoutID: nil)
        let copy = store.copy(of: grid)
        XCTAssertNotEqual(copy.id, grid.id)
        XCTAssertTrue(Set(copy.zones.map(\.id)).isDisjoint(with: grid.zones.map(\.id)))
        XCTAssertEqual(copy.zones.map(\.rect), grid.zones.map(\.rect))
        XCTAssertEqual(copy.name, "Grid 2×2 Copy")
        store.save(copy)
        XCTAssertEqual(store.copy(of: grid).name, "Grid 2×2 Copy 2")
    }

    func testSavingReplacesALayoutWithTheSameIdentifier() {
        let store = LayoutStore.inMemory(layouts: [grid, rows], defaultLayoutID: nil)
        var edited = grid
        edited.name = "Main"
        store.save(edited)
        XCTAssertEqual(store.layouts.map(\.name), ["Main", "2 Rows"])
        store.save(store.blankLayout())
        XCTAssertEqual(store.layouts.count, 3)
        XCTAssertEqual(store.layouts[2].zones.map(\.rect), [.full])
    }

    func testTemplatesAreUsedWithoutBeingCopied() {
        let store = LayoutStore.inMemory(layouts: [], defaultLayoutID: nil)
        store.assign(Layout.template(.threeColumns).id, to: .display("uuid-4k"))
        XCTAssertEqual(store.layouts, [])
        XCTAssertEqual(store.resolution(forDisplay: "uuid-4k", name: "LG HDR 4K").layout, Layout.template(.threeColumns))
        XCTAssertEqual(store.defaultLayout, LayoutStore.fallbackLayout)
    }

    func testUsageListsDisplaysSpacesAndTheDefault() {
        let store = LayoutStore.inMemory(
            layouts: [grid, rows],
            defaultLayoutID: rows.id,
            displayLayouts: ["uuid-left": rows.id, "uuid-right": rows.id, "uuid-4k": grid.id],
            spaceLayouts: ["space-1": rows.id],
            displayNames: ["uuid-left": "LG ULTRAWIDE (1)", "uuid-right": "LG ULTRAWIDE (2)"]
        )
        let usage = store.usage(of: rows.id)
        XCTAssertEqual(usage.displays, ["LG ULTRAWIDE (1)", "LG ULTRAWIDE (2)"])
        XCTAssertEqual(usage.spaces, 1)
        XCTAssertTrue(usage.isDefault)
        XCTAssertTrue(store.usage(of: Layout.template(.threeRows).id).isEmpty)
    }

    func testDeletingALayoutClearsWhereItWasUsed() {
        let store = LayoutStore.inMemory(
            layouts: [grid, rows],
            defaultLayoutID: grid.id,
            displayLayouts: ["uuid-4k": grid.id, "uuid-left": rows.id],
            spaceLayouts: ["space-1": grid.id]
        )
        store.deleteLayout(id: grid.id)
        XCTAssertEqual(store.displayLayouts, ["uuid-left": rows.id])
        XCTAssertEqual(store.spaceLayouts, [:])
        XCTAssertEqual(store.defaultLayoutID, rows.id)
    }

    func testDisconnectedDisplaysCanBeForgotten() throws {
        let store = LayoutStore.inMemory(
            layouts: [rows],
            defaultLayoutID: nil,
            displayLayouts: ["uuid-gone": rows.id],
            displayNames: ["uuid-gone": "ARZOPA (1)"]
        )
        let gone = try XCTUnwrap(store.disconnectedDisplays(connected: []).first)
        XCTAssertEqual(gone.name, "ARZOPA (1)")
        XCTAssertEqual(gone.layout, rows)
        XCTAssertTrue(store.disconnectedDisplays(connected: ["uuid-gone"]).isEmpty)

        store.forget(gone)
        XCTAssertNil(store.displayLayouts["uuid-gone"])
        XCTAssertTrue(store.disconnectedDisplays(connected: []).isEmpty)
    }

    func testTheWelcomeSuggestsATemplateThatSuitsEachDisplay() {
        func display(_ width: CGFloat, _ height: CGFloat) -> DisplayInfo {
            DisplayInfo(
                id: "d", name: "Display",
                frame: CGRect(x: 0, y: 0, width: width, height: height),
                visibleFrame: CGRect(x: 0, y: 0, width: width, height: height - 30),
                backingScale: 1, isPrimary: false
            )
        }
        XCTAssertEqual(LayoutTemplate.suggested(for: display(1080, 2560)), .twoRows)
        XCTAssertEqual(LayoutTemplate.suggested(for: display(3440, 1440)), .threeColumns)
        XCTAssertEqual(LayoutTemplate.suggested(for: display(3840, 2160)), .twoColumns)
    }
}
