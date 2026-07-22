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

        let f = screen.frame
        let threshold = AppSettings.shared.edgeSnapThreshold
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

        let position: SnapPosition
        if nearLeft {
            position = inTopBand ? .topLeftQuarter : inBottomBand ? .bottomLeftQuarter : .leftHalf
        } else if nearRight {
            position = inTopBand ? .topRightQuarter : inBottomBand ? .bottomRightQuarter : .rightHalf
        } else if nearTop {
            let topCenter: SnapPosition = AppSettings.shared.edgeSnapTopMaximize ? .maximize : .topHalf
            position = inLeftBand ? .topLeftQuarter : inRightBand ? .topRightQuarter : topCenter
        } else {
            position = inLeftBand ? .bottomLeftQuarter : inRightBand ? .bottomRightQuarter : .bottomHalf
        }
        return Target(position: position, screen: screen)
    }
}
