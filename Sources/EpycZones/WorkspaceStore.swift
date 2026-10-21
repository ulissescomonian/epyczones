import Foundation
import Observation

/// Saved workspaces, observable for the Settings window.
@MainActor
@Observable
final class WorkspaceStore {
    typealias Workspace = WorkspaceManager.Workspace

    static let shared = WorkspaceStore(persists: true)

    private(set) var workspaces: [Workspace]
    /// False keeps everything in memory, for screen renders.
    private let persists: Bool

    init(persists: Bool) {
        self.persists = persists
        workspaces = persists ? WorkspaceManager.loadAll() : []
    }

    static func inMemory(_ workspaces: [Workspace]) -> WorkspaceStore {
        let store = WorkspaceStore(persists: false)
        store.workspaces = workspaces
        return store
    }

    func add(_ workspace: Workspace) {
        workspaces.append(workspace)
        save()
    }

    func rename(id: UUID, to name: String) {
        guard let index = workspaces.firstIndex(where: { $0.id == id }) else { return }
        workspaces[index].name = name
        save()
    }

    func delete(id: UUID) {
        workspaces.removeAll { $0.id == id }
        save()
    }

    private func save() {
        guard persists else { return }
        WorkspaceManager.saveAll(workspaces)
    }
}
