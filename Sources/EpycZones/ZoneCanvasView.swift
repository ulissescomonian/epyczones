import SwiftUI

/// Interactive canvas for editing zones within a layout.
struct ZoneCanvasView: View {
    @Binding var zones: [Zone]
    @Binding var selectedZoneID: UUID?
    @Binding var snapToGrid: Bool

    @State private var interaction: Interaction = .idle
    @State private var dragOrigin: CGPoint = .zero
    @State private var originalRect: RelativeRect = .zero

    private let gridDivisions = 24
    private let handleSize: CGFloat = 10
    private let edgeHandleLength: CGFloat = 20

    private let zoneColors: [Color] = [
        .blue, .green, .orange, .purple, .pink, .teal, .indigo, .mint, .cyan, .red,
    ]

    // MARK: - Body

    var body: some View {
        GeometryReader { geo in
            let size = geo.size

            ZStack(alignment: .topLeading) {
                // Background + grid
                canvas(size: size)

                // Zones
                ForEach(Array(zones.enumerated()), id: \.element.id) { index, zone in
                    zoneView(zone: zone, index: index, size: size)
                }

                // Handles for selected zone
                if let selID = selectedZoneID, let zone = zones.first(where: { $0.id == selID }) {
                    handlesOverlay(for: zone, size: size)
                }
            }
            .clipped()
            .contentShape(Rectangle())
            .onTapGesture { location in
                if hitTestZone(at: location, canvasSize: size) == nil {
                    selectedZoneID = nil
                }
            }
        }
        .aspectRatio(16.0 / 10.0, contentMode: .fit)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }

    // MARK: - Canvas Background

    private func canvas(size: CGSize) -> some View {
        Canvas { context, drawSize in
            let color = Color(nsColor: .separatorColor).opacity(0.3)
            let divisions = snapToGrid ? gridDivisions : 12
            for i in 1..<divisions {
                let fraction = CGFloat(i) / CGFloat(divisions)
                let vx = fraction * drawSize.width
                context.stroke(Path { p in
                    p.move(to: CGPoint(x: vx, y: 0))
                    p.addLine(to: CGPoint(x: vx, y: drawSize.height))
                }, with: .color(color), lineWidth: 0.5)
                let hy = fraction * drawSize.height
                context.stroke(Path { p in
                    p.move(to: CGPoint(x: 0, y: hy))
                    p.addLine(to: CGPoint(x: drawSize.width, y: hy))
                }, with: .color(color), lineWidth: 0.5)
            }
        }
        .frame(width: size.width, height: size.height)
    }

    // MARK: - Zone View

    private func zoneView(zone: Zone, index: Int, size: CGSize) -> some View {
        let rect = canvasRect(for: zone.rect, in: size)
        let color = zoneColors[index % zoneColors.count]
        let isSelected = zone.id == selectedZoneID

        return ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(color.opacity(isSelected ? 0.35 : 0.2))
            RoundedRectangle(cornerRadius: 4)
                .stroke(isSelected ? Color.accentColor : color, lineWidth: isSelected ? 2.5 : 1.5)
            Text("\(index + 1)")
                .font(.system(size: min(rect.width, rect.height) * 0.3, weight: .bold, design: .rounded))
                .foregroundStyle(color.opacity(0.7))
        }
        .frame(width: rect.width, height: rect.height)
        .position(x: rect.midX, y: rect.midY)
        .onTapGesture {
            selectedZoneID = zone.id
        }
        .gesture(
            DragGesture(minimumDistance: 3)
                .onChanged { value in
                    if case .idle = interaction {
                        guard let idx = zones.firstIndex(where: { $0.id == zone.id }) else { return }
                        selectedZoneID = zone.id
                        interaction = .moving(idx)
                        dragOrigin = value.startLocation
                        originalRect = zones[idx].rect
                    }
                    if case .moving(let idx) = interaction {
                        let dx = (value.location.x - dragOrigin.x) / size.width
                        let dy = (value.location.y - dragOrigin.y) / size.height
                        zones[idx].rect.x = originalRect.x + dx
                        zones[idx].rect.y = originalRect.y + dy
                        applySnap(to: &zones[idx].rect)
                    }
                }
                .onEnded { _ in
                    interaction = .idle
                }
        )
    }

    // MARK: - Resize Handles (corners + edge midpoints)

    private func handlesOverlay(for zone: Zone, size: CGSize) -> some View {
        let rect = canvasRect(for: zone.rect, in: size)

        return ZStack {
            // Corner handles
            ForEach(Handle.corners, id: \.self) { handle in
                let pos = handlePosition(handle, rect: rect)
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: handleSize, height: handleSize)
                    .position(pos)
                    .gesture(resizeGesture(for: zone, handle: handle, canvasSize: size))
            }

            // Edge midpoint handles
            ForEach(Handle.edges, id: \.self) { handle in
                let pos = handlePosition(handle, rect: rect)
                let isHorizontal = handle == .midLeft || handle == .midRight
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.accentColor)
                    .frame(
                        width: isHorizontal ? 6 : edgeHandleLength,
                        height: isHorizontal ? edgeHandleLength : 6
                    )
                    .position(pos)
                    .gesture(resizeGesture(for: zone, handle: handle, canvasSize: size))
            }
        }
    }

    private func resizeGesture(for zone: Zone, handle: Handle, canvasSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                guard let idx = zones.firstIndex(where: { $0.id == zone.id }) else { return }
                if case .idle = interaction {
                    interaction = .resizing(idx, handle)
                    dragOrigin = value.startLocation
                    originalRect = zones[idx].rect
                }
                if case .resizing(let rIdx, let rHandle) = interaction {
                    applyResize(
                        index: rIdx,
                        handle: rHandle,
                        delta: CGSize(
                            width: (value.location.x - dragOrigin.x) / canvasSize.width,
                            height: (value.location.y - dragOrigin.y) / canvasSize.height
                        )
                    )
                }
            }
            .onEnded { _ in interaction = .idle }
    }

    // MARK: - Resize Logic

    private func applyResize(index: Int, handle: Handle, delta: CGSize) {
        var r = originalRect
        switch handle {
        case .topLeft:
            r.x += delta.width; r.y += delta.height
            r.width -= delta.width; r.height -= delta.height
        case .topRight:
            r.y += delta.height
            r.width += delta.width; r.height -= delta.height
        case .bottomLeft:
            r.x += delta.width
            r.width -= delta.width; r.height += delta.height
        case .bottomRight:
            r.width += delta.width; r.height += delta.height
        case .midTop:
            r.y += delta.height; r.height -= delta.height
        case .midBottom:
            r.height += delta.height
        case .midLeft:
            r.x += delta.width; r.width -= delta.width
        case .midRight:
            r.width += delta.width
        }
        applySnap(to: &r)
        zones[index].rect = r
    }

    // MARK: - Snap

    private func applySnap(to rect: inout RelativeRect) {
        if snapToGrid {
            rect.snapToGrid(divisions: gridDivisions)
        } else {
            rect.clamp()
        }
    }

    // MARK: - Helpers

    private func canvasRect(for relative: RelativeRect, in size: CGSize) -> CGRect {
        CGRect(
            x: relative.x * size.width,
            y: relative.y * size.height,
            width: relative.width * size.width,
            height: relative.height * size.height
        )
    }

    private func handlePosition(_ handle: Handle, rect: CGRect) -> CGPoint {
        switch handle {
        case .topLeft:     return CGPoint(x: rect.minX, y: rect.minY)
        case .topRight:    return CGPoint(x: rect.maxX, y: rect.minY)
        case .bottomLeft:  return CGPoint(x: rect.minX, y: rect.maxY)
        case .bottomRight: return CGPoint(x: rect.maxX, y: rect.maxY)
        case .midTop:      return CGPoint(x: rect.midX, y: rect.minY)
        case .midBottom:   return CGPoint(x: rect.midX, y: rect.maxY)
        case .midLeft:     return CGPoint(x: rect.minX, y: rect.midY)
        case .midRight:    return CGPoint(x: rect.maxX, y: rect.midY)
        }
    }

    private func hitTestZone(at point: CGPoint, canvasSize: CGSize) -> Int? {
        for (i, zone) in zones.enumerated().reversed() {
            if canvasRect(for: zone.rect, in: canvasSize).contains(point) {
                return i
            }
        }
        return nil
    }

    // MARK: - Types

    enum Interaction: Equatable {
        case idle
        case moving(Int)
        case resizing(Int, Handle)
    }

    enum Handle: CaseIterable, Hashable {
        case topLeft, topRight, bottomLeft, bottomRight
        case midTop, midBottom, midLeft, midRight

        static let corners: [Handle] = [.topLeft, .topRight, .bottomLeft, .bottomRight]
        static let edges: [Handle] = [.midTop, .midBottom, .midLeft, .midRight]
    }
}
