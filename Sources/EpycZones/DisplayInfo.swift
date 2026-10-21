import AppKit

/// A connected display as the Layouts window shows it: a value copy of what
/// it needs from `NSScreen`, so views and screen renders never hold screens.
struct DisplayInfo: Identifiable, Equatable {
    /// The display UUID.
    let id: String
    let name: String
    /// Frame in global AppKit coordinates, for the arrangement map.
    let frame: CGRect
    /// The area that zones divide: the display without the menu bar and Dock.
    let visibleFrame: CGRect
    let backingScale: CGFloat
    /// The display with the menu bar.
    let isPrimary: Bool

    /// Width over height of the area zones divide.
    var aspectRatio: CGFloat {
        visibleFrame.width / max(1, visibleFrame.height)
    }

    var isPortrait: Bool { frame.height > frame.width }

    var symbol: String { isPortrait ? "rectangle.portrait" : "display" }

    /// Resolution in pixels, as Displays settings describes it.
    var resolutionDescription: String {
        let width = Int((frame.width * backingScale).rounded())
        let height = Int((frame.height * backingScale).rounded())
        return "\(width) × \(height)"
    }

    /// Pixel size of a zone with this relative rect.
    func pixelSize(of rect: RelativeRect) -> (width: Int, height: Int) {
        (
            Int((rect.width * visibleFrame.width * backingScale).rounded()),
            Int((rect.height * visibleFrame.height * backingScale).rounded())
        )
    }

    /// Connected displays from left to right, as arranged in Displays settings.
    @MainActor
    static func connected() -> [DisplayInfo] {
        NSScreen.screens.enumerated().compactMap { index, screen -> DisplayInfo? in
            guard let uuid = screen.displayUUID() else { return nil }
            return DisplayInfo(
                id: uuid,
                name: screen.localizedName,
                frame: screen.frame,
                visibleFrame: screen.visibleFrame,
                backingScale: screen.backingScaleFactor,
                isPrimary: index == 0
            )
        }
        .sorted { ($0.frame.minX, -$0.frame.maxY) < ($1.frame.minX, -$1.frame.maxY) }
    }

    @MainActor
    var screen: NSScreen? {
        NSScreen.screens.first { $0.displayUUID() == id }
    }
}
