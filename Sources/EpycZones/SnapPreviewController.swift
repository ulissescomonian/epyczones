import AppKit

/// Shows a translucent "ghost" of the frame a window will snap to when dropped
/// near a screen edge. The panel itself is the ghost — its frame is the snap
/// target frame — so switching targets animates the panel sliding/morphing.
final class SnapPreviewController {
    private var panel: NSPanel?
    private(set) var target: EdgeSnapResolver.Target?

    var isVisible: Bool { panel != nil }

    func show(_ newTarget: EdgeSnapResolver.Target) {
        let frame = newTarget.position.frame(in: newTarget.screen.visibleFrame)

        if let panel = panel {
            if newTarget != target {
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.18
                    ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    panel.animator().setFrame(frame, display: true)
                }
            }
        } else {
            let p = NSPanel(
                contentRect: frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            p.level = .screenSaver
            p.backgroundColor = .clear
            p.isOpaque = false
            p.hasShadow = false
            p.ignoresMouseEvents = true
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            p.contentView = SnapGhostView()

            // Entrance: grow from the center of the target into place while fading in.
            let startFrame = frame.insetBy(dx: frame.width * 0.12, dy: frame.height * 0.12)
            p.setFrame(startFrame, display: false)
            p.alphaValue = 0
            p.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.22
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                p.animator().alphaValue = 1
                p.animator().setFrame(frame, display: true)
            }
            panel = p
        }
        target = newTarget
    }

    func hide() {
        target = nil
        panel?.orderOut(nil)
        panel = nil
    }
}

/// Same two-layer drawing as a highlighted zone in ZoneOverlayNSView:
/// thick accent border + tinted fill, with the dashed white ghost inside.
private final class SnapGhostView: NSView {
    private var antsTimer: Timer?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        antsTimer?.invalidate()
        antsTimer = nil
        guard window != nil else { return }
        antsTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.needsDisplay = true
        }
    }

    deinit {
        antsTimer?.invalidate()
    }

    override func draw(_ dirtyRect: NSRect) {
        let accent = NSColor.systemBlue

        // Outer: highlighted zone (thick border + tinted fill)
        let zoneRect = bounds.insetBy(dx: 4, dy: 4)
        let zonePath = NSBezierPath(roundedRect: zoneRect, xRadius: 10, yRadius: 10)
        accent.withAlphaComponent(0.35).setFill()
        zonePath.fill()
        accent.withAlphaComponent(0.9).setStroke()
        zonePath.lineWidth = 3
        zonePath.stroke()

        // Inner: ghost window outline (dashed white, marching ants)
        let ghostRect = zoneRect.insetBy(dx: 4, dy: 4)
        let ghostPath = NSBezierPath(roundedRect: ghostRect, xRadius: 8, yRadius: 8)
        accent.withAlphaComponent(0.12).setFill()
        ghostPath.fill()
        NSColor.white.withAlphaComponent(0.6).setStroke()
        ghostPath.lineWidth = 2
        let pattern: [CGFloat] = [6, 4]
        ghostPath.setLineDash(pattern, count: 2, phase: Self.marchingAntsPhase())
        ghostPath.stroke()
    }

    /// Dash phase derived from the clock — advances the dashes ~1.5 periods/s.
    static func marchingAntsPhase() -> CGFloat {
        -CGFloat((CACurrentMediaTime() * 15).truncatingRemainder(dividingBy: 10))
    }

    // Redraw on every animation tick so the dashed border stays crisp while
    // the panel morphs between snap targets.
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsDisplay = true
    }
}
