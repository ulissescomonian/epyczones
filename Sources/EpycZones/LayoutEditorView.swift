import SwiftUI

struct LayoutEditorView: View {
    @Environment(LayoutStore.self) private var store
    @State private var selectedLayoutID: UUID?
    @State private var selectedZoneID: UUID?
    @State private var snapToGrid = true

    var body: some View {
        @Bindable var store = store

        NavigationSplitView {
            sidebar
        } detail: {
            if let index = store.layouts.firstIndex(where: { $0.id == selectedLayoutID }) {
                editorPane(layoutIndex: index)
            } else {
                ContentUnavailableView(
                    "No Layout Selected",
                    systemImage: "rectangle.split.3x3",
                    description: Text("Select a layout from the sidebar or create a new one.")
                )
            }
        }
        .navigationTitle("Layout Editor")
        .frame(minWidth: 780, minHeight: 500)
        .onAppear {
            if selectedLayoutID == nil {
                selectedLayoutID = store.activeLayoutID ?? store.layouts.first?.id
            }
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        @Bindable var store = store

        return List(selection: $selectedLayoutID) {
            Section("Layouts") {
                ForEach(store.layouts) { layout in
                    HStack {
                        if layout.id == store.activeLayoutID {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .imageScale(.small)
                        }
                        Text(layout.name)
                        Spacer()
                        Text("\(layout.zones.count) zones")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                    .tag(layout.id)
                    .contextMenu {
                        Button("Set as Active") {
                            store.setActive(id: layout.id)
                        }
                        Divider()
                        Button("Delete", role: .destructive) {
                            if selectedLayoutID == layout.id {
                                selectedLayoutID = nil
                            }
                            store.deleteLayout(id: layout.id)
                        }
                    }
                }
            }

            if NSScreen.screens.count > 1 {
                Section("Screens") {
                    ForEach(NSScreen.screens, id: \.localizedName) { screen in
                        let screenName = screen.localizedName
                        let currentID = store.screenLayouts[screenName]
                        HStack {
                            Image(systemName: "display")
                                .imageScale(.small)
                            Text(screenName)
                                .lineLimit(1)
                            Spacer()
                        }
                        Menu(currentID.flatMap { id in store.layouts.first { $0.id == id }?.name } ?? "Default") {
                            Button("Default") {
                                store.removeScreenAssignment(for: screenName)
                            }
                            Divider()
                            ForEach(store.layouts) { layout in
                                Button(layout.name) {
                                    store.setActive(id: layout.id, forScreen: screenName)
                                }
                            }
                        }
                        .font(.caption)
                    }
                }
            }

            spacesSection

            Section("Templates") {
                templateButton("2 Columns", layout: Layout.twoColumns())
                templateButton("3 Columns", layout: Layout.threeColumns())
                templateButton("2 Rows", layout: Layout.twoRows())
                templateButton("Grid 2x2", layout: Layout.grid2x2())
                templateButton("Priority Right", layout: Layout.priorityRight())
                templateButton("Focus Center", layout: Layout.focusCenter())
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 180)
    }

    private var spacesSection: some View {
        let spaces = SpaceDetector.shared.allSpaces()
        let currentUUID = SpaceDetector.shared.currentSpaceUUID()

        return Group {
            if !spaces.isEmpty {
                Section("Spaces") {
                    ForEach(spaces, id: \.uuid) { space in
                        let assignedID = store.spaceLayouts[space.uuid]
                        HStack {
                            Image(systemName: space.uuid == currentUUID ? "square.fill" : "square")
                                .foregroundStyle(space.uuid == currentUUID ? .green : .secondary)
                                .imageScale(.small)
                            Text("Space \(space.index)")
                                .lineLimit(1)
                            Spacer()
                        }
                        Menu(assignedID.flatMap { id in store.layouts.first { $0.id == id }?.name } ?? "Default") {
                            Button("Default") {
                                store.removeSpaceAssignment(for: space.uuid)
                            }
                            Divider()
                            ForEach(store.layouts) { layout in
                                Button(layout.name) {
                                    store.setActive(id: layout.id, forSpace: space.uuid)
                                }
                            }
                        }
                        .font(.caption)
                    }
                }
            }
        }
    }

    private func templateButton(_ title: String, layout: Layout) -> some View {
        Button {
            let newLayout = Layout(name: layout.name, zones: layout.zones)
            store.addLayout(newLayout)
            selectedLayoutID = newLayout.id
        } label: {
            Label(title, systemImage: "plus.rectangle.on.rectangle")
        }
    }

    // MARK: - Editor Pane

    private func editorPane(layoutIndex: Int) -> some View {
        @Bindable var store = store

        return VStack(spacing: 0) {
            // Toolbar
            toolbar(layoutIndex: layoutIndex)
                .padding(.horizontal)
                .padding(.vertical, 10)
                .background(.bar)

            Divider()

            // Canvas
            ZoneCanvasView(
                zones: $store.layouts[layoutIndex].zones,
                selectedZoneID: $selectedZoneID,
                snapToGrid: $snapToGrid
            )
            .padding(20)

            Divider()

            // Bottom bar
            bottomBar(layoutIndex: layoutIndex)
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.bar)
        }
        .onChange(of: store.layouts[layoutIndex].zones) {
            store.save()
        }
    }

    private func toolbar(layoutIndex: Int) -> some View {
        @Bindable var store = store

        return HStack {
            TextField("Layout Name", text: $store.layouts[layoutIndex].name)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 200)
                .onChange(of: store.layouts[layoutIndex].name) {
                    store.save()
                }

            Spacer()

            if store.layouts[layoutIndex].id == store.activeLayoutID {
                Label("Active", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.callout)
            } else {
                Button("Set Active") {
                    store.setActive(id: store.layouts[layoutIndex].id)
                }
            }
        }
    }

    private func bottomBar(layoutIndex: Int) -> some View {
        @Bindable var store = store

        return HStack {
            Button {
                let newZone = Zone(
                    rect: RelativeRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
                )
                store.layouts[layoutIndex].zones.append(newZone)
                selectedZoneID = newZone.id
                store.save()
            } label: {
                Label("Add Zone", systemImage: "plus.rectangle")
            }

            Spacer()

            Toggle("Snap to Grid", isOn: $snapToGrid)
                .toggleStyle(.checkbox)
                .font(.callout)

            Spacer()

            Text("\(store.layouts[layoutIndex].zones.count) zone(s)")
                .foregroundStyle(.secondary)
                .font(.callout)

            Spacer()

            Button(role: .destructive) {
                if let zoneID = selectedZoneID {
                    store.layouts[layoutIndex].zones.removeAll { $0.id == zoneID }
                    selectedZoneID = nil
                    store.save()
                }
            } label: {
                Label("Delete Zone", systemImage: "trash")
            }
            .disabled(selectedZoneID == nil)
        }
    }
}
