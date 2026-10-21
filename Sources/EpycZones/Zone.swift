import Foundation

/// A rectangle defined in relative coordinates (0.0–1.0), where (0,0) is the top-left of the screen.
struct RelativeRect: Codable, Equatable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    static let zero = RelativeRect(x: 0, y: 0, width: 0, height: 0)
    static let full = RelativeRect(x: 0, y: 0, width: 1, height: 1)

    init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    /// The inverse of `frame(in:)`: expresses an absolute frame (NSScreen
    /// coordinates, bottom-left origin) relative to `screenRect`.
    init(frame: CGRect, in screenRect: CGRect) {
        self.init(
            x: (frame.minX - screenRect.minX) / screenRect.width,
            y: 1.0 - (frame.maxY - screenRect.minY) / screenRect.height,
            width: frame.width / screenRect.width,
            height: frame.height / screenRect.height
        )
    }

    /// Convert to an absolute frame within a screen rect (NSScreen coordinates, bottom-left origin).
    /// Since RelativeRect uses top-left origin (y=0 is top), we flip Y for NSScreen.
    /// `gap` adds inset padding in points on each side.
    func frame(in screenRect: CGRect, gap: Double = 0) -> CGRect {
        let raw = CGRect(
            x: screenRect.origin.x + x * screenRect.width,
            y: screenRect.origin.y + (1.0 - y - height) * screenRect.height,
            width: width * screenRect.width,
            height: height * screenRect.height
        )
        guard gap > 0 else { return raw }
        return raw.insetBy(dx: gap, dy: gap)
    }

    /// Clamp all values so the rect stays within [0, 1].
    mutating func clamp() {
        x = Swift.max(0, Swift.min(x, 1 - width))
        y = Swift.max(0, Swift.min(y, 1 - height))
        width = Swift.max(0.05, Swift.min(width, 1 - x))
        height = Swift.max(0.05, Swift.min(height, 1 - y))
    }

    /// Smallest rect that contains every zone; `.zero` when there are none.
    static func bounding(_ zones: [Zone]) -> RelativeRect {
        guard let first = zones.first else { return .zero }
        var minX = first.rect.x
        var minY = first.rect.y
        var maxX = first.rect.x + first.rect.width
        var maxY = first.rect.y + first.rect.height
        for zone in zones.dropFirst() {
            minX = Swift.min(minX, zone.rect.x)
            minY = Swift.min(minY, zone.rect.y)
            maxX = Swift.max(maxX, zone.rect.x + zone.rect.width)
            maxY = Swift.max(maxY, zone.rect.y + zone.rect.height)
        }
        return RelativeRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// Snap values to a grid with the given number of divisions.
    mutating func snapToGrid(divisions: Int = 12) {
        let step = 1.0 / Double(divisions)
        x = (x / step).rounded() * step
        y = (y / step).rounded() * step
        width = Swift.max(step, (width / step).rounded() * step)
        height = Swift.max(step, (height / step).rounded() * step)
        clamp()
    }
}

/// A single zone within a layout.
struct Zone: Identifiable, Codable, Equatable {
    let id: UUID
    var rect: RelativeRect
    var name: String

    init(id: UUID = UUID(), rect: RelativeRect, name: String = "") {
        self.id = id
        self.rect = rect
        self.name = name
    }
}
