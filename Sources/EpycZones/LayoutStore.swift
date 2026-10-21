import AppKit
import Foundation
import Observation

@Observable
final class LayoutStore {
    static let shared = LayoutStore()

    var layouts: [Layout] = []
    var activeLayoutID: UUID?

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

    /// Default active layout (fallback when no per-screen assignment exists).
    var activeLayout: Layout? {
        layouts.first { $0.id == activeLayoutID }
    }

    /// Active layout for a specific screen. Priority: per-space → per-display → global default.
    func activeLayout(for screen: NSScreen) -> Layout? {
        Self.resolveLayout(
            spaceUUID: SpaceDetector.shared.currentSpaceUUID(for: screen),
            displayUUID: screen.displayUUID(),
            screenName: screen.localizedName,
            layouts: layouts,
            spaceLayouts: spaceLayouts,
            displayLayouts: displayLayouts,
            legacyScreenLayouts: legacyScreenLayouts,
            defaultLayoutID: activeLayoutID
        )
    }

    /// Pure precedence rule behind `activeLayout(for:)`: per-space →
    /// per-display → not yet migrated per-name → global default. An
    /// assignment whose layout no longer exists falls through to the next level.
    static func resolveLayout(
        spaceUUID: String?,
        displayUUID: String?,
        screenName: String,
        layouts: [Layout],
        spaceLayouts: [String: UUID],
        displayLayouts: [String: UUID],
        legacyScreenLayouts: [String: UUID] = [:],
        defaultLayoutID: UUID?
    ) -> Layout? {
        func layout(_ id: UUID?) -> Layout? {
            guard let id else { return nil }
            return layouts.first { $0.id == id }
        }
        if let spaceUUID, let match = layout(spaceLayouts[spaceUUID]) { return match }
        if let displayUUID, let match = layout(displayLayouts[displayUUID]) { return match }
        if let match = layout(legacyScreenLayouts[screenName]) { return match }
        return layout(defaultLayoutID)
    }

    private init() {
        load()
        migrateLegacyAssignments()
    }

    // MARK: - Persistence

    private var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("EpycZones", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("layouts.json")
    }

    func save() {
        let model = StorageModel(
            layouts: layouts,
            activeLayoutID: activeLayoutID,
            screenLayouts: legacyScreenLayouts,
            displayLayouts: displayLayouts,
            spaceLayouts: spaceLayouts
        )
        guard let data = try? JSONEncoder().encode(model) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let model = try? JSONDecoder().decode(StorageModel.self, from: data) else { return }
        layouts = model.layouts
        activeLayoutID = model.activeLayoutID
        legacyScreenLayouts = model.screenLayouts ?? [:]
        displayLayouts = model.displayLayouts ?? [:]
        spaceLayouts = model.spaceLayouts ?? [:]
    }

    // MARK: - Display Migration

    /// Moves name-keyed assignments onto the UUIDs of the connected displays
    /// that carry those names. An existing UUID assignment wins; names with no
    /// connected display stay legacy.
    static func migrateLegacyAssignments(
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

    /// Migrates legacy assignments for the displays connected now. Called at
    /// launch and whenever the display configuration changes.
    func migrateLegacyAssignments(for screens: [NSScreen] = NSScreen.screens) {
        guard !legacyScreenLayouts.isEmpty else { return }
        let connected = screens.compactMap { screen -> (name: String, uuid: String)? in
            guard let uuid = screen.displayUUID() else { return nil }
            return (name: screen.localizedName, uuid: uuid)
        }
        let result = Self.migrateLegacyAssignments(
            legacyScreenLayouts,
            into: displayLayouts,
            connectedDisplays: connected
        )
        guard result.legacy != legacyScreenLayouts else { return }
        displayLayouts = result.displayLayouts
        legacyScreenLayouts = result.legacy
        save()
    }

    // MARK: - CRUD

    func addLayout(_ layout: Layout) {
        layouts.append(layout)
        if activeLayoutID == nil {
            activeLayoutID = layout.id
        }
        save()
    }

    func deleteLayout(id: UUID) {
        layouts.removeAll { $0.id == id }
        if activeLayoutID == id {
            activeLayoutID = layouts.first?.id
        }
        let isLive: (Dictionary<String, UUID>.Element) -> Bool = { entry in
            self.layouts.contains { $0.id == entry.value }
        }
        displayLayouts = displayLayouts.filter(isLive)
        legacyScreenLayouts = legacyScreenLayouts.filter(isLive)
        spaceLayouts = spaceLayouts.filter(isLive)
        save()
    }

    func setActive(id: UUID) {
        activeLayoutID = id
        save()
    }

    func setActive(id: UUID, forDisplay displayUUID: String) {
        displayLayouts[displayUUID] = id
        save()
    }

    func removeDisplayAssignment(for displayUUID: String) {
        displayLayouts.removeValue(forKey: displayUUID)
        save()
    }

    func setActive(id: UUID, forSpace spaceUUID: String) {
        spaceLayouts[spaceUUID] = id
        save()
    }

    func removeSpaceAssignment(for spaceUUID: String) {
        spaceLayouts.removeValue(forKey: spaceUUID)
        save()
    }

    // MARK: - Cycling

    /// Where the layout choice that applies to one screen is stored.
    enum AssignmentScope: Equatable {
        case space(String)
        case display(String)
        case global
    }

    /// The most specific scope with a live assignment for a screen, else the
    /// global default.
    static func effectiveScope(
        spaceUUID: String?,
        displayUUID: String?,
        layouts: [Layout],
        spaceLayouts: [String: UUID],
        displayLayouts: [String: UUID]
    ) -> AssignmentScope {
        let liveIDs = Set(layouts.map(\.id))
        if let spaceUUID, let id = spaceLayouts[spaceUUID], liveIDs.contains(id) {
            return .space(spaceUUID)
        }
        if let displayUUID, let id = displayLayouts[displayUUID], liveIDs.contains(id) {
            return .display(displayUUID)
        }
        return .global
    }

    /// The layout after `current` in library order, wrapping around.
    static func nextLayoutID(after current: UUID?, in layouts: [Layout]) -> UUID? {
        guard let first = layouts.first else { return nil }
        guard let current, let index = layouts.firstIndex(where: { $0.id == current }) else {
            return first.id
        }
        return layouts[(index + 1) % layouts.count].id
    }

    /// Advances the layout of `screen`, changing only the scope that decides
    /// it, so cycling one display never changes the others.
    @discardableResult
    func cycleLayout(on screen: NSScreen) -> Layout? {
        guard layouts.count > 1 else { return nil }

        let spaceUUID = SpaceDetector.shared.currentSpaceUUID(for: screen)
        let displayUUID = screen.displayUUID()
        let scope = Self.effectiveScope(
            spaceUUID: spaceUUID,
            displayUUID: displayUUID,
            layouts: layouts,
            spaceLayouts: spaceLayouts,
            displayLayouts: displayLayouts
        )
        guard let nextID = Self.nextLayoutID(after: activeLayout(for: screen)?.id, in: layouts) else {
            return nil
        }

        switch scope {
        case .space(let uuid):
            spaceLayouts[uuid] = nextID
        case .display(let uuid):
            displayLayouts[uuid] = nextID
        case .global:
            activeLayoutID = nextID
        }
        save()
        return layouts.first { $0.id == nextID }
    }

    // MARK: - Storage Model

    private struct StorageModel: Codable {
        var layouts: [Layout]
        var activeLayoutID: UUID?
        /// 1.0.x name-keyed assignments not yet migrated.
        var screenLayouts: [String: UUID]?
        var displayLayouts: [String: UUID]?
        var spaceLayouts: [String: UUID]?
    }
}
