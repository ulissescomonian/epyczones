import AppKit

/// Manages transparent overlay panels that show zone regions on screen.
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
    var highlightedZoneIndices: Set<Int> = []

    /// Redraw timer for the marching-ants ghost border.
    private var antsTimer: Timer?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        antsTimer?.invalidate()
        antsTimer = nil
        guard window != nil else { return }
        antsTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self = self, !self.highlightedZoneIndices.isEmpty else { return }
            self.needsDisplay = true
        }
    }

    deinit {
        antsTimer?.invalidate()
    }

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
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        let isDark = AppSettings.shared.overlayIsDark

        // Background tint
        let bgColor = isDark
            ? NSColor.black.withAlphaComponent(0.15)
            : NSColor.white.withAlphaComponent(0.25)
        bgColor.setFill()
        bounds.fill()

        let vfLocal = NSRect(
            x: visibleFrame.origin.x - screenFrame.origin.x,
            y: visibleFrame.origin.y - screenFrame.origin.y,
            width: visibleFrame.width,
            height: visibleFrame.height
        )

        let gap: CGFloat = 4
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

        // Ghost preview: draw a translucent "window" outline over the combined highlighted zone area
        if !highlightedZoneIndices.isEmpty {
            let highlightedZones = highlightedZoneIndices.compactMap { idx -> Zone? in
                idx < layout.zones.count ? layout.zones[idx] : nil
            }
            guard !highlightedZones.isEmpty else { return }

            // Compute combined bounding rect
            var minX = highlightedZones[0].rect.x
            var minY = highlightedZones[0].rect.y
            var maxX = minX + highlightedZones[0].rect.width
            var maxY = minY + highlightedZones[0].rect.height
            for z in highlightedZones.dropFirst() {
                minX = min(minX, z.rect.x)
                minY = min(minY, z.rect.y)
                maxX = max(maxX, z.rect.x + z.rect.width)
                maxY = max(maxY, z.rect.y + z.rect.height)
            }

            let ghostRect = NSRect(
                x: vfLocal.origin.x + minX * vfLocal.width + gap + 4,
                y: vfLocal.origin.y + (1.0 - minY - (maxY - minY)) * vfLocal.height + gap + 4,
                width: (maxX - minX) * vfLocal.width - gap * 2 - 8,
                height: (maxY - minY) * vfLocal.height - gap * 2 - 8
            )

            // Ghost window fill
            NSColor.systemBlue.withAlphaComponent(0.12).setFill()
            let ghostPath = NSBezierPath(roundedRect: ghostRect, xRadius: 8, yRadius: 8)
            ghostPath.fill()

            // Ghost window border (dashed, marching ants — ~1.5 periods/s)
            NSColor.white.withAlphaComponent(0.6).setStroke()
            ghostPath.lineWidth = 2
            let pattern: [CGFloat] = [6, 4]
            let phase = -CGFloat((CACurrentMediaTime() * 15).truncatingRemainder(dividingBy: 10))
            ghostPath.setLineDash(pattern, count: 2, phase: phase)
            ghostPath.stroke()
        }
    }
}
