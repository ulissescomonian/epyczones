import CoreGraphics

/// Resolves which layout zones a cursor selects. Works in relative
/// coordinates (0–1, top-left origin) so it is independent of any screen.
enum ZoneHitTester {
    /// Returns the zone under `point` plus, near a shared border, the adjacent
    /// zones that a drop there should span: 2 zones on an edge, 3 at a
    /// T-junction, 4 at the centre of a grid.
    ///
    /// - Parameters:
    ///   - point: Cursor position relative to the screen's visible frame.
    ///   - zones: Zones of the active layout, in hotkey order.
    ///   - threshold: Border proximity, in relative units.
    static func zoneIndices(at point: CGPoint, in zones: [Zone], threshold: Double) -> Set<Int> {
        let relX = Double(point.x)
        let relY = Double(point.y)

        // First, find exact zone hit
        var exactHit: Int?
        for (index, zone) in zones.enumerated() {
            let r = zone.rect
            if relX >= r.x && relX < r.x + r.width && relY >= r.y && relY < r.y + r.height {
                exactHit = index
                break
            }
        }

        guard let primary = exactHit else { return [] }

        // Find all adjacent zones that share a border with the primary zone near the cursor.
        var result: Set<Int> = [primary]
        let pz = zones[primary].rect

        // Is cursor near each edge of the primary zone?
        let nearRight  = abs(relX - (pz.x + pz.width))  < threshold
        let nearLeft   = abs(relX - pz.x)               < threshold
        let nearBottom = abs(relY - (pz.y + pz.height)) < threshold
        let nearTop    = abs(relY - pz.y)               < threshold

        guard nearRight || nearLeft || nearBottom || nearTop else {
            return result
        }

        for (index, zone) in zones.enumerated() where index != primary {
            let r = zone.rect

            // Check vertical shared edge (left/right) — zones must overlap on Y axis
            let yOverlap = max(0, min(pz.y + pz.height, r.y + r.height) - max(pz.y, r.y))
            // Check horizontal shared edge (top/bottom) — zones must overlap on X axis
            let xOverlap = max(0, min(pz.x + pz.width, r.x + r.width) - max(pz.x, r.x))

            let isAdjacent =
                // Right edge: cursor near right of primary & zone starts there
                (nearRight  && yOverlap > 0.01 && abs(r.x - (pz.x + pz.width)) < threshold) ||
                // Left edge: cursor near left of primary & zone ends there
                (nearLeft   && yOverlap > 0.01 && abs((r.x + r.width) - pz.x) < threshold) ||
                // Bottom edge: cursor near bottom of primary & zone starts there
                (nearBottom && xOverlap > 0.01 && abs(r.y - (pz.y + pz.height)) < threshold) ||
                // Top edge: cursor near top of primary & zone ends there
                (nearTop    && xOverlap > 0.01 && abs((r.y + r.height) - pz.y) < threshold)

            if isAdjacent {
                result.insert(index)
            }
        }

        // If we found adjacent zones, also check if THEIR neighbors should be included.
        // E.g., in a 2x2 grid at the center: primary=topLeft finds right+bottom adjacent,
        // but the diagonal (bottomRight) is adjacent to both of those, not directly to primary.
        if result.count > 1 {
            let directAdjacent = result.subtracting([primary])
            for adjIdx in directAdjacent {
                let az = zones[adjIdx].rect
                for (index, zone) in zones.enumerated() where !result.contains(index) {
                    let r = zone.rect
                    // Check if this zone shares a border with the adjacent zone near the cursor
                    let yOvr = max(0, min(az.y + az.height, r.y + r.height) - max(az.y, r.y))
                    let xOvr = max(0, min(az.x + az.width, r.x + r.width) - max(az.x, r.x))

                    let isDiagonal =
                        (nearRight  && yOvr > 0.01 && abs(r.x - (az.x + az.width)) < threshold) ||
                        (nearLeft   && yOvr > 0.01 && abs((r.x + r.width) - az.x) < threshold) ||
                        (nearBottom && xOvr > 0.01 && abs(r.y - (az.y + az.height)) < threshold) ||
                        (nearTop    && xOvr > 0.01 && abs((r.y + r.height) - az.y) < threshold)

                    if isDiagonal {
                        result.insert(index)
                    }
                }
            }
        }

        return result
    }
}
