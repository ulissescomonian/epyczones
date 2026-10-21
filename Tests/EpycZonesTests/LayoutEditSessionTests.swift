import XCTest
@testable import EpycZones

@MainActor
final class LayoutEditSessionTests: XCTestCase {
    private let display = DisplayInfo(
        id: "uuid-4k",
        name: "LG HDR 4K",
        frame: CGRect(x: 0, y: 0, width: 3840, height: 2160),
        visibleFrame: CGRect(x: 0, y: 90, width: 3840, height: 2040),
        backingScale: 1,
        isPrimary: true
    )

    private func session(_ layout: Layout) -> LayoutEditSession {
        LayoutEditSession(editing: layout, display: display, applyOnSave: .display("uuid-4k"))
    }

    func testEditingATemplateEditsANewCopy() {
        let template = Layout.template(.grid)
        let session = LayoutEditSession(
            editing: template,
            copyName: "Grid 2×2 Copy",
            display: display,
            applyOnSave: .display("uuid-4k")
        )
        XCTAssertTrue(session.isNew)
        XCTAssertEqual(session.template, template)
        XCTAssertEqual(session.applyOnSave, .display("uuid-4k"))
        XCTAssertNotEqual(session.draft.id, template.id)
        XCTAssertEqual(session.draft.name, "Grid 2×2 Copy")
        XCTAssertTrue(Set(session.draft.zones.map(\.id)).isDisjoint(with: template.zones.map(\.id)))
    }

    func testEditingAUserLayoutChangesItInPlace() {
        let mine = Layout(name: "Mine", zones: Layout.template(.twoRows).zones)
        let session = session(mine)
        XCTAssertFalse(session.isNew)
        XCTAssertNil(session.applyOnSave)
        XCTAssertEqual(session.draft.id, mine.id)
        XCTAssertFalse(session.hasChanges)
    }

    func testUndoAndRedoStepThroughChanges() throws {
        let session = session(Layout(name: "Mine", zones: [Zone(rect: .full)]))
        let first = try XCTUnwrap(session.selection)
        session.split(first, by: .vertical)
        XCTAssertEqual(session.zones.count, 2)
        XCTAssertTrue(session.hasChanges)

        session.undo()
        XCTAssertEqual(session.zones.map(\.rect), [.full])
        XCTAssertFalse(session.canUndo)
        session.redo()
        XCTAssertEqual(session.zones.count, 2)
        XCTAssertFalse(session.canRedo)
    }

    func testADragIsOneUndoStep() throws {
        let session = session(Layout(name: "Mine", zones: Layout.template(.twoColumns).zones))
        let divider = try XCTUnwrap(LayoutGeometry.dividers(in: session.zones).first)
        let start = session.zones
        session.beginInteraction()
        session.updateInteraction(LayoutGeometry.move(divider, to: 0.6, in: start))
        session.updateInteraction(LayoutGeometry.move(divider, to: 0.625, in: start))
        session.endInteraction()
        XCTAssertEqual(session.zones[0].rect.width, 0.625, accuracy: 1e-9)

        session.undo()
        XCTAssertEqual(session.zones, start)
        XCTAssertFalse(session.canUndo)
    }

    func testUndoKeepsNamesTypedSince() throws {
        let session = session(Layout(name: "Mine", zones: [Zone(rect: .full)]))
        let id = try XCTUnwrap(session.selection)
        session.split(id, by: .horizontal)
        session.setName("Browser", of: id)
        session.undo()
        XCTAssertEqual(session.zones.first?.name, "Browser")
    }

    func testRenumberingMovesAZoneAndItsShortcut() {
        let zones = Layout.template(.threeColumns).zones.map { Zone(rect: $0.rect) }
        let session = session(Layout(name: "Mine", zones: zones))
        session.renumber(zones[2].id, to: 1)
        XCTAssertEqual(session.zones.map(\.id), [zones[2].id, zones[0].id, zones[1].id])
    }

    func testDeletingSelectsTheNextZone() {
        let zones = Layout.template(.threeColumns).zones.map { Zone(rect: $0.rect) }
        let session = session(Layout(name: "Mine", zones: zones))
        session.delete(zones[1].id)
        XCTAssertEqual(session.selection, zones[2].id)
        session.delete(zones[2].id)
        XCTAssertEqual(session.selection, zones[0].id)
    }

    func testTheSavedLayoutHasTrimmedNames() throws {
        let session = session(Layout(name: "Mine", zones: [Zone(rect: .full)]))
        session.name = "  Coding "
        session.setName(" Editor ", of: try XCTUnwrap(session.selection))
        XCTAssertEqual(session.finishedLayout.name, "Coding")
        XCTAssertEqual(session.finishedLayout.zones[0].name, "Editor")
    }
}
