import AppKit
import SwiftUI

/// The editing surface: the display in its real proportions, with the
/// draft's zones and the zone gap to scale. A zone moves when dragged, the
/// selected zone resizes by its handles, and dragging the line between zones
/// resizes both sides at once.
///
/// One gesture serves the whole canvas and decides what it drags from where
/// it starts, so a drag survives the zones changing under it.
struct ZoneCanvasView: View {
    @Bindable var session: LayoutEditSession
    @FocusState private var isFocused: Bool
    @State private var drag: ActiveDrag?
    @State private var ignoresDrag = false
    @State private var hoveredDividerID: String?
    @State private var readout: Readout?

    private let shortcuts = HotKeyBinding.zoneBindings(modifiers: AppSettings.shared.zoneHotKeyModifiers.rawValue)

    /// What a drag changes.
    private enum Target {
        case move(UUID)
        case resize(UUID, LayoutGeometry.Edges)
        case divider(LayoutGeometry.Divider)
    }

    private struct ActiveDrag {
        let target: Target
        let startZones: [Zone]
    }

    /// A live value shown next to what is being dragged.
    private struct Readout {
        let text: String
        let point: CGPoint
    }

    /// Distance from a line or handle that still grabs it, in points.
    private static let grabDistance: CGFloat = 6
    private static let handleGrabDistance: CGFloat = 10

    var body: some View {
        GeometryReader { geometry in
            let size = fittedSize(in: geometry.size)
            canvas(size: size)
                .frame(width: size.width, height: size.height)
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled()
        .onKeyPress(phases: .down, action: handleKey)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Layout canvas")
    }

    private func fittedSize(in available: CGSize) -> CGSize {
        let aspect = session.display.aspectRatio
        let width = max(1, min(available.width, available.height * aspect))
        return CGSize(width: width, height: width / aspect)
    }

    // MARK: - Drawing

    private func canvas(size: CGSize) -> some View {
        let zones = session.zones
        let dividers = LayoutGeometry.dividers(in: zones)
        let scale = size.width / max(1, session.display.visibleFrame.width)
        let inset = max(2, AppSettings.shared.zoneGap * scale)

        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor))
                .shadow(color: .black.opacity(0.18), radius: 14, y: 5)
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)

            if session.snapsToGrid {
                GridLines()
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            if !zones.isEmpty {
                UncoveredHatch(regions: LayoutGeometry.uncoveredRegions(in: zones))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            ForEach(Array(zones.enumerated()), id: \.element.id) { index, zone in
                let rect = canvasRect(zone.rect, size).insetBy(dx: inset, dy: inset)
                CanvasZone(
                    number: index + 1,
                    name: zone.name,
                    shortcut: index < shortcuts.count ? shortcuts[index] : nil,
                    isSelected: zone.id == session.selection,
                    size: rect.size
                )
                .frame(width: max(0, rect.width), height: max(0, rect.height))
                .offset(x: rect.minX, y: rect.minY)
            }

            if let line = highlightedLine(dividers: dividers) {
                lineMark(line, size: size)
            }

            ForEach(dividers) { divider in
                DividerGrip(divider: divider, size: size)
            }

            if let index = session.selectedIndex {
                SelectionHandles(
                    rect: canvasRect(zones[index].rect, size),
                    edges: freeEdges(of: zones[index], dividers: dividers)
                )
            }

            if let readout {
                Text(verbatim: readout.text)
                    .font(.callout.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.black.opacity(0.75)))
                    .fixedSize()
                    .position(x: readout.point.x, y: readout.point.y - 26)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .contentShape(Rectangle().inset(by: -Self.handleGrabDistance))
        .onTapGesture(coordinateSpace: .local) { location in
            isFocused = true
            session.selection = zones.last { canvasRect($0.rect, size).contains(location) }?.id
        }
        .gesture(dragGesture(size: size, dividers: dividers))
        .onContinuousHover(coordinateSpace: .local) { phase in
            switch phase {
            case .active(let point):
                let target = target(at: point, size: size, dividers: dividers)
                var dividerID: String?
                if case .divider(let divider) = target { dividerID = divider.id }
                if hoveredDividerID != dividerID { hoveredDividerID = dividerID }
                cursor(for: target).set()
            case .ended:
                hoveredDividerID = nil
                NSCursor.arrow.set()
            }
        }
    }

    /// The line a divider drag moves, shown while hovering and dragging.
    private func highlightedLine(dividers: [LayoutGeometry.Divider]) -> LayoutGeometry.Divider? {
        if let drag, case .divider(let divider) = drag.target {
            let isVertical = divider.orientation == .vertical
            let position = session.zones
                .first { divider.leading.contains($0.id) }
                .map { isVertical ? $0.rect.maxX : $0.rect.maxY } ?? divider.position
            return LayoutGeometry.Divider(
                orientation: divider.orientation,
                position: position,
                start: divider.start,
                end: divider.end,
                leading: divider.leading,
                trailing: divider.trailing
            )
        }
        guard let hovered = dividers.first(where: { $0.id == hoveredDividerID }) else { return nil }
        return LayoutGeometry.line(through: hovered, in: session.zones)
    }

    private func lineMark(_ line: LayoutGeometry.Divider, size: CGSize) -> some View {
        let isVertical = line.orientation == .vertical
        let length = (line.end - line.start) * (isVertical ? size.height : size.width)
        let center = isVertical
            ? CGPoint(x: line.position * size.width, y: (line.start + line.end) / 2 * size.height)
            : CGPoint(x: (line.start + line.end) / 2 * size.width, y: line.position * size.height)
        return Capsule()
            .fill(Color.accentColor)
            .frame(width: isVertical ? 3 : length, height: isVertical ? length : 3)
            .position(center)
            .allowsHitTesting(false)
    }

    // MARK: - Geometry

    private func canvasRect(_ rect: RelativeRect, _ size: CGSize) -> CGRect {
        CGRect(
            x: rect.x * size.width,
            y: rect.y * size.height,
            width: rect.width * size.width,
            height: rect.height * size.height
        )
    }

    /// Edges of a zone that resize it alone: those not on a divider, where
    /// the divider's grip moves both sides instead.
    private func freeEdges(of zone: Zone, dividers: [LayoutGeometry.Divider]) -> LayoutGeometry.Edges {
        var edges: LayoutGeometry.Edges = [.left, .right, .top, .bottom]
        for divider in dividers {
            switch divider.orientation {
            case .vertical:
                if divider.leading.contains(zone.id) { edges.remove(.right) }
                if divider.trailing.contains(zone.id) { edges.remove(.left) }
            case .horizontal:
                if divider.leading.contains(zone.id) { edges.remove(.bottom) }
                if divider.trailing.contains(zone.id) { edges.remove(.top) }
            }
        }
        return edges
    }

    /// What a drag starting at `point` would change: the selected zone's
    /// handles first, then dividers, then the topmost zone.
    private func target(at point: CGPoint, size: CGSize, dividers: [LayoutGeometry.Divider]) -> Target? {
        if let index = session.selectedIndex {
            let zone = session.zones[index]
            let rect = canvasRect(zone.rect, size)
            for handle in SelectionHandles.handles(in: rect, edges: freeEdges(of: zone, dividers: dividers))
            where hypot(point.x - handle.point.x, point.y - handle.point.y) <= Self.handleGrabDistance {
                return .resize(zone.id, handle.edges)
            }
        }
        for divider in dividers {
            let isVertical = divider.orientation == .vertical
            let across = isVertical ? point.x - divider.position * size.width : point.y - divider.position * size.height
            let along = isVertical ? point.y / size.height : point.x / size.width
            if abs(across) <= Self.grabDistance, along >= divider.start, along <= divider.end {
                return .divider(divider)
            }
        }
        if let zone = session.zones.last(where: { canvasRect($0.rect, size).contains(point) }) {
            return .move(zone.id)
        }
        return nil
    }

    private func cursor(for target: Target?) -> NSCursor {
        switch target {
        case .move:
            return .openHand
        case .divider(let divider):
            return divider.orientation == .vertical ? .resizeLeftRight : .resizeUpDown
        case .resize(_, let edges):
            if edges == .left || edges == .right { return .resizeLeftRight }
            if edges == .top || edges == .bottom { return .resizeUpDown }
            return .crosshair
        case nil:
            return .arrow
        }
    }

    // MARK: - Dragging

    private func dragGesture(size: CGSize, dividers: [LayoutGeometry.Divider]) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .local)
            .onChanged { value in
                if drag == nil && !ignoresDrag {
                    guard var target = target(at: value.startLocation, size: size, dividers: dividers) else {
                        ignoresDrag = true
                        return
                    }
                    // A divider moves its whole line unless Option is held.
                    if case .divider(let segment) = target, !NSEvent.modifierFlags.contains(.option) {
                        target = .divider(LayoutGeometry.line(through: segment, in: session.zones))
                    }
                    switch target {
                    case .move(let id), .resize(let id, _):
                        session.selection = id
                    case .divider:
                        break
                    }
                    isFocused = true
                    session.beginInteraction()
                    drag = ActiveDrag(target: target, startZones: session.zones)
                    if case .move = target { NSCursor.closedHand.set() }
                }
                guard let drag else { return }
                apply(drag, translation: value.translation, location: value.location, size: size)
            }
            .onEnded { _ in
                if drag != nil {
                    session.endInteraction()
                }
                drag = nil
                ignoresDrag = false
                readout = nil
            }
    }

    private func apply(_ drag: ActiveDrag, translation: CGSize, location: CGPoint, size: CGSize) {
        let dx = translation.width / size.width
        let dy = translation.height / size.height
        let grid = session.snapsToGrid
        var zones = drag.startZones

        switch drag.target {
        case .move(let id):
            guard let index = zones.firstIndex(where: { $0.id == id }) else { return }
            zones[index].rect = LayoutGeometry.move(zones[index].rect, dx: dx, dy: dy, grid: grid)
            readout = nil
        case .resize(let id, let edges):
            guard let index = zones.firstIndex(where: { $0.id == id }) else { return }
            let rect = LayoutGeometry.resize(zones[index].rect, edges: edges, dx: dx, dy: dy, grid: grid)
            zones[index].rect = rect
            readout = Readout(text: "\(Self.percent(rect.width)) × \(Self.percent(rect.height))", point: location)
        case .divider(let divider):
            let isVertical = divider.orientation == .vertical
            let others = drag.startZones
                .filter { !divider.zoneIDs.contains($0.id) }
                .flatMap { isVertical ? [$0.rect.x, $0.rect.maxX] : [$0.rect.y, $0.rect.maxY] }
            let position = LayoutGeometry.snap(
                divider.position + (isVertical ? dx : dy),
                grid: grid,
                edges: others + [0.25, 1.0 / 3.0, 0.5, 2.0 / 3.0, 0.75]
            )
            zones = LayoutGeometry.move(divider, to: position, in: drag.startZones)
            let moved = zones.first { divider.leading.contains($0.id) }.map { isVertical ? $0.rect.maxX : $0.rect.maxY } ?? position
            let point = isVertical
                ? CGPoint(x: moved * size.width, y: location.y)
                : CGPoint(x: location.x, y: moved * size.height)
            readout = Readout(text: Self.percent(moved), point: point)
        }
        session.updateInteraction(zones)
    }

    static func percent(_ value: Double) -> String {
        (value).formatted(.percent.precision(.fractionLength(0...1)))
    }

    // MARK: - Keyboard

    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        let resizing = press.modifiers.contains(.shift)
        switch press.key {
        case .leftArrow: session.nudgeSelection(dx: -1, dy: 0, resizing: resizing)
        case .rightArrow: session.nudgeSelection(dx: 1, dy: 0, resizing: resizing)
        case .upArrow: session.nudgeSelection(dx: 0, dy: -1, resizing: resizing)
        case .downArrow: session.nudgeSelection(dx: 0, dy: 1, resizing: resizing)
        case .tab: session.selectNext(backward: press.modifiers.contains(.shift))
        case .delete, .deleteForward:
            guard let id = session.selection else { return .ignored }
            session.delete(id)
        default:
            return .ignored
        }
        return .handled
    }
}

// MARK: - Pieces

/// One zone on the canvas: its color, number, shortcut and name.
private struct CanvasZone: View {
    let number: Int
    let name: String
    let shortcut: HotKeyBinding?
    let isSelected: Bool
    let size: CGSize

    var body: some View {
        let color = ZonePalette.color(number - 1)
        let shortSide = min(size.width, size.height)

        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(color.opacity(isSelected ? 0.30 : 0.17))
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(color.opacity(isSelected ? 1 : 0.55), lineWidth: isSelected ? 2.5 : 1.25)
            VStack(spacing: 7) {
                Text(verbatim: "\(number)")
                    .font(.system(size: min(54, max(13, shortSide * 0.3)), weight: .bold, design: .rounded))
                    .foregroundStyle(color)
                if size.width > 90 && size.height > 96 {
                    if let shortcut {
                        KeyCaps(binding: shortcut)
                    }
                    if !name.isEmpty {
                        Text(verbatim: name)
                            .font(.callout.weight(.medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .padding(6)
            .minimumScaleFactor(0.5)
        }
        .shadow(color: isSelected ? color.opacity(0.35) : .clear, radius: 10)
        .accessibilityElement()
        .accessibilityLabel(name.isEmpty ? String(localized: "Zone \(number)") : name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// The grip in the middle of a divider.
private struct DividerGrip: View {
    let divider: LayoutGeometry.Divider
    let size: CGSize

    var body: some View {
        let isVertical = divider.orientation == .vertical
        let length = (divider.end - divider.start) * (isVertical ? size.height : size.width)
        let gripLength = min(34, max(12, length * 0.4))
        let center = isVertical
            ? CGPoint(x: divider.position * size.width, y: (divider.start + divider.end) / 2 * size.height)
            : CGPoint(x: (divider.start + divider.end) / 2 * size.width, y: divider.position * size.height)

        Capsule()
            .fill(Color.white)
            .overlay(Capsule().strokeBorder(Color.black.opacity(0.2), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.28), radius: 1.5, y: 0.5)
            .frame(width: isVertical ? 6 : gripLength, height: isVertical ? gripLength : 6)
            .position(center)
            .allowsHitTesting(false)
    }
}

/// Resize handles around the selected zone.
private struct SelectionHandles: View {
    let rect: CGRect
    let edges: LayoutGeometry.Edges

    struct Handle {
        let edges: LayoutGeometry.Edges
        let point: CGPoint
        var isCorner: Bool { edges.rawValue.nonzeroBitCount == 2 }
    }

    /// Corners always resize freely; an edge has a handle only when it is
    /// in `edges`, since a divider's grip moves the others.
    static func handles(in rect: CGRect, edges: LayoutGeometry.Edges) -> [Handle] {
        var result = [
            Handle(edges: [.left, .top], point: CGPoint(x: rect.minX, y: rect.minY)),
            Handle(edges: [.right, .top], point: CGPoint(x: rect.maxX, y: rect.minY)),
            Handle(edges: [.left, .bottom], point: CGPoint(x: rect.minX, y: rect.maxY)),
            Handle(edges: [.right, .bottom], point: CGPoint(x: rect.maxX, y: rect.maxY)),
        ]
        if edges.contains(.left) { result.append(Handle(edges: .left, point: CGPoint(x: rect.minX, y: rect.midY))) }
        if edges.contains(.right) { result.append(Handle(edges: .right, point: CGPoint(x: rect.maxX, y: rect.midY))) }
        if edges.contains(.top) { result.append(Handle(edges: .top, point: CGPoint(x: rect.midX, y: rect.minY))) }
        if edges.contains(.bottom) { result.append(Handle(edges: .bottom, point: CGPoint(x: rect.midX, y: rect.maxY))) }
        return result
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(Self.handles(in: rect, edges: edges).enumerated()), id: \.offset) { _, handle in
                Group {
                    if handle.isCorner {
                        Circle()
                            .fill(Color.white)
                            .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: 1.5))
                            .frame(width: 11, height: 11)
                    } else {
                        let isHorizontal = handle.edges == .left || handle.edges == .right
                        Capsule()
                            .fill(Color.white)
                            .overlay(Capsule().strokeBorder(Color.accentColor, lineWidth: 1.5))
                            .frame(width: isHorizontal ? 7 : 20, height: isHorizontal ? 20 : 7)
                    }
                }
                .shadow(color: .black.opacity(0.25), radius: 1.5, y: 0.5)
                .position(handle.point)
            }
        }
        .allowsHitTesting(false)
    }
}

/// The snapping grid, with halves and thirds a little stronger.
private struct GridLines: View {
    var body: some View {
        Canvas { context, size in
            let divisions = Int((1 / LayoutGeometry.gridStep).rounded())
            for i in 1..<divisions {
                let fraction = CGFloat(i) / CGFloat(divisions)
                let isMajor = i % (divisions / 2) == 0 || i % (divisions / 3) == 0
                let color = Color.primary.opacity(isMajor ? 0.10 : 0.045)
                var vertical = Path()
                vertical.move(to: CGPoint(x: fraction * size.width, y: 0))
                vertical.addLine(to: CGPoint(x: fraction * size.width, y: size.height))
                context.stroke(vertical, with: .color(color), lineWidth: 0.5)
                var horizontal = Path()
                horizontal.move(to: CGPoint(x: 0, y: fraction * size.height))
                horizontal.addLine(to: CGPoint(x: size.width, y: fraction * size.height))
                context.stroke(horizontal, with: .color(color), lineWidth: 0.5)
            }
        }
        .allowsHitTesting(false)
    }
}

/// Parts of the display in no zone, hatched so the gap is obvious.
private struct UncoveredHatch: View {
    let regions: [RelativeRect]

    var body: some View {
        Canvas { context, size in
            for region in regions {
                let rect = CGRect(
                    x: region.x * size.width,
                    y: region.y * size.height,
                    width: region.width * size.width,
                    height: region.height * size.height
                )
                guard rect.width > 0.5, rect.height > 0.5 else { continue }
                context.fill(Path(rect), with: .color(.orange.opacity(0.08)))
                var stripes = Path()
                var x = rect.minX - rect.height
                while x < rect.maxX {
                    stripes.move(to: CGPoint(x: x, y: rect.maxY))
                    stripes.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
                    x += 8
                }
                var clipped = context
                clipped.clip(to: Path(rect))
                clipped.stroke(stripes, with: .color(.orange.opacity(0.4)), lineWidth: 1)
            }
        }
        .allowsHitTesting(false)
    }
}
