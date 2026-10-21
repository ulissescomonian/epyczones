import AppKit
import Foundation
import Observation

@Observable
@MainActor
final class LayoutStore {
    static let shared = LayoutStore(fileURL: AppPaths.file("layouts.json"))

    /// The user's own layouts. Built-in templates are in `Layout.templates`
    /// and never stored here.
    var layouts: [Layout] = []

    /// The layout of displays that have none of their own. Nil, or a layout
    /// that no longer exists, means `fallbackLayout`.
    var defaultLayoutID: UUID?

    /// Per-display layout assignments. Key = display UUID from
    /// `CGDisplayCreateUUIDFromDisplayID`, which survives reconnections and
    /// tells two monitors of the same model apart.
    var displayLayouts: [String: UUID] = [:]

    /// Assignments saved by 1.0.x, keyed by `NSScreen.localizedName`. Each one
    /// moves to `displayLayouts` the first time a display with that name is
    /// connected; displays not seen since keep theirs here.
    private(set) var legacyScreenLayouts: [String: UUID] = [:]

    /// Per-space layout assignments. Key = Space UUID (persistent across reboots).
    var spaceLayouts: [String: UUID] = [:]

    /// The last name of each display UUID seen connected, to list displays
    /// that are not connected now.
    private(set) var displayNames: [String: String] = [:]

    /// The default layout when none is set.
    nonisolated static var fallbackLayout: Layout { Layout.template(.twoColumns) }

    /// Every layout a display can use: the user's, then the templates.
    var library: [Layout] { layouts + Layout.templates }

    func layout(id: UUID?) -> Layout? {
        guard let id else { return nil }
        return layouts.first { $0.id == id } ?? Layout.templates.first { $0.id == id }
    }

    var defaultLayout: Layout {
        layout(id: defaultLayoutID) ?? Self.fallbackLayout
    }

    /// Where the layout of a display was decided.
    enum Source: Equatable {
        /// Set for the display's current Space.
        case space
        /// Set for the display.
        case display
        /// The default layout, for displays with none of their own.
        case defaultLayout
    }

    struct Resolution: Equatable {
        let layout: Layout
        let source: Source
    }

    /// The layout in effect on `screen` and where it comes from.
    func resolution(for screen: NSScreen) -> Resolution {
        Self.resolve(
            spaceUUID: currentSpaceUUID(for: screen),
            displayUUID: screen.displayUUID(),
            screenName: screen.localizedName,
            library: library,
            spaceLayouts: spaceLayouts,
            displayLayouts: displayLayouts,
            legacyScreenLayouts: legacyScreenLayouts,
            defaultLayoutID: defaultLayoutID
        )
    }

    /// The layout in effect on a display, connected or not.
    func resolution(forDisplay displayUUID: String, name: String) -> Resolution {
        let screen = NSScreen.screens.first { $0.displayUUID() == displayUUID }
        return Self.resolve(
            spaceUUID: screen.flatMap(currentSpaceUUID(for:)),
            displayUUID: displayUUID,
            screenName: name,
            library: library,
            spaceLayouts: spaceLayouts,
            displayLayouts: displayLayouts,
            legacyScreenLayouts: legacyScreenLayouts,
            defaultLayoutID: defaultLayoutID
        )
    }

    /// The layout in effect on `screen`, used by the overlay, shortcuts and rules.
    func layout(for screen: NSScreen) -> Layout {
        resolution(for: screen).layout
    }

    /// The screen's current Space, read only when some Space has a layout:
    /// the lookup goes through private CGS APIs on every call.
    private func currentSpaceUUID(for screen: NSScreen) -> String? {
        spaceLayouts.isEmpty ? nil : SpaceDetector.shared.currentSpaceUUID(for: screen)
    }

    /// Pure precedence rule behind `resolution(for:)`: per-space →
    /// per-display → not yet migrated per-name → default → fallback. An
    /// assignment whose layout no longer exists falls through to the next level.
    nonisolated static func resolve(
        spaceUUID: String?,
        displayUUID: String?,
        screenName: String,
        library: [Layout],
        spaceLayouts: [String: UUID],
        displayLayouts: [String: UUID],
        legacyScreenLayouts: [String: UUID] = [:],
        defaultLayoutID: UUID?
    ) -> Resolution {
        func layout(_ id: UUID?) -> Layout? {
            guard let id else { return nil }
            return library.first { $0.id == id }
        }
        if let spaceUUID, let match = layout(spaceLayouts[spaceUUID]) {
            return Resolution(layout: match, source: .space)
        }
        if let displayUUID, let match = layout(displayLayouts[displayUUID]) {
            return Resolution(layout: match, source: .display)
        }
        if let match = layout(legacyScreenLayouts[screenName]) {
            return Resolution(layout: match, source: .display)
        }
        return Resolution(layout: layout(defaultLayoutID) ?? fallbackLayout, source: .defaultLayout)
    }

    /// Where layouts persist; nil keeps them in memory, for screen renders.
    private let fileURL: URL?

    init(fileURL: URL?) {
        self.fileURL = fileURL
        load()
        noteConnectedDisplays()
    }

    /// A store that never touches disk, filled with the given state.
    static func inMemory(
        layouts: [Layout],
        defaultLayoutID: UUID?,
        displayLayouts: [String: UUID] = [:],
        spaceLayouts: [String: UUID] = [:],
        displayNames: [String: String] = [:]
    ) -> LayoutStore {
        let store = LayoutStore(fileURL: nil)
        store.layouts = layouts
        store.defaultLayoutID = defaultLayoutID
        store.displayLayouts = displayLayouts
        store.spaceLayouts = spaceLayouts
        store.displayNames.merge(displayNames) { current, _ in current }
        return store
    }

    // MARK: - Persistence

    func save() {
        guard let fileURL else { return }
        let model = StorageModel(
            layouts: layouts,
            activeLayoutID: defaultLayoutID,
            screenLayouts: legacyScreenLayouts,
            displayLayouts: displayLayouts,
            spaceLayouts: spaceLayouts,
            displayNames: displayNames
        )
        guard let data = try? JSONEncoder().encode(model) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    func load() {
        guard let fileURL, let data = try? Data(contentsOf: fileURL),
              let model = try? JSONDecoder().decode(StorageModel.self, from: data) else { return }
        layouts = model.layouts
        defaultLayoutID = model.activeLayoutID
        legacyScreenLayouts = model.screenLayouts ?? [:]
        displayLayouts = model.displayLayouts ?? [:]
        spaceLayouts = model.spaceLayouts ?? [:]
        displayNames = model.displayNames ?? [:]
    }

    // MARK: - Displays

    /// Moves name-keyed assignments onto the UUIDs of the connected displays
    /// that carry those names. An existing UUID assignment wins; names with no
    /// connected display stay legacy.
    nonisolated static func migrateLegacyAssignments(
        _ legacy: [String: UUID],
        into displayLayouts: [String: UUID],
        connectedDisplays: [(name: String, uuid: String)]
    ) -> (displayLayouts: [String: UUID], legacy: [String: UUID]) {
        var migrated = displayLayouts
        var remaining = legacy
        for display in connectedDisplays {
            guard let id = remaining.removeValue(forKey: display.name) else { continue }
            if migrated[display.uuid] == nil {
                migrated[display.uuid] = id
            }
        }
        return (migrated, remaining)
    }

    /// Remembers the names of the connected displays and migrates their
    /// legacy assignments. Called at launch and whenever the display
    /// configuration changes.
    func noteConnectedDisplays(_ screens: [NSScreen] = NSScreen.screens) {
        let connected = screens.compactMap { screen -> (name: String, uuid: String)? in
            guard let uuid = screen.displayUUID() else { return nil }
            return (name: screen.localizedName, uuid: uuid)
        }
        var changed = false
        for display in connected where displayNames[display.uuid] != display.name {
            displayNames[display.uuid] = display.name
            changed = true
        }
        if !legacyScreenLayouts.isEmpty {
            let result = Self.migrateLegacyAssignments(
                legacyScreenLayouts,
                into: displayLayouts,
                connectedDisplays: connected
            )
            if result.legacy != legacyScreenLayouts {
                displayLayouts = result.displayLayouts
                legacyScreenLayouts = result.legacy
                changed = true
            }
        }
        if changed { save() }
    }

    /// A display that has a layout of its own but is not connected.
    struct DisconnectedDisplay: Identifiable, Equatable {
        /// The display UUID, or the name of a 1.0 assignment.
        let id: String
        let name: String
        let layout: Layout?
        fileprivate let isLegacy: Bool
    }

    func disconnectedDisplays(connected: Set<String>) -> [DisconnectedDisplay] {
        let byUUID = displayLayouts.filter { !connected.contains($0.key) }.map { uuid, layoutID in
            DisconnectedDisplay(
                id: uuid,
                name: displayNames[uuid] ?? String(localized: "Unknown Display"),
                layout: layout(id: layoutID),
                isLegacy: false
            )
        }
        let byName = legacyScreenLayouts.map { name, layoutID in
            DisconnectedDisplay(id: "name:\(name)", name: name, layout: layout(id: layoutID), isLegacy: true)
        }
        return (byUUID + byName).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Drops the layout of a display that is not connected.
    func forget(_ display: DisconnectedDisplay) {
        if display.isLegacy {
            legacyScreenLayouts.removeValue(forKey: display.name)
        } else {
            displayLayouts.removeValue(forKey: display.id)
            displayNames.removeValue(forKey: display.id)
        }
        save()
    }

    // MARK: - Assignments

    enum Target: Hashable {
        case display(String)
        case space(String)
        case defaultLayout
    }

    /// Where choosing a layout for a display applies: its current Desktop
    /// when that Desktop has a layout of its own, so the choice shows at
    /// once, otherwise the display.
    func choiceTarget(forDisplay displayUUID: String) -> Target {
        if !spaceLayouts.isEmpty,
           let screen = NSScreen.screens.first(where: { $0.displayUUID() == displayUUID }),
           let space = SpaceDetector.shared.currentSpaceUUID(for: screen),
           layout(id: spaceLayouts[space]) != nil {
            return .space(space)
        }
        return .display(displayUUID)
    }

    func assign(_ layoutID: UUID, to target: Target) {
        switch target {
        case .display(let uuid): displayLayouts[uuid] = layoutID
        case .space(let uuid): spaceLayouts[uuid] = layoutID
        case .defaultLayout: defaultLayoutID = layoutID
        }
        save()
    }

    /// Removes the assignment, so the display or Space falls back to the
    /// next level.
    func clearAssignment(_ target: Target) {
        switch target {
        case .display(let uuid): displayLayouts.removeValue(forKey: uuid)
        case .space(let uuid): spaceLayouts.removeValue(forKey: uuid)
        case .defaultLayout: defaultLayoutID = nil
        }
        save()
    }

    /// Where a layout is assigned, for the delete confirmation.
    struct Usage: Equatable {
        var displays: [String] = []
        var spaces = 0
        var isDefault = false

        var isEmpty: Bool { displays.isEmpty && spaces == 0 && !isDefault }
    }

    func usage(of layoutID: UUID) -> Usage {
        var usage = Usage()
        usage.displays = displayLayouts.filter { $0.value == layoutID }
            .map { displayNames[$0.key] ?? String(localized: "Unknown Display") }
        usage.displays += legacyScreenLayouts.filter { $0.value == layoutID }.map(\.key)
        usage.displays.sort { $0.localizedStandardCompare($1) == .orderedAscending }
        usage.spaces = spaceLayouts.values.filter { $0 == layoutID }.count
        usage.isDefault = defaultLayout.id == layoutID
        return usage
    }

    // MARK: - Library

    /// Adds a layout or, when one with its identifier exists, replaces it.
    func save(_ layout: Layout) {
        if let index = layouts.firstIndex(where: { $0.id == layout.id }) {
            layouts[index] = layout
        } else {
            layouts.append(layout)
        }
        save()
    }

    /// A copy with new identifiers and a name no other layout has.
    func copy(of layout: Layout) -> Layout {
        Layout(
            name: Self.uniqueName(String(localized: "\(layout.name) Copy"), among: library.map(\.name)),
            zones: layout.zones.map { Zone(rect: $0.rect, name: $0.name) }
        )
    }

    /// A new layout with one zone over the whole display, ready to split.
    func blankLayout() -> Layout {
        Layout(
            name: Self.uniqueName(String(localized: "New Layout"), among: library.map(\.name)),
            zones: [Zone(rect: .full)]
        )
    }

    func rename(id: UUID, to name: String) {
        guard let index = layouts.firstIndex(where: { $0.id == id }) else { return }
        layouts[index].name = name
        save()
    }

    /// Deletes a layout. Displays and Spaces that used it fall back to the
    /// default; when it was the default, the first remaining layout takes over.
    func deleteLayout(id: UUID) {
        layouts.removeAll { $0.id == id }
        if defaultLayoutID == id {
            defaultLayoutID = layouts.first?.id
        }
        let isLive: (Dictionary<String, UUID>.Element) -> Bool = { entry in
            self.layout(id: entry.value) != nil
        }
        displayLayouts = displayLayouts.filter(isLive)
        legacyScreenLayouts = legacyScreenLayouts.filter(isLive)
        spaceLayouts = spaceLayouts.filter(isLive)
        save()
    }

    /// `base`, or `base 2`, `base 3`… when the name is taken.
    nonisolated static func uniqueName(_ base: String, among names: [String]) -> String {
        let taken = Set(names)
        guard taken.contains(base) else { return base }
        var number = 2
        while taken.contains("\(base) \(number)") { number += 1 }
        return "\(base) \(number)"
    }

    // MARK: - Cycling

    /// The layouts the cycle shortcut steps through: the user's own when
    /// there are two or more, otherwise those and the templates.
    nonisolated static func cycleCandidates(userLayouts: [Layout]) -> [Layout] {
        userLayouts.count >= 2 ? userLayouts : userLayouts + Layout.templates
    }

    /// The layout after `current` in `layouts`, wrapping around.
    nonisolated static func nextLayoutID(after current: UUID?, in layouts: [Layout]) -> UUID? {
        guard let first = layouts.first else { return nil }
        guard let current, let index = layouts.firstIndex(where: { $0.id == current }) else {
            return first.id
        }
        return layouts[(index + 1) % layouts.count].id
    }

    /// Advances the layout of `screen` alone: a Space or display assignment
    /// changes in place, and a display on the default gets its own, so
    /// cycling one display never changes the others.
    @discardableResult
    func cycleLayout(on screen: NSScreen) -> Layout? {
        let current = resolution(for: screen)
        guard let nextID = Self.nextLayoutID(
            after: current.layout.id,
            in: Self.cycleCandidates(userLayouts: layouts)
        ) else { return nil }

        let displayUUID = screen.displayUUID()
        switch current.source {
        case .space:
            guard let spaceUUID = currentSpaceUUID(for: screen) else { return nil }
            spaceLayouts[spaceUUID] = nextID
        case .display, .defaultLayout:
            if let displayUUID {
                displayLayouts[displayUUID] = nextID
            } else if legacyScreenLayouts[screen.localizedName] != nil {
                legacyScreenLayouts[screen.localizedName] = nextID
            } else {
                defaultLayoutID = nextID
            }
        }
        save()
        return layout(id: nextID)
    }

    // MARK: - Storage Model

    private struct StorageModel: Codable {
        var layouts: [Layout]
        /// The default layout; named for its role in 1.0.x.
        var activeLayoutID: UUID?
        /// 1.0.x name-keyed assignments not yet migrated.
        var screenLayouts: [String: UUID]?
        var displayLayouts: [String: UUID]?
        var spaceLayouts: [String: UUID]?
        var displayNames: [String: String]?
    }
}
