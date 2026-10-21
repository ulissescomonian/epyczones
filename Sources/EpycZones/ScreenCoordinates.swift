import AppKit

/// Conversions between the two global coordinate spaces EpycZones works in.
///
/// AppKit (`NSScreen`, `NSEvent.mouseLocation`) puts the origin at the
/// bottom-left of the primary display, with y growing up. Accessibility and
/// CGWindowList put it at the top-left of the primary display, with y growing
/// down. Every conversion between the two goes through here.
enum ScreenCoordinates {
    /// Height of the primary display, the axis both spaces flip around.
    static var primaryDisplayHeight: CGFloat {
        NSScreen.screens.first?.frame.height ?? 0
    }

    /// The AX position (top-left corner) of a frame given in AppKit coordinates.
    static func axOrigin(of nsFrame: CGRect, primaryHeight: CGFloat = primaryDisplayHeight) -> CGPoint {
        CGPoint(x: nsFrame.minX, y: primaryHeight - nsFrame.maxY)
    }

    /// The AppKit frame of a window from its AX position and size.
    static func nsFrame(
        axOrigin: CGPoint,
        size: CGSize,
        primaryHeight: CGFloat = primaryDisplayHeight
    ) -> CGRect {
        CGRect(x: axOrigin.x, y: primaryHeight - axOrigin.y - size.height, width: size.width, height: size.height)
    }

    /// A single point in the other space. The flip is its own inverse.
    static func flipped(_ point: CGPoint, primaryHeight: CGFloat = primaryDisplayHeight) -> CGPoint {
        CGPoint(x: point.x, y: primaryHeight - point.y)
    }
}

extension CGRect {
    /// Origin and size each within `tolerance` of the other rect's.
    func isClose(to other: CGRect, tolerance: CGFloat) -> Bool {
        abs(origin.x - other.origin.x) < tolerance
            && abs(origin.y - other.origin.y) < tolerance
            && abs(width - other.width) < tolerance
            && abs(height - other.height) < tolerance
    }
}
