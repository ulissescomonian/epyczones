import Foundation

/// Pure geometry behind the layout editor: splitting and merging zones,
/// the dividers that neighboring zones share, snapping, and the checks that
/// warn about a layout. Rects are relative to the display's visible area,
/// with the origin at the top left.
enum LayoutGeometry {
    /// Two edges closer than this are the same edge (0.01% of the display).
    static let tolerance = 1e-4
    /// Step of the snapping grid. 1/24 holds halves, thirds, quarters,
    /// sixths, eighths and 62.5%.
    static let gridStep = 1.0 / 24.0
    /// Smallest zone side the editor creates.
    static let minimumSpan = gridStep

    /// The orientation of a line between zones: a vertical line separates
    /// columns, a horizontal one separates rows.
    enum Orientation: Hashable {
        case vertical, horizontal
    }

    // MARK: - Split

    /// Cuts a zone in two equal halves along `orientation`. The first half
    /// keeps the zone and its number; the second becomes a new zone at the
    /// end, so the shortcuts of the other zones do not change. Nil when the
    /// halves would be smaller than `minimumSpan`.
    static func split(_ zones: [Zone], zoneID: UUID, by orientation: Orientation) -> (zones: [Zone], newZoneID: UUID)? {
        guard let index = zones.firstIndex(where: { $0.id == zoneID }) else { return nil }
        var first = zones[index].rect
        var second = first
        switch orientation {
        case .vertical:
            let half = first.width / 2
            guard half >= minimumSpan - tolerance else { return nil }
            first.width = half
            second.x = first.x + half
            second.width = half
        case .horizontal:
            let half = first.height / 2
            guard half >= minimumSpan - tolerance else { return nil }
            first.height = half
            second.y = first.y + half
            second.height = half
        }
        var result = zones
        result[index].rect = first
        let newZone = Zone(rect: second)
        result.append(newZone)
        return (result, newZone.id)
    }

    // MARK: - Merge

    enum Side: Hashable {
        case left, right, top, bottom
    }

    struct Neighbor: Equatable {
        let zoneID: UUID
        let side: Side
    }

    /// Zones that share a whole edge with `zoneID`, so the two together form
    /// a rectangle. In zone order.
    static func mergeableNeighbors(of zoneID: UUID, in zones: [Zone]) -> [Neighbor] {
        guard let zone = zones.first(where: { $0.id == zoneID }) else { return [] }
        let a = zone.rect
        return zones.compactMap { other -> Neighbor? in
            guard other.id != zoneID else { return nil }
            let b = other.rect
            let sameRows = close(a.y, b.y) && close(a.height, b.height)
            let sameColumns = close(a.x, b.x) && close(a.width, b.width)
            if sameRows && close(b.x, a.maxX) { return Neighbor(zoneID: other.id, side: .right) }
            if sameRows && close(b.maxX, a.x) { return Neighbor(zoneID: other.id, side: .left) }
            if sameColumns && close(b.y, a.maxY) { return Neighbor(zoneID: other.id, side: .bottom) }
            if sameColumns && close(b.maxY, a.y) { return Neighbor(zoneID: other.id, side: .top) }
            return nil
        }
    }

    /// Joins two neighbors into one zone. The one with the lower number
    /// survives with the combined rect and keeps its name, or takes the
    /// other's when it has none. Nil when they do not form a rectangle.
    static func merge(_ zones: [Zone], zoneID: UUID, with otherID: UUID) -> [Zone]? {
        guard let a = zones.firstIndex(where: { $0.id == zoneID }),
              let b = zones.firstIndex(where: { $0.id == otherID }),
              mergeableNeighbors(of: zoneID, in: zones).contains(where: { $0.zoneID == otherID }) else { return nil }
        let keep = min(a, b)
        let drop = max(a, b)
        var result = zones
        result[keep].rect = zones[a].rect.union(zones[b].rect)
        if result[keep].name.isEmpty {
            result[keep].name = zones[drop].name
        }
        result.remove(at: drop)
        return result
    }

    // MARK: - Dividers

    /// A line where zones on one side end and zones on the other begin.
    /// Dragging it resizes both sides together, so no gap or overlap appears.
    struct Divider: Equatable, Identifiable {
        let orientation: Orientation
        /// x of a vertical divider, y of a horizontal one.
        let position: Double
        /// Extent along the line: y range of a vertical divider, x range of
        /// a horizontal one.
        let start: Double
        let end: Double
        /// Zones that end at the line (left or above) and that begin at it.
        let leading: Set<UUID>
        let trailing: Set<UUID>

        /// Stable while the divider is dragged: it names the zones, not the position.
        var id: String {
            let ids = (leading.map { "L\($0.uuidString)" } + trailing.map { "T\($0.uuidString)" }).sorted()
            return "\(orientation)|" + ids.joined(separator: ",")
        }

        var zoneIDs: Set<UUID> { leading.union(trailing) }
    }

    /// The dividers of a layout, each the shortest stretch of line between
    /// zones that touch across it. In a grid, the line between the columns is
    /// one divider per row; `line(through:in:)` joins them.
    static func dividers(in zones: [Zone]) -> [Divider] {
        [Orientation.vertical, .horizontal].flatMap { orientation in
            positions(of: orientation, in: zones).flatMap { position in
                groups(at: position, orientation: orientation, in: zones, joiningCrossings: false)
            }
        }
    }

    /// The whole line `divider` belongs to, continuing across the points
    /// where other dividers cross it. Moving it keeps a grid a grid.
    static func line(through divider: Divider, in zones: [Zone]) -> Divider {
        groups(at: divider.position, orientation: divider.orientation, in: zones, joiningCrossings: true)
            .first { !$0.zoneIDs.isDisjoint(with: divider.zoneIDs) } ?? divider
    }

    /// Where `divider` may move: each side keeps `minimumSpan`, and no zone
    /// grows into a zone that is not part of the divider.
    static func range(of divider: Divider, in zones: [Zone]) -> ClosedRange<Double> {
        let leading = zones.filter { divider.leading.contains($0.id) }
        let trailing = zones.filter { divider.trailing.contains($0.id) }
        let others = zones.filter { !divider.zoneIDs.contains($0.id) }
        let p = divider.position

        var lower = 0.0
        var upper = 1.0
        for zone in leading {
            lower = max(lower, zone.rect.minAlong(divider.orientation) + minimumSpan)
        }
        for zone in trailing {
            upper = min(upper, zone.rect.maxAlong(divider.orientation) - minimumSpan)
        }
        for other in others {
            let r = other.rect
            // Trailing zones grow back toward zones that end before the line.
            if r.maxAlong(divider.orientation) <= p + tolerance,
               trailing.contains(where: { $0.rect.overlapsAcross(r, divider.orientation) }) {
                lower = max(lower, r.maxAlong(divider.orientation))
            }
            // Leading zones grow forward toward zones that begin after it.
            if r.minAlong(divider.orientation) >= p - tolerance,
               leading.contains(where: { $0.rect.overlapsAcross(r, divider.orientation) }) {
                upper = min(upper, r.minAlong(divider.orientation))
            }
        }
        // A side already below the minimum may still grow, never shrink further.
        lower = min(lower, p)
        upper = max(upper, p)
        return lower...upper
    }

    /// Moves `divider` to `position`, clamped to `range(of:in:)`.
    static func move(_ divider: Divider, to position: Double, in zones: [Zone]) -> [Zone] {
        let allowed = range(of: divider, in: zones)
        let target = min(max(position, allowed.lowerBound), allowed.upperBound)
        return zones.map { zone in
            var zone = zone
            if divider.leading.contains(zone.id) {
                switch divider.orientation {
                case .vertical: zone.rect.width = target - zone.rect.x
                case .horizontal: zone.rect.height = target - zone.rect.y
                }
            } else if divider.trailing.contains(zone.id) {
                switch divider.orientation {
                case .vertical:
                    zone.rect.width = zone.rect.maxX - target
                    zone.rect.x = target
                case .horizontal:
                    zone.rect.height = zone.rect.maxY - target
                    zone.rect.y = target
                }
            }
            return zone
        }
    }

    /// Inner positions where some zone has an edge across `orientation`.
    private static func positions(of orientation: Orientation, in zones: [Zone]) -> [Double] {
        var values: [Double] = []
        for zone in zones {
            for value in [zone.rect.minAlong(orientation), zone.rect.maxAlong(orientation)]
            where value > tolerance && value < 1 - tolerance && !values.contains(where: { close($0, value) }) {
                values.append(value)
            }
        }
        return values.sorted()
    }

    /// The groups of zones that meet at one line. Zones on opposite sides
    /// connect where they face each other over some length; with
    /// `joiningCrossings`, stretches that merely touch end to end connect too.
    private static func groups(
        at position: Double,
        orientation: Orientation,
        in zones: [Zone],
        joiningCrossings: Bool
    ) -> [Divider] {
        struct Item {
            let zone: Zone
            let isLeading: Bool
            let start: Double
            let end: Double
        }
        var items: [Item] = []
        for zone in zones {
            let r = zone.rect
            let span = r.spanAcross(orientation)
            if close(r.maxAlong(orientation), position) {
                items.append(Item(zone: zone, isLeading: true, start: span.lowerBound, end: span.upperBound))
            } else if close(r.minAlong(orientation), position) {
                items.append(Item(zone: zone, isLeading: false, start: span.lowerBound, end: span.upperBound))
            }
        }

        // Union-find over the items.
        var parent = Array(items.indices)
        func root(_ i: Int) -> Int {
            var i = i
            while parent[i] != i { i = parent[i] }
            return i
        }
        var paired = Set<Int>()
        for i in items.indices {
            for j in items.indices where j > i {
                let overlap = min(items[i].end, items[j].end) - max(items[i].start, items[j].start)
                let faces = items[i].isLeading != items[j].isLeading && overlap > tolerance
                let touches = joiningCrossings && overlap >= -tolerance
                guard faces || touches else { continue }
                if faces { paired.formUnion([i, j]) }
                parent[root(i)] = root(j)
            }
        }

        var components: [Int: [Int]] = [:]
        for i in items.indices where paired.contains(i) || joiningCrossings {
            components[root(i), default: []].append(i)
        }
        return components.values.compactMap { members -> Divider? in
            let leading = members.filter { items[$0].isLeading }
            let trailing = members.filter { !items[$0].isLeading }
            guard members.contains(where: paired.contains), !leading.isEmpty, !trailing.isEmpty else { return nil }
            return Divider(
                orientation: orientation,
                position: position,
                start: members.map { items[$0].start }.min() ?? 0,
                end: members.map { items[$0].end }.max() ?? 1,
                leading: Set(leading.map { items[$0].zone.id }),
                trailing: Set(trailing.map { items[$0].zone.id })
            )
        }
        .sorted { $0.start < $1.start }
    }

    // MARK: - Snapping

    /// `value` pulled to the nearest grid line when `grid` is on, or else to
    /// the nearest of `edges` within `threshold`.
    static func snap(_ value: Double, grid: Bool, edges: [Double] = [], threshold: Double = 0.01) -> Double {
        if grid {
            return (value / gridStep).rounded() * gridStep
        }
        let nearest = edges.min { abs($0 - value) < abs($1 - value) }
        if let nearest, abs(nearest - value) <= threshold {
            return nearest
        }
        return value
    }

    /// Edges that move with a free zone.
    struct Edges: OptionSet, Hashable {
        let rawValue: Int
        static let left = Edges(rawValue: 1 << 0)
        static let right = Edges(rawValue: 1 << 1)
        static let top = Edges(rawValue: 1 << 2)
        static let bottom = Edges(rawValue: 1 << 3)
    }

    /// `rect` with `edges` moved by the deltas, snapped, inside the display
    /// and at least `minimumSpan` on each side.
    static func resize(_ rect: RelativeRect, edges: Edges, dx: Double, dy: Double, grid: Bool) -> RelativeRect {
        var minX = rect.x
        var maxX = rect.maxX
        var minY = rect.y
        var maxY = rect.maxY
        if edges.contains(.left) {
            minX = min(max(0, snap(minX + dx, grid: grid)), maxX - minimumSpan)
        }
        if edges.contains(.right) {
            maxX = max(min(1, snap(maxX + dx, grid: grid)), minX + minimumSpan)
        }
        if edges.contains(.top) {
            minY = min(max(0, snap(minY + dy, grid: grid)), maxY - minimumSpan)
        }
        if edges.contains(.bottom) {
            maxY = max(min(1, snap(maxY + dy, grid: grid)), minY + minimumSpan)
        }
        return RelativeRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// `rect` moved by the deltas, snapped, and kept inside the display.
    static func move(_ rect: RelativeRect, dx: Double, dy: Double, grid: Bool) -> RelativeRect {
        var moved = rect
        moved.x = min(max(0, snap(rect.x + dx, grid: grid)), 1 - rect.width)
        moved.y = min(max(0, snap(rect.y + dy, grid: grid)), 1 - rect.height)
        return moved
    }

    // MARK: - Order

    /// Zones in reading order: top to bottom, then left to right.
    static func sortedByPosition(_ zones: [Zone]) -> [Zone] {
        zones.sorted { a, b in
            if !close(a.rect.y, b.rect.y) { return a.rect.y < b.rect.y }
            return a.rect.x < b.rect.x
        }
    }

    // MARK: - Checks

    enum Issue: Hashable {
        /// No zones: dragging shows nothing on this display.
        case empty
        /// Part of the display, as a fraction of its area, is in no zone.
        case uncovered(fraction: Double)
        /// Two zones, by index, cover the same area.
        case overlap(Int, Int)
        /// Zones past the ninth have no keyboard shortcut.
        case withoutShortcut(count: Int)
    }

    /// Smallest uncovered share of the display worth reporting.
    static let reportableUncoveredFraction = 0.001

    static func issues(in zones: [Zone]) -> [Issue] {
        guard !zones.isEmpty else { return [.empty] }
        var issues: [Issue] = []
        let uncovered = uncoveredRegions(in: zones).reduce(0) { $0 + $1.width * $1.height }
        if uncovered >= reportableUncoveredFraction {
            issues.append(.uncovered(fraction: uncovered))
        }
        for i in zones.indices {
            for j in zones.indices where j > i && zones[i].rect.overlaps(zones[j].rect) {
                issues.append(.overlap(i, j))
            }
        }
        if zones.count > 9 {
            issues.append(.withoutShortcut(count: zones.count - 9))
        }
        return issues
    }

    /// Parts of the display that no zone covers, as row strips.
    static func uncoveredRegions(in zones: [Zone]) -> [RelativeRect] {
        let xs = edges(zones.flatMap { [$0.rect.x, $0.rect.maxX] })
        let ys = edges(zones.flatMap { [$0.rect.y, $0.rect.maxY] })
        var regions: [RelativeRect] = []
        for row in 0..<(ys.count - 1) {
            let y0 = ys[row], y1 = ys[row + 1]
            var stripStart: Double?
            for column in 0..<(xs.count - 1) {
                let x0 = xs[column], x1 = xs[column + 1]
                let center = (x: (x0 + x1) / 2, y: (y0 + y1) / 2)
                let covered = zones.contains { $0.rect.contains(center.x, center.y) }
                if !covered, stripStart == nil {
                    stripStart = x0
                } else if covered, let start = stripStart {
                    regions.append(RelativeRect(x: start, y: y0, width: x0 - start, height: y1 - y0))
                    stripStart = nil
                }
            }
            if let start = stripStart {
                regions.append(RelativeRect(x: start, y: y0, width: 1 - start, height: y1 - y0))
            }
        }
        return regions
    }

    /// Distinct cut positions inside [0, 1], with both ends.
    private static func edges(_ values: [Double]) -> [Double] {
        var result = [0.0, 1.0]
        for value in values where value > tolerance && value < 1 - tolerance && !result.contains(where: { close($0, value) }) {
            result.append(value)
        }
        return result.sorted()
    }

    static func close(_ a: Double, _ b: Double) -> Bool {
        abs(a - b) < tolerance
    }
}

// MARK: - RelativeRect Geometry

extension RelativeRect {
    var maxX: Double { x + width }
    var maxY: Double { y + height }

    func union(_ other: RelativeRect) -> RelativeRect {
        let minX = Swift.min(x, other.x)
        let minY = Swift.min(y, other.y)
        return RelativeRect(
            x: minX,
            y: minY,
            width: Swift.max(maxX, other.maxX) - minX,
            height: Swift.max(maxY, other.maxY) - minY
        )
    }

    /// True when the two share an area, not just an edge.
    func overlaps(_ other: RelativeRect) -> Bool {
        let w = Swift.min(maxX, other.maxX) - Swift.max(x, other.x)
        let h = Swift.min(maxY, other.maxY) - Swift.max(y, other.y)
        return w > LayoutGeometry.tolerance && h > LayoutGeometry.tolerance
    }

    func contains(_ px: Double, _ py: Double) -> Bool {
        px >= x && px <= maxX && py >= y && py <= maxY
    }

    /// The edge position across which a divider of `orientation` runs.
    fileprivate func minAlong(_ orientation: LayoutGeometry.Orientation) -> Double {
        orientation == .vertical ? x : y
    }

    fileprivate func maxAlong(_ orientation: LayoutGeometry.Orientation) -> Double {
        orientation == .vertical ? maxX : maxY
    }

    /// The extent along a divider of `orientation`.
    fileprivate func spanAcross(_ orientation: LayoutGeometry.Orientation) -> ClosedRange<Double> {
        orientation == .vertical ? y...maxY : x...maxX
    }

    /// True when the two face each other across a divider of `orientation`.
    fileprivate func overlapsAcross(_ other: RelativeRect, _ orientation: LayoutGeometry.Orientation) -> Bool {
        let a = spanAcross(orientation)
        let b = other.spanAcross(orientation)
        return Swift.min(a.upperBound, b.upperBound) - Swift.max(a.lowerBound, b.lowerBound) > LayoutGeometry.tolerance
    }
}
