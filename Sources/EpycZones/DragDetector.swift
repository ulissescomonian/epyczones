import Cocoa
import ApplicationServices
import OSLog

/// Detects window dragging + Shift key to show zone overlays,
/// and dragging near screen edges to snap to halves/quarters (ghost preview).
///
/// Uses NSEvent global + local monitors.
/// Global monitors track events to other apps; local monitors track events to our app
/// (needed when overlay panels are showing and our app receives focus).
final class DragDetector {
    private let overlay = ZoneOverlayController()
    private let snapPreview = SnapPreviewController()

    private var globalMouseDownMonitor: Any?
    private var globalMouseDragMonitor: Any?
    private var globalMouseUpMonitor: Any?
    private var globalFlagsMonitor: Any?
    private var globalKeyDownMonitor: Any?
    private var localMouseDragMonitor: Any?
    private var localMouseUpMonitor: Any?
    private var localFlagsMonitor: Any?
    private var localKeyDownMonitor: Any?

    private var isMouseDown = false
    private var isDragging = false
    private var isOverlayVisible = false
    private var dragStartPos: NSPoint = .zero
    /// Invalidates delayed post-drag snap attempts when the user starts a new gesture.
    private var dragGeneration = 0

    /// Esc was pressed during this drag — suppress all snap UI until mouse up
    /// (re-pressing Shift re-enables).
    private var snapSuppressed = false

    /// Drag-away restore: size to restore when a snapped window starts being dragged.
    private var pendingDragRestoreSize: CGSize?
    private var didDragRestore = false

    /// The window being dragged — captured before overlay appears so we don't lose the reference.
    private var draggedWindow: AXUIElement?

    /// Window position at drag start — used to detect actual window movement vs text selection.
    private var windowStartPos: CGPoint?
    /// The dragged window has moved during this gesture: it is a window drag.
    private var windowHasMoved = false
    /// Layouts resolved during this gesture; see `gestureLayout(for:)`.
    private var gestureLayouts: [NSScreen: Layout?] = [:]

    /// Timer for edge snap delay.
    private var edgeSnapTimer: Timer?
    private var isWaitingForEdgeSnap = false

    private let dragThreshold: CGFloat = 5.0

    // MARK: - Lifecycle

    func start() {
        globalMouseDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            self?.onMouseDown()
        }
        globalMouseDragMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { [weak self] _ in
            self?.onMouseDragged()
        }
        globalMouseUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
            self?.onMouseUp()
        }
        globalFlagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.onFlagsChanged(flags: event.modifierFlags)
        }
        globalKeyDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.onKeyDown(event)
        }

        localMouseDragMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDragged) { [weak self] event in
            self?.onMouseDragged()
            return event
        }
        localMouseUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
            self?.onMouseUp()
            return event
        }
        localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.onFlagsChanged(flags: event.modifierFlags)
            return event
        }
        localKeyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.onKeyDown(event)
            return event
        }
    }

    func stop() {
        for m in [globalMouseDownMonitor, globalMouseDragMonitor, globalMouseUpMonitor,
                   globalFlagsMonitor, globalKeyDownMonitor, localMouseDragMonitor,
                   localMouseUpMonitor, localFlagsMonitor, localKeyDownMonitor] {
            if let m = m { NSEvent.removeMonitor(m) }
        }
    }

    // MARK: - Event Handlers

    private func onMouseDown() {
        dragGeneration += 1
        isMouseDown = true
        isDragging = false
        draggedWindow = nil
        windowStartPos = nil
        windowHasMoved = false
        gestureLayouts = [:]
        snapSuppressed = false
        pendingDragRestoreSize = nil
        didDragRestore = false
        dragStartPos = NSEvent.mouseLocation
    }

    private func onMouseDragged() {
        let currentPos = NSEvent.mouseLocation

        if isMouseDown && !isDragging {
            let distance = hypot(currentPos.x - dragStartPos.x, currentPos.y - dragStartPos.y)
            if distance > dragThreshold {
                isDragging = true
            }
        }

        guard isDragging else { return }

        // AX state can be temporarily unavailable (notably for browser app shims).
        // Keep trying on subsequent drag events, but preserve the first window found.
        captureDraggedWindowIfNeeded()
        let windowIsMoving = isWindowMoving()

        // Drag-away restore: un-snapping a snapped window restores its pre-snap size.
        if let size = pendingDragRestoreSize, !didDragRestore, let w = draggedWindow, windowIsMoving {
            didDragRestore = true
            WindowManager.restoreSizeDuringDrag(of: w, to: size)
        }

        let mode = DragSnapPolicy.mode(
            windowIsMoving: windowIsMoving,
            shiftHeld: NSEvent.modifierFlags.contains(.shift),
            suppressed: snapSuppressed,
            edgeSnapEnabled: AppSettings.shared.edgeSnapEnabled
        )

        switch mode {
        case .zones:
            // Shift: layout zone overlay, immediately. Edge preview yields.
            cancelEdgeSnapTimer()
            snapPreview.hide()
            if !isOverlayVisible { showOverlay() }
            if isOverlayVisible { updateHighlight(at: currentPos) }

        case .edge:
            if isOverlayVisible {
                hideOverlay(snap: false)
            }

            // Edge snap (no modifier): edges → halves, corners → quarters.
            if let target = EdgeSnapResolver.resolve(at: currentPos) {
                if snapPreview.isVisible {
                    snapPreview.show(target)
                } else if !isWaitingForEdgeSnap {
                    startEdgeSnapTimer()
                }
            } else {
                cancelEdgeSnapTimer()
                snapPreview.hide()
            }

        case .none:
            if isOverlayVisible {
                hideOverlay(snap: false)
            }
            cancelEdgeSnapTimer()
            snapPreview.hide()
        }
    }

    private func onMouseUp() {
        let generation = dragGeneration
        if isOverlayVisible {
            // Re-evaluate zones at the final mouse position
            updateHighlight(at: NSEvent.mouseLocation)

            // Capture state before hiding overlay
            let zoneIndices = overlay.highlightedZoneIndices
            let screen = overlay.highlightedScreen

            // Hide overlay immediately (visual feedback)
            isOverlayVisible = false
            overlay.hide()

            if let screen = screen, !zoneIndices.isEmpty,
               let layout = gestureLayout(for: screen),
               let window = draggedWindow {
                let validIndices = zoneIndices.filter { $0 < layout.zones.count }
                if validIndices.count == 1, let index = validIndices.first {
                    let targetNS = layout.zones[index].rect.frame(
                        in: screen.visibleFrame,
                        gap: AppSettings.shared.zoneGap
                    )
                    let layoutID = layout.id
                    WindowManager.applySnapAfterDrag(
                        targetNS,
                        to: window,
                        safeVisibleFrame: screen.visibleFrame,
                        isStillValid: { [weak self] in
                            self?.dragGeneration == generation
                        }
                    ) { appliedWindow, didApply in
                        guard didApply else { return }
                        WindowPersistence.record(
                            window: appliedWindow,
                            zoneIndex: index,
                            screen: screen,
                            layoutID: layoutID
                        )
                    }
                } else if !validIndices.isEmpty {
                    let zones = validIndices.map { layout.zones[$0] }
                    let targetNS = RelativeRect.bounding(zones).frame(
                        in: screen.visibleFrame,
                        gap: AppSettings.shared.zoneGap
                    )
                    WindowManager.applySnapAfterDrag(
                        targetNS,
                        to: window,
                        safeVisibleFrame: screen.visibleFrame,
                        isStillValid: { [weak self] in
                            self?.dragGeneration == generation
                        }
                    ) { _, _ in }
                }
            } else if draggedWindow == nil {
                Log.drag.notice("Could not capture dragged window for zone snap")
            }
        } else if let target = snapPreview.target {
            snapPreview.hide()
            applyEdgeSnap(target)
        }
        cancelEdgeSnapTimer()
        snapPreview.hide()
        isMouseDown = false
        isDragging = false
        draggedWindow = nil
        windowStartPos = nil
        windowHasMoved = false
        gestureLayouts = [:]
        snapSuppressed = false
        pendingDragRestoreSize = nil
        didDragRestore = false
    }

    private func onFlagsChanged(flags: NSEvent.ModifierFlags) {
        let shiftHeld = flags.contains(.shift)

        // Re-pressing Shift re-enables snapping after an Esc cancel.
        if shiftHeld && isDragging { snapSuppressed = false }

        if shiftHeld && isDragging && !isOverlayVisible && isWindowMoving() {
            cancelEdgeSnapTimer()
            snapPreview.hide()
            showOverlay()
            updateHighlight(at: NSEvent.mouseLocation)
        } else if !shiftHeld && isOverlayVisible {
            hideOverlay(snap: false)
        }
    }

    private func onKeyDown(_ event: NSEvent) {
        // Esc cancels any pending snap for the rest of the drag.
        guard event.keyCode == 53, isDragging else { return }
        snapSuppressed = true
        cancelEdgeSnapTimer()
        snapPreview.hide()
        if isOverlayVisible {
            isOverlayVisible = false
            overlay.hide()
        }
    }

    // MARK: - Overlay

    private func showOverlay() {
        guard !isOverlayVisible else { return }
        // Check that at least one screen has a layout with zones
        guard NSScreen.screens.contains(where: { screen in
            let l = gestureLayout(for: screen)
            return l != nil && !l!.zones.isEmpty
        }) else { return }
        isOverlayVisible = true
        overlay.show { screen in gestureLayout(for: screen) }
    }

    /// Each screen's active layout, resolved once per gesture: the drag
    /// handlers ask on every mouse event, and resolving can query Spaces.
    private func gestureLayout(for screen: NSScreen) -> Layout? {
        if let cached = gestureLayouts[screen] { return cached }
        let resolved = LayoutStore.shared.activeLayout(for: screen)
        gestureLayouts[screen] = .some(resolved)
        return resolved
    }

    private func updateHighlight(at nsPoint: NSPoint) {
        let (indices, screen) = zoneIndices(at: nsPoint)
        overlay.updateHighlight(zoneIndices: indices, on: screen)
    }

    private func hideOverlay(snap: Bool) {
        let zoneIndices = overlay.highlightedZoneIndices
        let screen = overlay.highlightedScreen
        isOverlayVisible = false
        overlay.hide()

        if snap, !zoneIndices.isEmpty, let window = draggedWindow,
           let screen = screen,
           let layout = gestureLayout(for: screen) {
            let validIndices = zoneIndices.filter { $0 < layout.zones.count }
            guard !validIndices.isEmpty else { return }
            let zones = validIndices.map { layout.zones[$0] }
            snapWindow(window, toZones: zones, on: screen)
            if let first = validIndices.sorted().first {
                WindowPersistence.record(window: window, zoneIndex: first, screen: screen, layoutID: layout.id)
            }
        }
    }

    // MARK: - Window Snapping

    /// Snap window to combined bounding rect of one or more zones (spanning).
    private func snapWindow(_ window: AXUIElement, toZones zones: [Zone], on screen: NSScreen) {
        let gap = AppSettings.shared.zoneGap
        let combined = RelativeRect.bounding(zones)
        let targetNS = combined.frame(in: screen.visibleFrame, gap: gap)
        WindowManager.applySnap(targetNS, to: window, animated: false)
    }

    // MARK: - Window Movement Detection

    /// Check if the window has actually moved from its start position (i.e., user is dragging the window, not selecting text).
    /// Latches once true, so a confirmed window drag stops re-reading AX on every event.
    private func isWindowMoving() -> Bool {
        if windowHasMoved { return true }
        guard let w = draggedWindow, let startPos = windowStartPos,
              let currentPos = WindowManager.getPosition(of: w) else { return false }
        let threshold: CGFloat = 3.0
        windowHasMoved = abs(currentPos.x - startPos.x) > threshold || abs(currentPos.y - startPos.y) > threshold
        return windowHasMoved
    }

    // MARK: - AX Helpers

    /// Capture the dragged window and its starting position as AX makes them available.
    /// Once a window is found, it remains stable for the rest of the gesture.
    private func captureDraggedWindowIfNeeded() {
        if draggedWindow == nil, let window = WindowManager.windowForDrag(at: NSEvent.mouseLocation) {
            draggedWindow = window
            pendingDragRestoreSize = WindowManager.dragRestoreSize(for: window)
        }

        if windowStartPos == nil, let window = draggedWindow {
            windowStartPos = WindowManager.getPosition(of: window)
        }
    }

    // MARK: - Edge Snap Timer

    private func startEdgeSnapTimer() {
        isWaitingForEdgeSnap = true
        edgeSnapTimer = Timer.scheduledTimer(withTimeInterval: AppSettings.shared.edgeSnapDelay, repeats: false) { [weak self] _ in
            guard let self = self, self.isWaitingForEdgeSnap, self.isDragging else { return }
            self.isWaitingForEdgeSnap = false
            if let target = EdgeSnapResolver.resolve(at: NSEvent.mouseLocation) {
                self.snapPreview.show(target)
            }
        }
    }

    private func cancelEdgeSnapTimer() {
        edgeSnapTimer?.invalidate()
        edgeSnapTimer = nil
        isWaitingForEdgeSnap = false
    }

    // MARK: - Edge Snap

    /// Apply an edge snap after drop using the same guarded AX sequence as zone snaps.
    private func applyEdgeSnap(_ target: EdgeSnapResolver.Target) {
        guard let w = draggedWindow else {
            Log.drag.notice("Could not capture dragged window for edge snap")
            return
        }
        let vf = target.screen.visibleFrame
        let generation = dragGeneration
        WindowManager.applySnapAfterDrag(
            target.position.frame(in: vf),
            to: w,
            safeVisibleFrame: vf,
            isStillValid: { [weak self] in
                self?.dragGeneration == generation
            }
        ) { _, _ in }
    }

    // MARK: - Zone Hit-Testing

    /// Returns the set of zone indices the cursor is over (may be >1 near boundaries)
    /// and the screen the cursor is on.
    private func zoneIndices(at nsPoint: NSPoint) -> (Set<Int>, NSScreen?) {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(nsPoint) }),
              let layout = gestureLayout(for: screen) else { return ([], nil) }

        let vf = screen.visibleFrame
        let relative = CGPoint(
            x: (nsPoint.x - vf.origin.x) / vf.width,
            y: 1.0 - (nsPoint.y - vf.origin.y) / vf.height
        )

        // Zone boundary threshold in relative coords (~20px)
        let threshold = 20.0 / max(vf.width, vf.height)

        let indices = ZoneHitTester.zoneIndices(at: relative, in: layout.zones, threshold: threshold)
        return (indices, screen)
    }
}
