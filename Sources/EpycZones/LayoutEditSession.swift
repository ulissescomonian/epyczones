import Foundation
import Observation

/// One pass of editing a layout. Every change stays in `draft` until the
/// window saves it; Cancel drops it. Undo and redo step through the zone
/// changes made in this session.
@Observable
@MainActor
final class LayoutEditSession {
    private(set) var draft: Layout
    /// The draft as the session began, to tell whether anything changed.
    private let initial: Layout
    /// True when saving creates the layout: a new one or a template's copy.
    let isNew: Bool
    /// The template this draft copies, when it does.
    let template: Layout?
    /// Where saving applies the layout, for layouts that do not exist yet.
    let applyOnSave: LayoutStore.Target?
    /// The display whose proportions the canvas has.
    let display: DisplayInfo

    var selection: UUID?
    var snapsToGrid = true

    private struct Snapshot: Equatable {
        var zones: [Zone]
        var selection: UUID?
    }

    private var undoStack: [Snapshot] = []
    private var redoStack: [Snapshot] = []
    /// The state before the drag in progress, recorded as one step at its end.
    private var interactionStart: Snapshot?

    /// Edits `layout`, or a new copy of it when it is a template.
    init(editing layout: Layout, copyName: String? = nil, display: DisplayInfo, applyOnSave: LayoutStore.Target?) {
        let start: Layout
        if layout.isTemplate {
            start = Layout(
                name: copyName ?? layout.name,
                zones: layout.zones.map { Zone(rect: $0.rect, name: $0.name) }
            )
            template = layout
            isNew = true
            self.applyOnSave = applyOnSave
        } else {
            start = layout
            template = nil
            isNew = false
            self.applyOnSave = nil
        }
        draft = start
        initial = start
        self.display = display
        selection = start.zones.first?.id
    }

    /// Creates `layout`, which no store holds yet.
    init(creating layout: Layout, display: DisplayInfo, applyOnSave: LayoutStore.Target?) {
        draft = layout
        initial = layout
        template = nil
        isNew = true
        self.applyOnSave = applyOnSave
        self.display = display
        selection = layout.zones.first?.id
    }

    var hasChanges: Bool { draft != initial }

    var name: String {
        get { draft.name }
        set { draft.name = newValue }
    }

    var zones: [Zone] { draft.zones }

    var selectedIndex: Int? {
        draft.zones.firstIndex { $0.id == selection }
    }

    var issues: [LayoutGeometry.Issue] {
        LayoutGeometry.issues(in: draft.zones)
    }

    // MARK: - History

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    private var snapshot: Snapshot {
        Snapshot(zones: draft.zones, selection: selection)
    }

    /// Puts back the zones of `snapshot`. Names are typed text outside the
    /// history, so each zone keeps the name it has now.
    private func restore(_ snapshot: Snapshot) {
        let names = Dictionary(draft.zones.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        draft.zones = snapshot.zones.map { zone in
            var zone = zone
            if let name = names[zone.id] { zone.name = name }
            return zone
        }
        selection = snapshot.selection
    }

    /// Applies one change to the zones as a single undo step.
    func perform(_ change: (inout [Zone]) -> Void) {
        let before = snapshot
        var zones = draft.zones
        change(&zones)
        guard zones != draft.zones else { return }
        undoStack.append(before)
        redoStack.removeAll()
        draft.zones = zones
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(snapshot)
        restore(previous)
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(snapshot)
        restore(next)
    }

    /// Marks the start of a drag; its changes become one undo step.
    func beginInteraction() {
        if interactionStart == nil {
            interactionStart = snapshot
        }
    }

    /// Shows the zones of a drag in progress without recording a step.
    func updateInteraction(_ zones: [Zone]) {
        draft.zones = zones
    }

    func endInteraction() {
        defer { interactionStart = nil }
        guard let start = interactionStart, start.zones != draft.zones else { return }
        undoStack.append(start)
        redoStack.removeAll()
    }

    // MARK: - Commands

    func split(_ zoneID: UUID, by orientation: LayoutGeometry.Orientation) {
        guard let result = LayoutGeometry.split(draft.zones, zoneID: zoneID, by: orientation) else { return }
        perform { $0 = result.zones }
        selection = zoneID
    }

    func merge(_ zoneID: UUID, with otherID: UUID) {
        guard let merged = LayoutGeometry.merge(draft.zones, zoneID: zoneID, with: otherID) else { return }
        let survivor = draft.zones.firstIndex { $0.id == zoneID }.flatMap { a in
            draft.zones.firstIndex { $0.id == otherID }.map { b in draft.zones[min(a, b)].id }
        }
        perform { $0 = merged }
        selection = survivor
    }

    /// Adds a free zone in the middle of the display, over the others.
    func addZone() {
        let zone = Zone(rect: RelativeRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5))
        perform { $0.append(zone) }
        selection = zone.id
    }

    func delete(_ zoneID: UUID) {
        guard let index = draft.zones.firstIndex(where: { $0.id == zoneID }) else { return }
        perform { $0.remove(at: index) }
        let remaining = draft.zones
        selection = remaining.isEmpty ? nil : remaining[min(index, remaining.count - 1)].id
    }

    /// Gives a zone another number, shifting the zones in between.
    func renumber(_ zoneID: UUID, to number: Int) {
        guard let index = draft.zones.firstIndex(where: { $0.id == zoneID }),
              (1...draft.zones.count).contains(number), number - 1 != index else { return }
        perform { zones in
            let zone = zones.remove(at: index)
            zones.insert(zone, at: number - 1)
        }
    }

    func moveZones(fromOffsets source: IndexSet, toOffset destination: Int) {
        perform { $0.move(fromOffsets: source, toOffset: destination) }
    }

    func sortByPosition() {
        perform { $0 = LayoutGeometry.sortedByPosition($0) }
    }

    /// Sets a zone's rect from typed values, kept inside the display.
    func setRect(_ rect: RelativeRect, of zoneID: UUID) {
        var clamped = rect
        clamped.width = min(max(LayoutGeometry.minimumSpan, rect.width), 1)
        clamped.height = min(max(LayoutGeometry.minimumSpan, rect.height), 1)
        clamped.x = min(max(0, rect.x), 1 - clamped.width)
        clamped.y = min(max(0, rect.y), 1 - clamped.height)
        perform { zones in
            guard let index = zones.firstIndex(where: { $0.id == zoneID }) else { return }
            zones[index].rect = clamped
        }
    }

    /// Renames a zone as the name is typed. Like the layout name, it is not
    /// an undo step: the text field undoes its own typing.
    func setName(_ name: String, of zoneID: UUID) {
        guard let index = draft.zones.firstIndex(where: { $0.id == zoneID }) else { return }
        draft.zones[index].name = name
    }

    /// The draft as it is saved: names without stray spaces.
    var finishedLayout: Layout {
        var layout = draft
        layout.name = layout.name.trimmingCharacters(in: .whitespaces)
        for index in layout.zones.indices {
            layout.zones[index].name = layout.zones[index].name.trimmingCharacters(in: .whitespaces)
        }
        return layout
    }

    /// Moves the selected zone one grid step, or 1% without the grid. With
    /// `resizing`, the right or bottom edge moves instead.
    func nudgeSelection(dx: Int, dy: Int, resizing: Bool) {
        guard let index = selectedIndex else { return }
        let step = snapsToGrid ? LayoutGeometry.gridStep : 0.01
        let rect = draft.zones[index].rect
        let moved = resizing
            ? LayoutGeometry.resize(rect, edges: [.right, .bottom], dx: Double(dx) * step, dy: Double(dy) * step, grid: snapsToGrid)
            : LayoutGeometry.move(rect, dx: Double(dx) * step, dy: Double(dy) * step, grid: snapsToGrid)
        perform { $0[index].rect = moved }
    }

    /// Selects the next zone by number, wrapping around.
    func selectNext(backward: Bool = false) {
        guard !draft.zones.isEmpty else { return }
        let count = draft.zones.count
        guard let index = selectedIndex else {
            selection = draft.zones[backward ? count - 1 : 0].id
            return
        }
        selection = draft.zones[(index + (backward ? count - 1 : 1)) % count].id
    }
}
