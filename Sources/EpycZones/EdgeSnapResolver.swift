import AppKit

/// Resolves a cursor position near a screen edge to a fixed snap target,
/// Aero Snap style: edges → halves, corners → quarters.
/// Independent of the active layout — layout zones are the Shift+drag path.
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

        guard let position = position(
            at: point,
            in: screen.frame,
            threshold: AppSettings.shared.edgeSnapThreshold,
            topEdgeMaximizes: AppSettings.shared.edgeSnapTopMaximize
        ) else { return nil }
        return Target(position: position, screen: screen)
    }

    /// Classifies a point against one screen frame (NSScreen coordinates,
    /// bottom-left origin) without consulting global state.
    static func position(
        at point: NSPoint,
        in f: CGRect,
        threshold: Double,
        topEdgeMaximizes: Bool
    ) -> SnapPosition? {
        let nearLeft   = point.x <= f.minX + threshold
        let nearRight  = point.x >= f.maxX - threshold
        let nearTop    = point.y >= f.maxY - threshold
        let nearBottom = point.y <= f.minY + threshold
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
