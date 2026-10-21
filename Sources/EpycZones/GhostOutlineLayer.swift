import AppKit
import QuartzCore

/// The dashed "ghost window" outline shared by the zone overlay and the
/// edge-snap preview.
///
/// The dashes march through a Core Animation phase animation, so the render
/// server moves them; the host views used to redraw their whole area on the
/// CPU 30 times a second for the same effect. With Reduce Motion on, the
/// dashes stand still.
final class GhostOutlineLayer: CAShapeLayer {
    /// One dash period (6 + 4 pt) every 10/15 s: about 1.5 periods a second.
    private static let periodDuration: CFTimeInterval = 10.0 / 15.0
    private static let cornerRadius: CGFloat = 8

    override init() {
        super.init()
        fillColor = NSColor.systemBlue.withAlphaComponent(0.12).cgColor
        strokeColor = NSColor.white.withAlphaComponent(0.6).cgColor
        lineWidth = 2
        lineDashPattern = [6, 4]
        // Path and visibility changes apply at once, without implicit animation.
        actions = ["path": NSNull(), "hidden": NSNull()]
        startMarching()
    }

    /// Used by Core Animation to copy the layer for rendering.
    override init(layer: Any) {
        super.init(layer: layer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// Outlines `rect`, in the host layer's coordinates, with rounded corners.
    func outline(_ rect: CGRect) {
        guard rect.width > 0, rect.height > 0 else {
            path = nil
            return
        }
        // CGPath requires each corner radius to fit within half the rect.
        let radius = min(Self.cornerRadius, rect.width / 2, rect.height / 2)
        path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    }

    private func startMarching() {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let march = CABasicAnimation(keyPath: "lineDashPhase")
        march.fromValue = 0
        march.toValue = -10
        march.duration = Self.periodDuration
        march.repeatCount = .infinity
        add(march, forKey: "marchingAnts")
    }
}
