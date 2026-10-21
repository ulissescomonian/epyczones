import AppKit

/// Manages transparent overlay panels that show zone regions on screen.
@MainActor
final class ZoneOverlayController {
    private var panels: [NSPanel] = []
    private var overlayViews: [ZoneOverlayNSView] = []
    private var viewScreens: [NSScreen] = []

    /// Currently highlighted zone indices (can be multiple for spanning).
    private(set) var highlightedZoneIndices: Set<Int> = []
    /// The screen the highlight is on.
    private(set) var highlightedScreen: NSScreen?

    /// Show overlay on all screens using a per-screen layout provider.
    func show(layoutProvider: (NSScreen) -> Layout?) {
        hide()

        for screen in NSScreen.screens {
            guard let layout = layoutProvider(screen) else { continue }

            let panel = NSPanel(
                contentRect: screen.frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.level = .screenSaver
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = false
            panel.ignoresMouseEvents = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

            let view = ZoneOverlayNSView(
                layout: layout,
                screenFrame: screen.frame,
                visibleFrame: screen.visibleFrame
            )
            panel.contentView = view
            panel.orderFrontRegardless()

            panels.append(panel)
            overlayViews.append(view)
            viewScreens.append(screen)
        }
    }

    /// Update highlight — only on the given screen, clear all others.
    func updateHighlight(zoneIndices: Set<Int>, on screen: NSScreen?) {
        if zoneIndices == highlightedZoneIndices && highlightedScreen == screen { return }
        highlightedZoneIndices = zoneIndices
        highlightedScreen = screen

        for (i, view) in overlayViews.enumerated() {
            let isActiveScreen = screen != nil && viewScreens[i] == screen!
            view.highlightedZoneIndices = isActiveScreen ? zoneIndices : []
            view.needsDisplay = true
        }
    }

    func hide() {
        highlightedZoneIndices = []
        highlightedScreen = nil
        for panel in panels {
            panel.orderOut(nil)
        }
        panels.removeAll()
        overlayViews.removeAll()
        viewScreens.removeAll()
    }
}

// MARK: - Overlay NSView

final class ZoneOverlayNSView: NSView {
    let layout: Layout
    let screenFrame: NSRect
    let visibleFrame: NSRect
    var highlightedZoneIndices: Set<Int> = [] {
        didSet { updateGhost() }
    }

    /// Ghost "window" over the highlighted zones; animates on its own, so the
    /// view only redraws when the highlight changes.
    private let ghostLayer = GhostOutlineLayer()

    /// Inset of each drawn zone from its slot, in points.
    private static let zoneInset: CGFloat = 4

    private let zoneColors: [NSColor] = [
        .systemBlue, .systemGreen, .systemOrange, .systemPurple,
        .systemPink, .systemTeal, .systemIndigo, .systemMint,
        .systemCyan, .systemRed,
    ]

    init(layout: Layout, screenFrame: NSRect, visibleFrame: NSRect) {
        self.layout = layout
        self.screenFrame = screenFrame
        self.visibleFrame = visibleFrame
        super.init(frame: NSRect(origin: .zero, size: screenFrame.size))
        wantsLayer = true
        ghostLayer.isHidden = true
        layer?.addSublayer(ghostLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if ghostLayer.superlayer == nil {
            layer?.addSublayer(ghostLayer)
        }
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        ghostLayer.contentsScale = window?.backingScaleFactor ?? 1
    }

    /// The screen's visible frame in this view's coordinates.
    private var visibleFrameLocal: NSRect {
        NSRect(
            x: visibleFrame.origin.x - screenFrame.origin.x,
            y: visibleFrame.origin.y - screenFrame.origin.y,
            width: visibleFrame.width,
            height: visibleFrame.height
        )
    }

    /// Places the ghost over the combined highlighted zones, 4 pt inside them.
    private func updateGhost() {
        let zones = highlightedZoneIndices.compactMap { index -> Zone? in
            index < layout.zones.count ? layout.zones[index] : nil
        }
        guard !zones.isEmpty else {
            ghostLayer.isHidden = true
            return
        }

        let vfLocal = visibleFrameLocal
        let combined = RelativeRect.bounding(zones)
        let inset = Self.zoneInset + 4
        ghostLayer.outline(NSRect(
            x: vfLocal.origin.x + combined.x * vfLocal.width + inset,
            y: vfLocal.origin.y + (1.0 - combined.y - combined.height) * vfLocal.height + inset,
            width: combined.width * vfLocal.width - inset * 2,
            height: combined.height * vfLocal.height - inset * 2
        ))
        ghostLayer.isHidden = false
    }

    override func draw(_ dirtyRect: NSRect) {
        let isDark = AppSettings.shared.overlayIsDark

        // Background tint
        let bgColor = isDark
            ? NSColor.black.withAlphaComponent(0.15)
            : NSColor.white.withAlphaComponent(0.25)
        bgColor.setFill()
        bounds.fill()

        let vfLocal = visibleFrameLocal
        let gap = Self.zoneInset
        let baseColor = isDark ? NSColor.white : NSColor.black

        for (index, zone) in layout.zones.enumerated() {
            let isHighlighted = highlightedZoneIndices.contains(index)
            let accentColor = zoneColors[index % zoneColors.count]

            let rect = NSRect(
                x: vfLocal.origin.x + zone.rect.x * vfLocal.width + gap,
                y: vfLocal.origin.y + (1.0 - zone.rect.y - zone.rect.height) * vfLocal.height + gap,
                width: zone.rect.width * vfLocal.width - gap * 2,
                height: zone.rect.height * vfLocal.height - gap * 2
            )

            // Fill
            let fillColor = isHighlighted
                ? accentColor.withAlphaComponent(0.35)
                : baseColor.withAlphaComponent(isDark ? 0.08 : 0.06)
            fillColor.setFill()
            let path = NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10)
            path.fill()

            // Border
            let borderColor = isHighlighted
                ? accentColor.withAlphaComponent(0.9)
                : baseColor.withAlphaComponent(isDark ? 0.3 : 0.2)
            borderColor.setStroke()
            path.lineWidth = isHighlighted ? 3 : 1.5
            path.stroke()

            // Zone number
            let fontSize = max(20, min(rect.width, rect.height) * 0.25)
            let textColor = isHighlighted
                ? (isDark ? NSColor.white : NSColor.black).withAlphaComponent(0.9)
                : baseColor.withAlphaComponent(0.4)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: fontSize, weight: .bold),
                .foregroundColor: textColor,
            ]
            let label = NSAttributedString(string: "\(index + 1)", attributes: attrs)
            let labelSize = label.size()
            label.draw(at: NSPoint(
                x: rect.midX - labelSize.width / 2,
                y: rect.midY - labelSize.height / 2
            ))
        }
    }
}
