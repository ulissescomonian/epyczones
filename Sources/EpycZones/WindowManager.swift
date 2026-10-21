import AppKit
import ApplicationServices

/// Snapping logic: where a hotkey, zone or drop sends a window, and the one
/// path that writes the resulting frame. Accessibility primitives live in
/// `AXWindow`, window lookup in `WindowTargeting.swift`, per-window memory in
/// `SnapHistory`, and drop handling in `PostDragSnapCoordinator`.
enum WindowManager {

    // MARK: - Public

    static func snap(to position: SnapPosition) {
        snap(to: position, retryOnMissingWindow: true)
    }

    private static func snap(to position: SnapPosition, retryOnMissingWindow: Bool) {
        guard AccessibilityChecker.isGranted else { return }
        guard let window = getFocusedWindow() else {
            guard retryOnMissingWindow else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                snap(to: position, retryOnMissingWindow: false)
            }
            return
        }

        let screen = screenForWindow(window) ?? NSScreen.main ?? NSScreen.screens[0]
        let visibleFrame = screen.visibleFrame

        // Handle dynamic positions
        switch position {
        case .restore:
            restoreWindow(window)
            return
        case .makeSmaller:
            resizeWindow(window, factor: 0.9)
            return
        case .makeLarger:
            resizeWindow(window, factor: 1.1)
            return
        case .maximizeHeight:
            maximizeHeight(window, screen: screen)
            return
        case .dockLeft:
            dockWindow(window, screen: screen, side: .left)
            return
        case .dockRight:
            dockWindow(window, screen: screen, side: .right)
            return
        default:
            break
        }

        // Repeated snap to the same half cycles widths: 1/2 → 2/3 → 1/3 →
        // adjacent monitor (if any) → back to 1/2.
        let cycle: [SnapPosition]
        switch position {
        case .leftHalf:  cycle = [.leftHalf, .firstTwoThirds, .firstThird]
        case .rightHalf: cycle = [.rightHalf, .lastTwoThirds, .lastThird]
        default:         cycle = []
        }
        if !cycle.isEmpty {
            let current = AXWindow.frame(of: window)
            let now = ProcessInfo.processInfo.systemUptime
            let step = SnapHistory.cycleStep(for: window)

            // Find the window's current cycle step. Prefer the recorded state:
            // apps can clamp the requested width (min width > 1/3 of the screen,
            // or grid-rounded sizing like Terminal), so the frame never matches
            // the step exactly — compare origin and height only. A step recorded
            // moments ago still counts while its animation is under way. Fall
            // back to geometric matching when there is no recorded state.
            var currentIndex: Int?
            if let step, step.position == position,
               now - step.recordedAt < SnapHistory.cycleAnimationGrace {
                currentIndex = step.index
            } else if let step, step.position == position, let cur = current,
               abs(cur.origin.x - step.frame.origin.x) < 15,
               abs(cur.origin.y - step.frame.origin.y) < 15,
               abs(cur.height - step.frame.height) < 15 {
                currentIndex = step.index
            } else if let cur = current,
                      let idx = cycle.firstIndex(where: { cur.isClose(to: $0.frame(in: visibleFrame), tolerance: 15) }) {
                currentIndex = idx
            }

            // End of cycle: flow to the adjacent monitor; otherwise wrap below.
            if let idx = currentIndex, idx + 1 >= cycle.count,
               let nextScreen = adjacentScreen(from: screen, direction: position.flowDirection) {
                applySnap(position.arrivalPosition.frame(in: nextScreen.visibleFrame), to: window)
                return
            }

            let nextIndex = currentIndex.map { ($0 + 1) % cycle.count } ?? 0
            let targetNS = cycle[nextIndex].frame(in: visibleFrame)
            applySnap(targetNS, to: window)
            SnapHistory.setCycleStep(
                SnapHistory.CycleStep(position: position, index: nextIndex, frame: targetNS, recordedAt: now),
                for: window
            )
            return
        }

        // Flow through monitors: if already at this position on the current screen,
        // move to the adjacent monitor in the snap direction.
        if NSScreen.screens.count > 1, let currentFrame = AXWindow.frame(of: window) {
            let targetNS = position.frame(in: visibleFrame)
            if currentFrame.isClose(to: targetNS, tolerance: 15) {
                if let nextScreen = adjacentScreen(from: screen, direction: position.flowDirection) {
                    applySnap(position.arrivalPosition.frame(in: nextScreen.visibleFrame), to: window)
                    return
                }
            }
        }

        applySnap(position.frame(in: visibleFrame), to: window)
    }

    static func snapToActiveZone(index: Int) {
        guard AccessibilityChecker.isGranted else { return }
        guard let window = getFocusedWindow() else { return }
        let screen = screenForWindow(window) ?? NSScreen.main ?? NSScreen.screens[0]
        snapToActiveZone(index: index, on: screen, window: window)
    }

    /// Snap a window that has already been resolved by the caller. This keeps a
    /// drag gesture tied to the same AX window even if focus changes mid-drag.
    static func snapToActiveZone(
        index: Int,
        on screen: NSScreen,
        window: AXUIElement,
        animated: Bool = true
    ) {
        guard AccessibilityChecker.isGranted else { return }
        guard let layout = LayoutStore.shared.activeLayout(for: screen),
              layout.zones.indices.contains(index) else { return }

        let gap = AppSettings.shared.zoneGap
        let zone = layout.zones[index]
        applySnap(zone.rect.frame(in: screen.visibleFrame, gap: gap), to: window, animated: animated)
        WindowPersistence.record(window: window, zoneIndex: index, screen: screen, layoutID: layout.id)
    }

    // MARK: - Dynamic Positions

    private static func restoreWindow(_ window: AXUIElement) {
        guard let previous = SnapHistory.popUndo(for: window) else { return }
        applyFrame(previous, to: window)
    }

    private static func resizeWindow(_ window: AXUIElement, factor: Double) {
        guard let frame = AXWindow.frame(of: window) else { return }
        SnapHistory.saveFrame(of: window)

        // Keep centered
        let newW = frame.width * factor
        let newH = frame.height * factor
        let targetNS = CGRect(x: frame.midX - newW / 2, y: frame.midY - newH / 2, width: newW, height: newH)
        applyFrame(targetNS, to: window)
    }

    enum DockSide { case left, right }

    private static func dockWindow(_ window: AXUIElement, screen: NSScreen, side: DockSide) {
        SnapHistory.saveFrame(of: window)
        let vf = screen.visibleFrame

        // Same logic as "center" but applied within each half of the screen.
        // Center uses 60% width, 80% height of full screen.
        // Dock uses 65% width, 80% height of half screen, centered within that half.
        let halfW = vf.width / 2
        let dw = halfW * 0.80
        let dh = vf.height * 0.80

        let dy = vf.origin.y + (vf.height - dh) / 2
        let dx: CGFloat
        switch side {
        case .left:
            // Center within left half
            dx = vf.origin.x + (halfW - dw) / 2
        case .right:
            // Center within right half
            dx = vf.origin.x + halfW + (halfW - dw) / 2
        }

        let targetNS = CGRect(x: dx, y: dy, width: dw, height: dh)
        applyFrame(targetNS, to: window)
    }

    private static func maximizeHeight(_ window: AXUIElement, screen: NSScreen) {
        guard let frame = AXWindow.frame(of: window) else { return }

        SnapHistory.saveFrame(of: window)
        let vf = screen.visibleFrame

        // Keep X and width, maximize height to visible frame
        let targetNS = CGRect(x: frame.minX, y: vf.origin.y, width: frame.width, height: vf.height)
        applyFrame(targetNS, to: window)
    }

    // MARK: - Snapping

    /// Save undo frame, apply the target, and record the snap for drag-away restore.
    /// All snap paths (hotkey, zone, drag, edge, app rule) should go through here.
    static func applySnap(_ targetNS: CGRect, to window: AXUIElement, animated: Bool = true) {
        let pre = AXWindow.frame(of: window)
        applyFrame(targetNS, to: window, animated: animated)
        SnapHistory.recordSnap(targetNS, to: window, preSnapFrame: pre)
    }

    /// Applies a snap after a user drag has ended; see `PostDragSnapCoordinator`.
    static func applySnapAfterDrag(
        _ targetNS: CGRect,
        to capturedWindow: AXUIElement,
        safeVisibleFrame: CGRect,
        isStillValid: @escaping () -> Bool,
        completion: @escaping (AXUIElement, Bool) -> Void
    ) {
        guard let droppedFrame = AXWindow.frame(of: capturedWindow) else {
            AXWindow.logMessage("post-drag snap skipped: could not read dropped frame", key: "post-drag-no-frame")
            completion(capturedWindow, false)
            return
        }

        PostDragSnapCoordinator(
            targetNS: targetNS,
            capturedWindow: capturedWindow,
            safeVisibleFrame: safeVisibleFrame,
            droppedFrame: droppedFrame,
            isStillValid: isStillValid,
            completion: completion
        ).start()
    }

    /// Resize mid-drag. Size-only: a position change would fight the system's
    /// drag tracking, but a size change sticks while the window keeps following the mouse.
    static func restoreSizeDuringDrag(of window: AXUIElement, to size: CGSize) {
        let appElement = AXWindow.appElement(for: window)
        let hadEnhancedUI = AXWindow.managesEnhancedUI(for: window) && AXWindow.isEnhancedUIEnabled(appElement)
        if hadEnhancedUI { AXWindow.setEnhancedUI(appElement, enabled: false) }
        AXWindow.setSize(of: window, to: size)
        if hadEnhancedUI { AXWindow.setEnhancedUI(appElement, enabled: true) }
    }

    // MARK: - Monitor Flow Helpers

    enum FlowDirection {
        case left, right, up, down, none
    }

    /// Find the adjacent screen in a spatial direction based on screen arrangement.
    private static func adjacentScreen(from screen: NSScreen, direction: FlowDirection) -> NSScreen? {
        let screens = NSScreen.screens
        guard screens.count > 1 else { return nil }

        let frame = screen.frame

        switch direction {
        case .right:
            // Find screen whose left edge is at or near our right edge
            return screens.filter { $0 != screen }
                .filter { $0.frame.origin.x >= frame.origin.x + frame.width - 50 }
                .min(by: { $0.frame.origin.x < $1.frame.origin.x })
        case .left:
            // Find screen whose right edge is at or near our left edge
            return screens.filter { $0 != screen }
                .filter { $0.frame.origin.x + $0.frame.width <= frame.origin.x + 50 }
                .max(by: { $0.frame.origin.x + $0.frame.width < $1.frame.origin.x + $1.frame.width })
        case .up:
            // NSScreen: higher Y = higher on screen
            return screens.filter { $0 != screen }
                .filter { $0.frame.origin.y >= frame.origin.y + frame.height - 50 }
                .min(by: { $0.frame.origin.y < $1.frame.origin.y })
        case .down:
            return screens.filter { $0 != screen }
                .filter { $0.frame.origin.y + $0.frame.height <= frame.origin.y + 50 }
                .max(by: { $0.frame.origin.y + $0.frame.height < $1.frame.origin.y + $1.frame.height })
        case .none:
            return nil
        }
    }

    // MARK: - Move Between Monitors

    static func moveToNextScreen() { moveToScreen(offset: 1) }
    static func moveToPreviousScreen() { moveToScreen(offset: -1) }

    /// Moves the focused window to another display, keeping its frame
    /// relative to the visible area.
    private static func moveToScreen(offset: Int) {
        guard AccessibilityChecker.isGranted else { return }
        guard let window = getFocusedWindow() else { return }
        let screens = NSScreen.screens
        guard screens.count > 1 else { return }

        let currentScreen = screenForWindow(window) ?? NSScreen.main ?? screens[0]
        guard let currentIndex = screens.firstIndex(where: { $0 == currentScreen }) else { return }

        let nextIndex = (currentIndex + offset + screens.count) % screens.count
        let targetScreen = screens[nextIndex]

        guard let frame = AXWindow.frame(of: window) else { return }

        let srcVF = currentScreen.visibleFrame
        let dstVF = targetScreen.visibleFrame

        let relX = (frame.minX - srcVF.origin.x) / srcVF.width
        let relY = (frame.minY - srcVF.origin.y) / srcVF.height
        let relW = frame.width / srcVF.width
        let relH = frame.height / srcVF.height

        let targetNS = CGRect(
            x: dstVF.origin.x + relX * dstVF.width,
            y: dstVF.origin.y + relY * dstVF.height,
            width: relW * dstVF.width,
            height: relH * dstVF.height
        )
        SnapHistory.saveFrame(of: window)
        applyFrame(targetNS, to: window)
    }

    // MARK: - Apply

    /// The single path that writes a window's frame, animated or not.
    ///
    /// - Parameter raisesWindow: Bring the window to the front of its app
    ///   afterwards. Batch restores pass false to keep the existing stacking.
    static func applyFrame(
        _ targetNS: CGRect,
        to window: AXUIElement,
        animated: Bool = true,
        raisesWindow: Bool = true
    ) {
        // Disable AXEnhancedUserInterface (used by Terminal, Xcode, etc.)
        // which blocks programmatic resize when enabled (e.g. for VoiceOver).
        // A write that supersedes one still animating finds it already
        // disabled, so it inherits the duty to turn it back on.
        let appElement = AXWindow.appElement(for: window)
        let superseded = frameWrites[window]
        let enabledNow = AXWindow.managesEnhancedUI(for: window) && AXWindow.isEnhancedUIEnabled(appElement)
        if enabledNow {
            AXWindow.setEnhancedUI(appElement, enabled: false)
        }
        let restoresEnhancedUI = enabledNow || superseded?.restoresEnhancedUI == true

        nextFrameWriteToken += 1
        let token = nextFrameWriteToken
        frameWrites[window] = FrameWrite(token: token, restoresEnhancedUI: restoresEnhancedUI)
        let isCurrent = { frameWrites[window]?.token == token }

        let finish = {
            // A newer write took over this window and finishes the job.
            guard isCurrent() else { return }
            frameWrites[window] = nil
            if restoresEnhancedUI {
                AXWindow.setEnhancedUI(appElement, enabled: true)
            }
            if raisesWindow { AXWindow.raise(window) }
        }

        if animated && AppSettings.shared.animateSnap {
            WindowAnimator.animate(window: window, to: targetNS, isCurrent: isCurrent) { _ in
                finish()
            }
        } else {
            AXWindow.setFrame(targetNS, of: window)
            finish()
        }
    }

    /// The latest frame write per window. A new write cancels an animation
    /// still running on the same window instead of interleaving with it.
    private struct FrameWrite {
        let token: Int
        let restoresEnhancedUI: Bool
    }

    private static var frameWrites = WindowStateMap<FrameWrite>()
    private static var nextFrameWriteToken = 0
}
