import AppKit
import SwiftUI

struct WorkspacesSettingsPane: View {
    @Environment(WorkspaceStore.self) private var store
    @State private var report: WorkspaceManager.RestoreReport?
    @State private var isCapturing = false
    @State private var renaming: WorkspaceStore.Workspace?
    @State private var newName = ""
    @State private var pendingDeletion: WorkspaceStore.Workspace?

    var body: some View {
        Form {
            Section {
                if store.workspaces.isEmpty {
                    EmptyListMessage(
                        symbol: "square.stack.3d.up",
                        title: "No Workspaces Yet",
                        message: "Save the windows you have open now, then put them back in the same places with one click."
                    )
                } else {
                    ForEach(store.workspaces) { workspace in
                        WorkspaceRow(
                            workspace: workspace,
                            onRestore: { report = WorkspaceManager.restore(workspace) },
                            onRename: {
                                newName = workspace.name
                                renaming = workspace
                            },
                            onDelete: { pendingDeletion = workspace }
                        )
                    }
                }
                if let report {
                    InlineNotice(kind: report.missingApps.isEmpty ? .success : .warning, text: report.summary)
                }
            } header: {
                PaneHeader(
                    symbol: SettingsPane.workspaces.symbol,
                    color: SettingsPane.workspaces.color,
                    title: "Workspaces",
                    subtitle: "Save where your windows are and put them back with one click."
                )
            } footer: {
                HStack(alignment: .firstTextBaseline) {
                    Text("Restoring moves windows that are open. It does not open apps.")
                    Spacer()
                    Button("Save Current Windows…") { isCapturing = true }
                }
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $isCapturing) {
            WorkspaceCaptureSheet()
        }
        .alert("Rename Workspace", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $newName)
            Button("Rename") {
                let name = newName.trimmingCharacters(in: .whitespaces)
                if let workspace = renaming, !name.isEmpty {
                    store.rename(id: workspace.id, to: name)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(
            "Delete this workspace?",
            isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }),
            presenting: pendingDeletion
        ) { workspace in
            Button("Delete Workspace", role: .destructive) {
                store.delete(id: workspace.id)
            }
        } message: { workspace in
            Text("“\(workspace.name)” will be removed. Your windows stay where they are.")
        }
    }
}

// MARK: - Row

private struct WorkspaceRow: View {
    let workspace: WorkspaceStore.Workspace
    let onRestore: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void

    private var appIDs: [String] {
        var seen = Set<String>()
        return workspace.entries.map(\.bundleID).filter { seen.insert($0).inserted }
    }

    var body: some View {
        HStack(spacing: 12) {
            AppIconStack(bundleIDs: Array(appIDs.prefix(4)))
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: workspace.name)
                Text("\(workspace.entries.count) windows from \(appIDs.count) apps")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            Button("Restore", action: onRestore)
            Menu {
                Button("Rename…", action: onRename)
                Button("Delete…", role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 15))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.vertical, 2)
        .contextMenu {
            Button("Restore", action: onRestore)
            Button("Rename…", action: onRename)
            Button("Delete…", role: .destructive, action: onDelete)
        }
    }
}

/// The workspace's first app icons, slightly overlapping, each on its own
/// backdrop so they stay distinct.
private struct AppIconStack: View {
    let bundleIDs: [String]

    private static let iconSize: CGFloat = 24
    private static let step: CGFloat = 17

    var body: some View {
        HStack(spacing: Self.step - Self.iconSize) {
            ForEach(Array(bundleIDs.prefix(3).enumerated()), id: \.offset) { index, bundleID in
                Image(nsImage: AppIcons.icon(forBundleID: bundleID))
                    .resizable()
                    .frame(width: Self.iconSize, height: Self.iconSize)
                    .padding(1.5)
                    .background(
                        Circle().fill(Color(nsColor: .windowBackgroundColor))
                    )
                    .zIndex(Double(3 - index))
            }
        }
        .frame(width: 64, alignment: .leading)
    }
}

// MARK: - Capture

/// Shows the windows that would be saved and lets the user leave some out.
struct WorkspaceCaptureSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(WorkspaceStore.self) private var store
    @State private var name = ""
    @State private var entries: [WorkspaceManager.Workspace.Entry] = []
    @State private var included = Set<Int>()

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Name", text: $name, prompt: Text("Work, Writing, Review…"))
                }
                Section("Windows") {
                    if entries.isEmpty {
                        EmptyListMessage(
                            symbol: "macwindow",
                            title: "No Windows to Save",
                            message: "Open the windows you want in this workspace, then try again."
                        )
                    }
                    ForEach(groupedApps, id: \.bundleID) { group in
                        HStack(spacing: 8) {
                            Image(nsImage: AppIcons.icon(forBundleID: group.bundleID))
                                .resizable()
                                .frame(width: 20, height: 20)
                            Text(verbatim: AppIcons.name(forBundleID: group.bundleID))
                                .font(.headline)
                        }
                        ForEach(group.indices, id: \.self) { index in
                            Toggle(isOn: binding(for: index)) {
                                if entries[index].windowTitle.isEmpty {
                                    Text("Untitled Window")
                                } else {
                                    Text(verbatim: entries[index].windowTitle)
                                }
                            }
                            .padding(.leading, 28)
                        }
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Text("\(included.count) of \(entries.count) windows")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save Workspace", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(included.isEmpty)
            }
            .padding(16)
        }
        .frame(width: 540, height: 580)
        .onAppear {
            entries = WorkspaceManager.captureCurrentWorkspace(name: "").entries
            included = Set(entries.indices)
        }
    }

    private var groupedApps: [(bundleID: String, indices: [Int])] {
        var order: [String] = []
        var groups: [String: [Int]] = [:]
        for (index, entry) in entries.enumerated() {
            if groups[entry.bundleID] == nil { order.append(entry.bundleID) }
            groups[entry.bundleID, default: []].append(index)
        }
        return order.map { ($0, groups[$0] ?? []) }
    }

    private func binding(for index: Int) -> Binding<Bool> {
        Binding(
            get: { included.contains(index) },
            set: { isOn in
                if isOn { included.insert(index) } else { included.remove(index) }
            }
        )
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let finalName = trimmed.isEmpty ? String(localized: "Workspace \(store.workspaces.count + 1)") : trimmed
        let kept = entries.indices.filter(included.contains).map { entries[$0] }
        store.add(WorkspaceStore.Workspace(name: finalName, entries: kept))
        dismiss()
    }
}
