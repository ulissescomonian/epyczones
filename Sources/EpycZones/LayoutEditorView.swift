import AppKit
import SwiftUI

/// Editing one layout: tools over the canvas, the inspector on the right.
/// Nothing is saved until Save; Cancel leaves the layout as it was.
struct LayoutEditorView: View {
    @Bindable var session: LayoutEditSession
    let onFinish: (_ save: Bool) -> Void

    @State private var confirmsDiscard = false
    @FocusState private var textField: InspectorField?

    private var title: LocalizedStringKey {
        if session.template != nil { return "Customize Template" }
        return session.isNew ? "New Layout" : "Edit Layout"
    }

    private var canSave: Bool {
        !session.name.trimmingCharacters(in: .whitespaces).isEmpty && (session.isNew || session.hasChanges)
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                EditorTools(session: session)
                    .padding(.top, 16)
                ZoneCanvasView(session: session)
                    .padding(.horizontal, 40)
                    .padding(.vertical, 26)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                EditorStatusBar(session: session)
            }
            .background(Color(nsColor: .underPageBackgroundColor))

            Divider()

            LayoutInspector(session: session, focus: $textField)
                .frame(width: 300)
        }
        .navigationTitle(title)
        .navigationSubtitle(session.display.name)
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                // Disabled while a text field is focused, so ⌘Z undoes typing there.
                Button {
                    session.undo()
                } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(!session.canUndo || textField != nil)
                .help("Undo")

                Button {
                    session.redo()
                } label: {
                    Label("Redo", systemImage: "arrow.uturn.forward")
                }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!session.canRedo || textField != nil)
                .help("Redo")
            }

            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    if let screen = session.display.screen {
                        ZoneOverlayController.preview(session.draft, on: screen)
                    }
                } label: {
                    Label("Test on Display", systemImage: "eye")
                        .labelStyle(.titleAndIcon)
                }
                .help("Show these zones on \(session.display.name) for a moment, as dragging shows them")

                Button("Cancel", action: cancel)
                    .keyboardShortcut(.cancelAction)

                Button("Save") {
                    onFinish(true)
                }
                .keyboardShortcut("s", modifiers: .command)
                .buttonStyle(.borderedProminent)
                .disabled(!canSave)
            }
        }
        .confirmationDialog("Discard your changes?", isPresented: $confirmsDiscard) {
            Button("Discard Changes", role: .destructive) {
                onFinish(false)
            }
            Button("Keep Editing", role: .cancel) {}
        } message: {
            Text(session.isNew
                ? "The new layout will not be created."
                : "The layout stays as it was before you started editing.")
        }
    }

    private func cancel() {
        if session.hasChanges {
            confirmsDiscard = true
        } else {
            onFinish(false)
        }
    }
}

enum InspectorField: Hashable {
    case layoutName
    case zoneName
    case geometry(Int)
}

// MARK: - Tools

/// The tools over the canvas, in a floating bar.
private struct EditorTools: View {
    @Bindable var session: LayoutEditSession
    @State private var showsMergeChoices = false

    var body: some View {
        let selection = session.selection
        let neighbors = selection.map { LayoutGeometry.mergeableNeighbors(of: $0, in: session.zones) } ?? []

        HStack(spacing: 2) {
            ToolButton(title: "Columns", symbol: "rectangle.split.2x1") {
                if let selection { session.split(selection, by: .vertical) }
            }
            .help("Split the selected zone into two columns")
            .disabled(selection == nil)

            ToolButton(title: "Rows", symbol: "rectangle.split.1x2") {
                if let selection { session.split(selection, by: .horizontal) }
            }
            .help("Split the selected zone into two rows")
            .disabled(selection == nil)

            ToolButton(title: "Merge", symbol: "rectangle.compress.vertical") {
                if neighbors.count == 1, let selection {
                    session.merge(selection, with: neighbors[0].zoneID)
                } else {
                    showsMergeChoices = true
                }
            }
            .help("Join the selected zone with a neighbor that shares a whole edge")
            .disabled(neighbors.isEmpty)
            .popover(isPresented: $showsMergeChoices, arrowEdge: .bottom) {
                MergeChoices(session: session, neighbors: neighbors) {
                    showsMergeChoices = false
                }
            }

            ToolSeparator()

            ToolButton(title: "Add Zone", symbol: "plus.rectangle.on.rectangle") {
                session.addZone()
            }
            .help("Add a free zone that you can place anywhere, even over others")

            ToolButton(title: "Delete", symbol: "trash") {
                if let selection { session.delete(selection) }
            }
            .help("Delete the selected zone")
            .disabled(selection == nil)

            ToolSeparator()

            ToolButton(title: "Grid", symbol: "grid", isOn: session.snapsToGrid) {
                session.snapsToGrid.toggle()
            }
            .help("Snap zones and dividers to a grid of 24 steps")
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct MergeChoices: View {
    let session: LayoutEditSession
    let neighbors: [LayoutGeometry.Neighbor]
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Merge With")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.bottom, 4)
            ForEach(neighbors, id: \.zoneID) { neighbor in
                let number = (session.zones.firstIndex { $0.id == neighbor.zoneID } ?? 0) + 1
                Button {
                    if let selection = session.selection {
                        session.merge(selection, with: neighbor.zoneID)
                    }
                    onDone()
                } label: {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(ZonePalette.color(number - 1))
                            .frame(width: 8, height: 8)
                        Text("Zone \(number)")
                        Spacer(minLength: 16)
                        Text(Self.sideName(neighbor.side))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .frame(minWidth: 200)
    }

    private static func sideName(_ side: LayoutGeometry.Side) -> LocalizedStringKey {
        switch side {
        case .left: return "On the left"
        case .right: return "On the right"
        case .top: return "Above"
        case .bottom: return "Below"
        }
    }
}

private struct ToolButton: View {
    let title: LocalizedStringKey
    let symbol: String
    var isOn = false
    let action: () -> Void

    @State private var isHovered = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: symbol)
                    .font(.system(size: 15))
                    .frame(height: 18)
                Text(title)
                    .font(.system(size: 10.5))
                    .lineLimit(1)
            }
            .frame(width: 62, height: 42)
            .foregroundStyle(isOn ? Color.accentColor : Color.primary)
            .opacity(isEnabled ? 1 : 0.35)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isOn
                        ? Color.accentColor.opacity(0.15)
                        : Color.primary.opacity(isHovered && isEnabled ? 0.08 : 0))
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel(title)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

private struct ToolSeparator: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.12))
            .frame(width: 1, height: 28)
            .padding(.horizontal, 4)
    }
}

/// The check result and a hint, under the canvas.
private struct EditorStatusBar: View {
    let session: LayoutEditSession

    var body: some View {
        let count = session.issues.count
        HStack(spacing: 12) {
            if count == 0 {
                Label {
                    Text("No gaps or overlaps")
                } icon: {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                }
            } else {
                Label {
                    Text("^[\(count) issue](inflect: true) to check")
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
            }
            Spacer(minLength: 12)
            Text("Drag the line between zones to resize both. Hold ⌥ to move one segment.")
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .font(.callout)
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }
}

// MARK: - Inspector

private struct LayoutInspector: View {
    @Environment(LayoutStore.self) private var store
    @Bindable var session: LayoutEditSession
    var focus: FocusState<InspectorField?>.Binding

    private let shortcuts = HotKeyBinding.zoneBindings(modifiers: AppSettings.shared.zoneHotKeyModifiers.rawValue)

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $session.name, prompt: Text("Layout name"))
                    .focused(focus, equals: .layoutName)
            } header: {
                Text("Layout")
            } footer: {
                layoutNote
            }

            zoneSection
            orderSection
            checksSection
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var layoutNote: some View {
        if let template = session.template {
            Text("A copy of the \(template.name) template. Saving adds it to your layouts.")
        } else if !session.isNew {
            let displays = store.usage(of: session.draft.id).displays
            if !displays.isEmpty {
                Text("Used on \(displays.formatted(.list(type: .and))).")
            }
        }
    }

    // MARK: Zone

    @ViewBuilder
    private var zoneSection: some View {
        if let index = session.selectedIndex {
            let zone = session.zones[index]
            let pixels = session.display.pixelSize(of: zone.rect)

            Section {
                LabeledContent("Shortcut") {
                    if index < shortcuts.count {
                        KeyCaps(binding: shortcuts[index])
                    } else {
                        Text("None")
                            .foregroundStyle(.secondary)
                    }
                }
                Picker("Number", selection: Binding(
                    get: { index + 1 },
                    set: { session.renumber(zone.id, to: $0) }
                )) {
                    ForEach(1...session.zones.count, id: \.self) { number in
                        Text(verbatim: "\(number)").tag(number)
                    }
                }
                TextField("Name", text: Binding(
                    get: { zone.name },
                    set: { session.setName($0, of: zone.id) }
                ), prompt: Text("Optional"))
                .focused(focus, equals: .zoneName)

                LabeledContent("Position") {
                    HStack(spacing: 10) {
                        PercentField(label: "X", value: zone.rect.x, field: .geometry(0), focus: focus) { value in
                            update(zone) { $0.x = value }
                        }
                        PercentField(label: "Y", value: zone.rect.y, field: .geometry(1), focus: focus) { value in
                            update(zone) { $0.y = value }
                        }
                    }
                }
                LabeledContent("Size") {
                    HStack(spacing: 10) {
                        PercentField(label: "W", value: zone.rect.width, field: .geometry(2), focus: focus) { value in
                            update(zone) { $0.width = value }
                        }
                        PercentField(label: "H", value: zone.rect.height, field: .geometry(3), focus: focus) { value in
                            update(zone) { $0.height = value }
                        }
                    }
                }
                LabeledContent("Pixels") {
                    Text(verbatim: "\(pixels.width) × \(pixels.height)")
                        .monospacedDigit()
                }
            } header: {
                HStack(spacing: 6) {
                    Circle()
                        .fill(ZonePalette.color(index))
                        .frame(width: 8, height: 8)
                    Text("Zone \(index + 1)")
                }
            }
        } else {
            Section("Zone") {
                Text("Select a zone on the canvas to change it. Tab moves between zones.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func update(_ zone: Zone, _ change: (inout RelativeRect) -> Void) {
        var rect = zone.rect
        change(&rect)
        session.setRect(rect, of: zone.id)
    }

    // MARK: Order

    private var orderSection: some View {
        Section {
            ForEach(Array(session.zones.enumerated()), id: \.element.id) { index, zone in
                HStack(spacing: 10) {
                    Text(verbatim: "\(index + 1)")
                        .font(.system(.callout, design: .rounded).weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(ZonePalette.color(index)))
                    if zone.name.isEmpty {
                        Text("Zone \(index + 1)")
                            .foregroundStyle(.secondary)
                    } else {
                        Text(verbatim: zone.name)
                    }
                    Spacer(minLength: 8)
                    if index < shortcuts.count {
                        Text(verbatim: shortcuts[index].displayString)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { session.selection = zone.id }
                .listRowBackground(zone.id == session.selection ? Color.accentColor.opacity(0.14) : nil)
            }
            .onMove { source, destination in
                session.moveZones(fromOffsets: source, toOffset: destination)
            }
        } header: {
            Text("Order")
        } footer: {
            VStack(alignment: .leading, spacing: 8) {
                Text("The number is the zone’s shortcut. Drag a zone to change it.")
                Button("Sort by Position") {
                    session.sortByPosition()
                }
                .help("Number the zones from top to bottom, then left to right")
            }
        }
    }

    // MARK: Checks

    private var checksSection: some View {
        Section("Checks") {
            let issues = session.issues
            if issues.isEmpty {
                InlineNotice(kind: .success, text: String(localized: "Every part of the display is in exactly one zone."))
            }
            ForEach(issues, id: \.self) { issue in
                InlineNotice(kind: .warning, text: Self.describe(issue))
            }
        }
    }

    static func describe(_ issue: LayoutGeometry.Issue) -> String {
        switch issue {
        case .empty:
            return String(localized: "The layout has no zones, so dragging shows nothing on this display.")
        case .uncovered(let fraction):
            let share = fraction.formatted(.percent.precision(.fractionLength(0...1)))
            return String(localized: "\(share) of the display is in no zone. Windows can’t snap there.")
        case .overlap(let a, let b):
            return String(localized: "Zones \(a + 1) and \(b + 1) overlap.")
        case .withoutShortcut(let count):
            return String(localized: "Only the first 9 zones have shortcuts; \(count) more have none.")
        }
    }
}

/// A percentage typed as a number from 0 to 100.
private struct PercentField: View {
    let label: LocalizedStringKey
    let value: Double
    let field: InspectorField
    var focus: FocusState<InspectorField?>.Binding
    let onCommit: (Double) -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(
                label,
                value: Binding(get: { value * 100 }, set: { onCommit($0 / 100) }),
                format: .number.precision(.fractionLength(0...1))
            )
            .labelsHidden()
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.trailing)
            .frame(width: 52)
            .focused(focus, equals: field)
            Text(verbatim: "%")
                .foregroundStyle(.secondary)
        }
    }
}
