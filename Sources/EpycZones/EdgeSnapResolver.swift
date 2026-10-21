import AppKit

/// Resolves a cursor position near a screen edge to a fixed snap target,
/// Aero Snap style: edges → halves, corners → quarters.
/// Independent of the active layout — layout zones are the Shift+drag path.
@MainActor
enum EdgeSnapResolver {
    struct Target: Equatable {
        let position: SnapPosition
        let screen: NSScreen
    }

    static func resolve(at point: NSPoint) -> Target? {
        // insetBy(-1): NSRect.contains excludes max edges, but the cursor can
        // sit exactly on them when clamped at the screen border.
        guard let screen = NSScreen.screens.first(where: {
            $0.frame.insetBy(dx: -1, dy: -1).contains(point)
        }) else { return nil }

        let neighbors = AppSettings.shared.edgeSnapIgnoresSharedEdges
            ? NSScreen.screens.filter { $0 != screen }.map(\.frame)
            : []
        guard let position = position(
            at: point,
            in: screen.frame,
            threshold: AppSettings.shared.edgeSnapThreshold,
            topEdgeMaximizes: AppSettings.shared.edgeSnapTopMaximize,
            neighborFrames: neighbors
        ) else { return nil }
        return Target(position: position, screen: screen)
    }

    /// Classifies a point against one screen frame (NSScreen coordinates,
    /// bottom-left origin) without consulting global state.
    ///
    /// - Parameter neighborFrames: Other displays. Where one of them continues
    ///   past an edge at the cursor's position, that stretch of edge is a
    ///   passage to it, not a snap target.
    nonisolated static func position(
        at point: NSPoint,
        in f: CGRect,
        threshold: Double,
        topEdgeMaximizes: Bool,
        neighborFrames: [CGRect] = []
    ) -> SnapPosition? {
        func isOpen(beyond probe: CGPoint) -> Bool {
            !neighborFrames.contains { $0.contains(probe) }
        }
        let nearLeft   = point.x <= f.minX + threshold && isOpen(beyond: CGPoint(x: f.minX - 1, y: point.y))
        let nearRight  = point.x >= f.maxX - threshold && isOpen(beyond: CGPoint(x: f.maxX + 1, y: point.y))
        let nearTop    = point.y >= f.maxY - threshold && isOpen(beyond: CGPoint(x: point.x, y: f.maxY + 1))
        let nearBottom = point.y <= f.minY + threshold && isOpen(beyond: CGPoint(x: point.x, y: f.minY - 1))
        guard nearLeft || nearRight || nearTop || nearBottom else { return nil }

        // Corner box: how far along the edge from a corner still counts as that corner.
        let corner = min(max(f.height * 0.15, 80), 200)
        let inTopBand    = point.y >= f.maxY - corner
        let inBottomBand = point.y <= f.minY + corner
        let inLeftBand   = point.x <= f.minX + corner
        let inRightBand  = point.x >= f.maxX - corner

        if nearLeft {
            return inTopBand ? .topLeftQuarter : inBottomBand ? .bottomLeftQuarter : .leftHalf
        } else if nearRight {
            return inTopBand ? .topRightQuarter : inBottomBand ? .bottomRightQuarter : .rightHalf
        } else if nearTop {
            let topCenter: SnapPosition = topEdgeMaximizes ? .maximize : .topHalf
            return inLeftBand ? .topLeftQuarter : inRightBand ? .topRightQuarter : topCenter
        } else {
            return inLeftBand ? .bottomLeftQuarter : inRightBand ? .bottomRightQuarter : .bottomHalf
        }
    }
}
