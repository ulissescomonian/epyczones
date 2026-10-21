import AppKit
import SwiftUI

/// The Layouts window. Displays come first: the sidebar shows them as they
/// are arranged, the detail shows the selected display's layout and the
/// library to choose from, and editing a layout takes over the window until
/// it is saved or cancelled.
struct LayoutsView: View {
    @Environment(LayoutStore.self) private var store
    @State private var displays: [DisplayInfo]
    @State private var selectedDisplayID: String?
    @State private var session: LayoutEditSession?
    @State private var columnVisibility: NavigationSplitViewVisibility

    init(displays: [DisplayInfo]? = nil, selectedDisplayID: String? = nil, session: LayoutEditSession? = nil) {
        let connected = displays ?? DisplayInfo.connected()
        _displays = State(initialValue: connected)
        _selectedDisplayID = State(
            initialValue: selectedDisplayID ?? connected.first(where: \.isPrimary)?.id ?? connected.first?.id
        )
        _session = State(initialValue: session)
        _columnVisibility = State(initialValue: session == nil ? .all : .detailOnly)
    }

    private var selectedDisplay: DisplayInfo? {
        displays.first { $0.id == selectedDisplayID }
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            LayoutsSidebar(displays: displays, selection: $selectedDisplayID)
                .disabled(session != nil)
                .navigationSplitViewColumnWidth(min: 240, ideal: 260, max: 320)
        } detail: {
            if let session {
                LayoutEditorView(session: session) { save in
                    finishEditing(session, save: save)
                }
            } else if let display = selectedDisplay {
                DisplayLayoutsView(display: display) { newSession in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        session = newSession
                        columnVisibility = .detailOnly
                    }
                }
                .id(display.id)
            } else {
                ContentUnavailableView(
                    "No Displays",
                    systemImage: "display",
                    description: Text("Connect a display to arrange its zones.")
                )
            }
        }
        .frame(minWidth: 920, minHeight: 620)
        .onChange(of: AppNavigation.shared.layoutsDisplayID, initial: true) { _, id in
            guard let id else { return }
            if displays.contains(where: { $0.id == id }) {
                selectedDisplayID = id
            }
            AppNavigation.shared.layoutsDisplayID = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            displays = DisplayInfo.connected()
            if !displays.contains(where: { $0.id == selectedDisplayID }) {
                selectedDisplayID = displays.first?.id
            }
        }
    }

    private func finishEditing(_ finished: LayoutEditSession, save: Bool) {
        if save {
            let layout = finished.finishedLayout
            store.save(layout)
            if let target = finished.applyOnSave {
                store.assign(layout.id, to: target)
            }
        }
        withAnimation(.easeInOut(duration: 0.2)) {
            session = nil
            columnVisibility = .all
        }
    }
}

// MARK: - Sidebar

private struct LayoutsSidebar: View {
    @Environment(LayoutStore.self) private var store
    let displays: [DisplayInfo]
    @Binding var selection: String?
    @State private var pendingForget: LayoutStore.DisconnectedDisplay?

    var body: some View {
        let disconnected = store.disconnectedDisplays(connected: Set(displays.map(\.id)))

        List(selection: $selection) {
            Section {
                DisplayArrangementMap(displays: displays, selection: $selection)
                    .frame(height: 112)
                    .padding(.vertical, 6)
                    .selectionDisabled()
            }

            Section("Displays") {
                ForEach(displays) { display in
                    DisplaySidebarRow(
                        display: display,
                        resolution: store.resolution(forDisplay: display.id, name: display.name)
                    )
                    .tag(display.id)
                }
            }

            if !disconnected.isEmpty {
                Section("Not Connected") {
                    ForEach(disconnected) { display in
                        DisconnectedDisplayRow(display: display) {
                            pendingForget = display
                        }
                        .selectionDisabled()
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            DefaultLayoutBar()
        }
        .confirmationDialog(
            "Forget this display?",
            isPresented: Binding(get: { pendingForget != nil }, set: { if !$0 { pendingForget = nil } }),
            presenting: pendingForget
        ) { display in
            Button("Forget Display", role: .destructive) {
                store.forget(display)
            }
        } message: { display in
            Text("“\(display.name)” will use the default layout if you connect it again.")
        }
    }
}

/// The connected displays drawn as they are arranged in Displays settings,
/// each with its layout. With a selection, clicking one selects it and the
/// others dim.
struct DisplayArrangementMap: View {
    @Environment(LayoutStore.self) private var store
    let displays: [DisplayInfo]
    var selection: Binding<String?>?

    var body: some View {
        GeometryReader { geometry in
            let bounds = displays.reduce(CGRect.null) { $0.union($1.frame) }
            let scale = bounds.isNull ? 0 : min(
                geometry.size.width / bounds.width,
                geometry.size.height / bounds.height
            )
            let offset = CGPoint(
                x: (geometry.size.width - bounds.width * scale) / 2,
                y: (geometry.size.height - bounds.height * scale) / 2
            )

            ZStack(alignment: .topLeading) {
                ForEach(displays) { display in
                    let rect = CGRect(
                        x: offset.x + (display.frame.minX - bounds.minX) * scale,
                        y: offset.y + (bounds.maxY - display.frame.maxY) * scale,
                        width: display.frame.width * scale,
                        height: display.frame.height * scale
                    ).insetBy(dx: 2, dy: 2)
                    let isSelected = display.id == selection?.wrappedValue
                    let isDimmed = selection != nil && !isSelected

                    ZoneMap(
                        zones: store.resolution(forDisplay: display.id, name: display.name).layout.zones,
                        aspectRatio: rect.width / max(1, rect.height),
                        spacing: 1,
                        cornerRadius: 1.5
                    )
                    .overlay(alignment: .top) {
                        if display.isPrimary {
                            // The menu bar, as Displays settings marks the main display.
                            Rectangle()
                                .fill(Color.primary.opacity(0.35))
                                .frame(height: 2)
                                .padding(.horizontal, 1)
                        }
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                            .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2)
                            .padding(-3)
                    }
                    .opacity(isDimmed ? 0.55 : 1)
                    .frame(width: rect.width, height: rect.height)
                    .contentShape(Rectangle())
                    .onTapGesture { selection?.wrappedValue = display.id }
                    .offset(x: rect.minX, y: rect.minY)
                    .help(display.name)
                    .accessibilityElement()
                    .accessibilityLabel(display.name)
                    .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
                }
            }
        }
        .padding(.horizontal, 6)
    }
}

private struct DisplaySidebarRow: View {
    let display: DisplayInfo
    let resolution: LayoutStore.Resolution

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: display.symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: display.name)
                    .lineLimit(1)
                Group {
                    switch resolution.source {
                    case .display:
                        Text(verbatim: resolution.layout.name)
                    case .space:
                        Text("\(resolution.layout.name) · this Desktop")
                    case .defaultLayout:
                        Text("\(resolution.layout.name) · default")
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
        }
        .padding(.vertical, 3)
    }
}

private struct DisconnectedDisplayRow: View {
    let display: LayoutStore.DisconnectedDisplay
    let onForget: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "display")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.tertiary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: display.name)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let layout = display.layout {
                    Text(verbatim: layout.name)
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            Button("Forget", action: onForget)
                .buttonStyle(.borderless)
                .font(.subheadline)
        }
        .padding(.vertical, 3)
        .contextMenu {
            Button("Forget Display…", action: onForget)
        }
    }
}

/// The layout of displays that have none of their own, kept out of the way.
private struct DefaultLayoutBar: View {
    @Environment(LayoutStore.self) private var store

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                Text("Default Layout")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                LayoutPicker(selection: Binding(
                    get: { store.defaultLayout.id },
                    set: { store.assign($0, to: .defaultLayout) }
                ))
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 12)
        }
        .help("Used by a display that has no layout of its own, such as one you connect for the first time.")
    }
}

/// A menu of the user's layouts and the templates.
struct LayoutPicker<Extra: View>: View {
    @Environment(LayoutStore.self) private var store
    @Binding var selection: UUID?
    let extra: Extra

    init(selection: Binding<UUID?>, @ViewBuilder extra: () -> Extra) {
        _selection = selection
        self.extra = extra()
    }

    var body: some View {
        Picker(selection: $selection) {
            extra
            if !store.layouts.isEmpty {
                Section("Your Layouts") {
                    ForEach(store.layouts) { layout in
                        Text(verbatim: layout.name).tag(UUID?.some(layout.id))
                    }
                }
            }
            Section("Templates") {
                ForEach(Layout.templates) { layout in
                    Text(verbatim: layout.name).tag(UUID?.some(layout.id))
                }
            }
        } label: {
            EmptyView()
        }
        .labelsHidden()
        .pickerStyle(.menu)
    }
}

extension LayoutPicker where Extra == EmptyView {
    init(selection: Binding<UUID>) {
        self.init(
            selection: Binding<UUID?>(
                get: { selection.wrappedValue },
                set: { if let id = $0 { selection.wrappedValue = id } }
            ),
            extra: { EmptyView() }
        )
    }
}

// MARK: - Display Detail

/// One display: the layout it uses, where that comes from, and the library
/// to choose another with one click.
struct DisplayLayoutsView: View {
    @Environment(LayoutStore.self) private var store
    let display: DisplayInfo
    let onEdit: (LayoutEditSession) -> Void

    @State private var renaming: Layout?
    @State private var newName = ""
    @State private var pendingDeletion: Layout?

    private var resolution: LayoutStore.Resolution {
        store.resolution(forDisplay: display.id, name: display.name)
    }

    private var spaces: [SpaceDetector.SpaceInfo] {
        SpaceDetector.shared.allSpaces().filter { $0.displayUUID == display.id }
    }

    private var currentSpace: SpaceDetector.SpaceInfo? {
        display.screen.flatMap { SpaceDetector.shared.currentSpace(for: $0) }
    }

    private var target: LayoutStore.Target {
        store.choiceTarget(forDisplay: display.id)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                hero
                library(
                    title: "Your Layouts",
                    layouts: store.layouts,
                    empty: "Layouts you create or customize appear here."
                )
                library(title: "Templates", layouts: Layout.templates, empty: nil)
                if spaces.count > 1 {
                    desktops
                }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 28)
            .frame(maxWidth: 1000, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(display.name)
        .navigationSubtitle(display.isPortrait
            ? String(localized: "\(display.resolutionDescription) · Portrait")
            : display.resolutionDescription)
        .alert("Rename Layout", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $newName)
            Button("Rename") {
                let name = newName.trimmingCharacters(in: .whitespaces)
                if let layout = renaming, !name.isEmpty {
                    store.rename(id: layout.id, to: name)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(
            pendingDeletion.map { String(localized: "Delete “\($0.name)”?") } ?? "",
            isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }),
            presenting: pendingDeletion
        ) { layout in
            Button("Delete Layout", role: .destructive) {
                store.deleteLayout(id: layout.id)
            }
        } message: { layout in
            Text(deletionMessage(for: layout))
        }
    }

    // MARK: Hero

    private var hero: some View {
        let layout = resolution.layout
        let usedElsewhere = store.usage(of: layout.id).displays.filter { $0 != display.name }

        return HStack(alignment: .center, spacing: 32) {
            DisplayPreview(zones: layout.zones, aspectRatio: display.aspectRatio)
                .frame(
                    width: display.isPortrait ? nil : 400,
                    height: display.isPortrait ? 300 : nil
                )

            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Layout in Use")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(verbatim: layout.name)
                        .font(.title.weight(.semibold))
                        .lineLimit(2)
                    SourceLabel(source: resolution.source, spaceIndex: currentSpace?.index)
                }

                HStack(spacing: 10) {
                    Button {
                        edit(layout)
                    } label: {
                        Label(layout.isTemplate ? "Customize…" : "Edit Layout…", systemImage: "slider.horizontal.3")
                    }
                    .buttonStyle(.borderedProminent)
                    Button {
                        if let screen = display.screen {
                            ZoneOverlayController.preview(layout, on: screen)
                        }
                    } label: {
                        Label("Show on Display", systemImage: "eye")
                    }
                    .help("Show the zones on this display for a moment")
                }
                .controlSize(.large)

                Group {
                    switch resolution.source {
                    case .space:
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("Choosing a layout below changes only this Desktop.")
                            if let space = currentSpace {
                                Button("Use the Display’s Layout") {
                                    store.clearAssignment(.space(space.uuid))
                                }
                                .buttonStyle(.link)
                            }
                        }
                    case .defaultLayout:
                        Text("Choosing a layout below gives this display its own.")
                    case .display:
                        if layout.isTemplate {
                            Text("Customizing a template saves your own copy.")
                        } else if !usedElsewhere.isEmpty {
                            Text("Also used on \(usedElsewhere.formatted(.list(type: .and))). Editing it changes it there too.")
                        }
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Library

    private func library(title: LocalizedStringKey, layouts: [Layout], empty: LocalizedStringKey?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.headline)
                Spacer()
                if empty != nil {
                    Button {
                        onEdit(LayoutEditSession(creating: store.blankLayout(), display: display, applyOnSave: target))
                    } label: {
                        Label("New Layout", systemImage: "plus")
                    }
                    .buttonStyle(.borderless)
                    .help("Start from one zone over the whole display, then split it")
                }
            }

            if layouts.isEmpty, let empty {
                Text(empty)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    )
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 150, maximum: 210), spacing: 14)],
                    alignment: .leading,
                    spacing: 14
                ) {
                    ForEach(layouts) { layout in
                        LayoutTile(
                            layout: layout,
                            aspectRatio: display.aspectRatio,
                            isCurrent: layout.id == resolution.layout.id
                        ) {
                            store.assign(layout.id, to: target)
                        }
                        .contextMenu { menu(for: layout) }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func menu(for layout: Layout) -> some View {
        Button("Use on \(display.name)") {
            store.assign(layout.id, to: target)
        }
        Button(layout.isTemplate ? "Customize…" : "Edit…") {
            edit(layout)
        }
        if !layout.isTemplate {
            Button("Duplicate") {
                store.save(store.copy(of: layout))
            }
            Button("Rename…") {
                newName = layout.name
                renaming = layout
            }
        }
        Button("Make Default Layout") {
            store.assign(layout.id, to: .defaultLayout)
        }
        .disabled(store.defaultLayout.id == layout.id)
        if !layout.isTemplate {
            Divider()
            Button("Delete…", role: .destructive) {
                pendingDeletion = layout
            }
        }
    }

    private func edit(_ layout: Layout) {
        onEdit(LayoutEditSession(
            editing: layout,
            copyName: LayoutStore.uniqueName(String(localized: "\(layout.name) Copy"), among: store.library.map(\.name)),
            display: display,
            applyOnSave: target
        ))
    }

    private func deletionMessage(for layout: Layout) -> String {
        let usage = store.usage(of: layout.id)
        var parts: [String] = []
        if !usage.displays.isEmpty {
            parts.append(String(localized: "It is used on \(usage.displays.formatted(.list(type: .and))), which will use the default layout instead."))
        }
        if usage.spaces > 0 {
            parts.append(String(localized: "\(usage.spaces) Desktops with this layout will use their display’s layout."))
        }
        if usage.isDefault {
            parts.append(String(localized: "It is the default layout; your first remaining layout takes its place."))
        }
        if parts.isEmpty {
            parts.append(String(localized: "No display uses it."))
        }
        return parts.joined(separator: " ")
    }

    // MARK: Desktops

    private var desktops: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Desktops")
                    .font(.headline)
                Text("A Desktop can have a layout of its own, used instead of the display’s while you are on it.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            VStack(spacing: 0) {
                ForEach(Array(spaces.enumerated()), id: \.element.uuid) { offset, space in
                    if offset > 0 {
                        Divider().padding(.leading, 14)
                    }
                    HStack(spacing: 10) {
                        Text("Desktop \(space.index)")
                        if space.uuid == currentSpace?.uuid {
                            Badge(text: "Current")
                        }
                        Spacer()
                        LayoutPicker(
                            selection: Binding(
                                get: { store.spaceLayouts[space.uuid].flatMap { store.layout(id: $0)?.id } },
                                set: { id in
                                    if let id {
                                        store.assign(id, to: .space(space.uuid))
                                    } else {
                                        store.clearAssignment(.space(space.uuid))
                                    }
                                }
                            )
                        ) {
                            Text("Display’s Layout").tag(UUID?.none)
                        }
                        .fixedSize()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.035))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
    }
}

/// Where the layout of a display comes from, in words.
private struct SourceLabel: View {
    let source: LayoutStore.Source
    let spaceIndex: Int?

    var body: some View {
        Group {
            switch source {
            case .display:
                Label("Chosen for this display", systemImage: "display")
            case .space:
                if let spaceIndex {
                    Label("Chosen for Desktop \(spaceIndex)", systemImage: "rectangle.stack")
                } else {
                    Label("Chosen for this Desktop", systemImage: "rectangle.stack")
                }
            case .defaultLayout:
                Label("The default layout", systemImage: "arrow.uturn.down.square")
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
    }
}

/// A large picture of a layout on its display, with numbers and shortcuts.
private struct DisplayPreview: View {
    let zones: [Zone]
    let aspectRatio: CGFloat

    var body: some View {
        ZoneMap(zones: zones, aspectRatio: aspectRatio, spacing: 3, showsNumbers: true, cornerRadius: 6)
            .padding(7)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor))
                    .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
            )
    }
}

/// A layout in the library: a picture in the display's proportions and its
/// name. Clicking it applies it.
private struct LayoutTile: View {
    let layout: Layout
    let aspectRatio: CGFloat
    let isCurrent: Bool
    let action: () -> Void
    @State private var isHovered = false

    private var thumbnailHeight: CGFloat { aspectRatio < 1 ? 118 : 84 }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                ZoneMap(zones: layout.zones, aspectRatio: aspectRatio, spacing: 1.5, cornerRadius: 3)
                    .frame(maxWidth: .infinity, maxHeight: thumbnailHeight)
                    .frame(height: thumbnailHeight)
                HStack(spacing: 5) {
                    Text(verbatim: layout.name)
                        .font(.callout.weight(isCurrent ? .semibold : .regular))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if isCurrent {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.callout)
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isCurrent ? Color.accentColor.opacity(0.10) : Color.primary.opacity(isHovered ? 0.07 : 0.035))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        isCurrent ? Color.accentColor : Color.primary.opacity(isHovered ? 0.2 : 0.08),
                        lineWidth: isCurrent ? 2 : 1
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .accessibilityLabel(layout.name)
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }
}
