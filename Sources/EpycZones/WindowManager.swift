import AppKit
import ApplicationServices

enum WindowManager {

    /// Undo stack per window (key = window hash). Each entry is a frame before a snap.
    private static var undoStacks: [Int: [CGRect]] = [:]
    /// Redo stack per window.
    private static var redoStacks: [Int: [CGRect]] = [:]
    private static let maxUndoDepth = 20
    private static var lastAXLogTimes: [String: TimeInterval] = [:]
    private static let axLogThrottleInterval: TimeInterval = 5

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
            restoreWindow(window, screen: screen)
            return
        case .makeSmaller:
            resizeWindow(window, screen: screen, factor: 0.9)
            return
        case .makeLarger:
            resizeWindow(window, screen: screen, factor: 1.1)
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
            let key = windowHash(window)
            let current = currentNSFrame(of: window)

            // Find the window's current cycle step. Prefer the recorded state:
            // apps can clamp the requested width (min width > 1/3 of the screen,
            // or grid-rounded sizing like Terminal), so the frame never matches
            // the step exactly — compare origin and height only. Fall back to
            // geometric matching when there is no recorded state.
            var currentIndex: Int?
            if let state = cycleStates[key], state.position == position, let cur = current,
               abs(cur.origin.x - state.frame.origin.x) < 15,
               abs(cur.origin.y - state.frame.origin.y) < 15,
               abs(cur.height - state.frame.height) < 15 {
                currentIndex = state.index
            } else if let cur = current,
                      let idx = cycle.firstIndex(where: { framesMatch(cur, $0.frame(in: visibleFrame), tolerance: 15) }) {
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
            cycleStates[key] = (position: position, index: nextIndex, frame: targetNS)
            return
        }

        // Flow through monitors: if already at this position on the current screen,
        // move to the adjacent monitor in the snap direction.
        if NSScreen.screens.count > 1, let currentFrame = currentNSFrame(of: window) {
            let targetNS = position.frame(in: visibleFrame)
            if framesMatch(currentFrame, targetNS, tolerance: 15) {
                if let nextScreen = adjacentScreen(from: screen, direction: position.flowDirection) {
                    applySnap(position.arrivalPosition.frame(in: nextScreen.visibleFrame), to: window)
                    return
                }
            }
        }

        applySnap(position.frame(in: visibleFrame), to: window)
    }

    static func snap(to zone: Zone) {
        guard AccessibilityChecker.isGranted else { return }
        guard let window = getFocusedWindow() else { return }

        let screen = screenForWindow(window) ?? NSScreen.main ?? NSScreen.screens[0]
        let gap = AppSettings.shared.zoneGap
        applySnap(zone.rect.frame(in: screen.visibleFrame, gap: gap), to: window)
    }

    static func snapToActiveZone(index: Int) {
        guard AccessibilityChecker.isGranted else { return }
        guard let window = getFocusedWindow() else { return }
        let screen = screenForWindow(window) ?? NSScreen.main ?? NSScreen.screens[0]
        snapToActiveZone(index: index, on: screen, window: window)
    }

    static func snapToActiveZone(index: Int, on screen: NSScreen, animated: Bool = true) {
        guard AccessibilityChecker.isGranted else { return }
        guard let window = getFocusedWindow() else { return }
        snapToActiveZone(index: index, on: screen, window: window, animated: animated)
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

    private static func restoreWindow(_ window: AXUIElement, screen: NSScreen) {
        let key = windowHash(window)
        guard var stack = undoStacks[key], let prev = stack.popLast() else { return }
        undoStacks[key] = stack

        // Save current frame to redo stack before restoring
        if let currentFrame = currentNSFrame(of: window) {
            redoStacks[key, default: []].append(currentFrame)
        }
        applyFrame(prev, to: window)
    }

    /// Redo: re-apply the last undone snap.
    static func redoSnap() {
        guard AccessibilityChecker.isGranted else { return }
        guard let window = getFocusedWindow() else { return }
        let key = windowHash(window)
        guard var stack = redoStacks[key], let next = stack.popLast() else { return }
        redoStacks[key] = stack

        // Save current frame to undo stack
        if let currentFrame = currentNSFrame(of: window) {
            undoStacks[key, default: []].append(currentFrame)
        }
        applyFrame(next, to: window)
    }

    private static func resizeWindow(_ window: AXUIElement, screen: NSScreen, factor: Double) {
        guard let axPos = getPosition(of: window),
              let axSize = getSize(of: window) else { return }

        let primaryHeight = NSScreen.screens[0].frame.height
        let nsX = axPos.x
        let nsY = primaryHeight - axPos.y - axSize.height

        let newW = axSize.width * factor
        let newH = axSize.height * factor
        // Keep centered
        let newX = nsX - (newW - axSize.width) / 2
        let newY = nsY - (newH - axSize.height) / 2

        let targetNS = CGRect(x: newX, y: newY, width: newW, height: newH)
        applyFrame(targetNS, to: window)
    }

    enum DockSide { case left, right }

    private static func dockWindow(_ window: AXUIElement, screen: NSScreen, side: DockSide) {
        saveFrame(of: window)
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
        guard let axPos = getPosition(of: window),
              let axSize = getSize(of: window) else { return }

        saveFrame(of: window)
        let vf = screen.visibleFrame

        // Keep X and width, maximize height to visible frame
        let targetNS = CGRect(
            x: axPos.x,
            y: vf.origin.y,
            width: axSize.width,
            height: vf.height
        )
        applyFrame(targetNS, to: window)
    }

    static func saveFrame(of window: AXUIElement) {
        guard let frame = currentNSFrame(of: window) else { return }
        let key = windowHash(window)
        undoStacks[key, default: []].append(frame)
        if undoStacks[key]!.count > maxUndoDepth {
            undoStacks[key]!.removeFirst()
        }
        // Clear redo stack on new action
        redoStacks[key] = nil
    }

    // MARK: - Snap Tracking (drag-away restore)

    /// Cycle step per window for repeated half-snap cycling. Stores the
    /// requested frame so clamped windows (min width > step width) still
    /// advance the cycle instead of looping forever.
    private static var cycleStates: [Int: (position: SnapPosition, index: Int, frame: CGRect)] = [:]

    /// Last applied snap frame per window (NS coords).
    private static var snapFrames: [Int: CGRect] = [:]
    /// Window size before the first snap in a chain — restored when the window is dragged away.
    private static var dragRestoreSizes: [Int: CGSize] = [:]

    /// Save undo frame, apply the target, and record the snap for drag-away restore.
    /// All snap paths (hotkey, zone, drag, edge, app rule) should go through here.
    static func applySnap(_ targetNS: CGRect, to window: AXUIElement, animated: Bool = true) {
        let pre = currentNSFrame(of: window)
        applyFrame(targetNS, to: window, animated: animated)
        recordSuccessfulSnap(targetNS, to: window, preSnapFrame: pre)
    }

    /// Applies a snap after a user drag has ended. Finder can still own the AX
    /// window briefly after mouse-up: moving it is accepted, while resizing is
    /// transiently rejected. Keep the safe move and all retries together so a
    /// failed resize can never strand the window at the safe top-left position.
    static func applySnapAfterDrag(
        _ targetNS: CGRect,
        to capturedWindow: AXUIElement,
        safeVisibleFrame: CGRect,
        isStillValid: @escaping () -> Bool,
        completion: @escaping (AXUIElement, Bool) -> Void
    ) {
        guard let droppedFrame = currentNSFrame(of: capturedWindow) else {
            logAXMessage("post-drag snap skipped: could not read dropped frame", key: "post-drag-no-frame")
            completion(capturedWindow, false)
            return
        }

        let capturedPID = processID(of: capturedWindow)
        let preserveCapturedWindow = isChromeAppShim(pid: capturedPID)

        // Yield briefly so Finder finishes its drag transaction before the
        // first direct AX frame write, without making the snap feel delayed.
        let initialDelay: TimeInterval = 0.06
        DispatchQueue.main.asyncAfter(deadline: .now() + initialDelay) {
            performPostDragSnapAttempt(
                targetNS,
                capturedWindow: capturedWindow,
                capturedPID: capturedPID,
                preserveCapturedWindow: preserveCapturedWindow,
                safeVisibleFrame: safeVisibleFrame,
                droppedFrame: droppedFrame,
                attempt: 0,
                isStillValid: isStillValid,
                completion: completion
            )
        }
    }

    private static func performPostDragSnapAttempt(
        _ targetNS: CGRect,
        capturedWindow: AXUIElement,
        capturedPID: pid_t,
        preserveCapturedWindow: Bool,
        safeVisibleFrame: CGRect,
        droppedFrame: CGRect,
        attempt: Int,
        isStillValid: @escaping () -> Bool,
        completion: @escaping (AXUIElement, Bool) -> Void
    ) {
        guard isStillValid() else {
            completion(capturedWindow, false)
            return
        }
        let window = resolvedPostDragWindow(
            capturedWindow: capturedWindow,
            capturedPID: capturedPID,
            preserveCapturedWindow: preserveCapturedWindow
        )

        // Finder is the only app that needs the direct path to avoid a visible
        // staging jump. All other apps keep the long-standing safe sequence,
        // as does Finder's final compatibility fallback.
        let usesDirectAttempt = isFinder(pid: capturedPID) && attempt < 2
        if !usesDirectAttempt {
            let primaryHeight = NSScreen.screens[0].frame.height
            let safePosition = CGPoint(
                x: safeVisibleFrame.origin.x,
                y: primaryHeight - safeVisibleFrame.origin.y - safeVisibleFrame.height
            )
            logAXMessage(
                "post-drag snap using safe staging",
                key: "post-drag-safe-staging-\(capturedPID)-\(attempt)",
                interval: 1
            )
            _ = setPosition(of: window, to: safePosition)
        }
        let preApplyFrame = currentNSFrame(of: window) ?? droppedFrame
        applyFrame(targetNS, to: window, animated: false)

        // AX updates can be delivered one run-loop turn after a successful
        // write, particularly by Finder. Verify observable progress rather
        // than trusting AXUIElementSetAttributeValue's return code alone.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
            guard isStillValid() else {
                completion(window, false)
                return
            }
            let didApply: Bool
            if let actual = currentNSFrame(of: window) {
                // A direct Finder write must reach the full requested frame;
                // partial movement means its drag transaction is still active.
                // Safe staging retains the tolerant constraint handling used
                // by apps with a minimum window size.
                didApply = usesDirectAttempt
                    ? framesMatch(actual, targetNS, tolerance: 2)
                    : frameReachedOrAdvanced(from: preApplyFrame, to: actual, toward: targetNS)
            } else {
                didApply = false
            }
            if didApply {
                recordSuccessfulSnap(targetNS, to: window, preSnapFrame: droppedFrame)
                completion(window, true)
                return
            }

            guard attempt < 2 else {
                performPostDragRollbackAttempt(
                    capturedWindow: window,
                    droppedFrame: droppedFrame,
                    capturedPID: capturedPID,
                    attempt: 0,
                    isStillValid: isStillValid,
                    completion: completion
                )
                return
            }

            guard isStillValid() else {
                completion(window, false)
                return
            }
            let retryDelay: TimeInterval = attempt == 0 ? 0.06 : 0.12
            let nextUsesDirectAttempt = isFinder(pid: capturedPID) && attempt + 1 < 2
            let nextAttemptDescription = nextUsesDirectAttempt ? "direct Finder" : "safe staging"
            logAXMessage(
                "post-drag snap retry \(attempt + 2)/3 (\(nextAttemptDescription))",
                key: "post-drag-snap-retry-\(capturedPID)-\(attempt)",
                interval: 1
            )
            DispatchQueue.main.asyncAfter(deadline: .now() + retryDelay) {
                performPostDragSnapAttempt(
                    targetNS,
                    capturedWindow: capturedWindow,
                    capturedPID: capturedPID,
                    preserveCapturedWindow: preserveCapturedWindow,
                    safeVisibleFrame: safeVisibleFrame,
                    droppedFrame: droppedFrame,
                    attempt: attempt + 1,
                    isStillValid: isStillValid,
                    completion: completion
                )
            }
        }
    }

    /// A constrained window may not reach the requested size exactly. It is a
    /// successful snap when every requested component is either within the
    /// normal tolerance or has measurably moved toward its requested value.
    private static func frameReachedOrAdvanced(from before: CGRect, to after: CGRect, toward target: CGRect) -> Bool {
        let tolerance: CGFloat = 2
        let values: [(CGFloat, CGFloat, CGFloat)] = [
            (before.origin.x, after.origin.x, target.origin.x),
            (before.origin.y, after.origin.y, target.origin.y),
            (before.width, after.width, target.width),
            (before.height, after.height, target.height)
        ]
        return values.allSatisfy { beforeValue, afterValue, targetValue in
            let initialDistance = abs(targetValue - beforeValue)
            if initialDistance <= tolerance { return true }
            return abs(targetValue - afterValue) <= tolerance
                || abs(targetValue - afterValue) + tolerance < initialDistance
        }
    }

    private static func resolvedPostDragWindow(
        capturedWindow: AXUIElement,
        capturedPID: pid_t,
        preserveCapturedWindow: Bool
    ) -> AXUIElement {
        guard !preserveCapturedWindow,
              let focused = getFocusedWindow(),
              processID(of: focused) == capturedPID,
              CFEqual(focused, capturedWindow) else {
            return capturedWindow
        }
        return focused
    }

    private static func performPostDragRollbackAttempt(
        capturedWindow: AXUIElement,
        droppedFrame: CGRect,
        capturedPID: pid_t,
        attempt: Int,
        isStillValid: @escaping () -> Bool,
        completion: @escaping (AXUIElement, Bool) -> Void
    ) {
        guard isStillValid() else {
            completion(capturedWindow, false)
            return
        }

        let before = currentNSFrame(of: capturedWindow) ?? droppedFrame
        applyFrame(droppedFrame, to: capturedWindow, animated: false)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
            guard isStillValid() else {
                completion(capturedWindow, false)
                return
            }
            if let actual = currentNSFrame(of: capturedWindow),
               frameReachedOrAdvanced(from: before, to: actual, toward: droppedFrame) {
                logAXMessage(
                    "post-drag snap failed; restored dropped frame",
                    key: "post-drag-snap-restored-\(capturedPID)",
                    interval: 5
                )
                completion(capturedWindow, false)
                return
            }

            guard attempt < 2 else {
                logAXMessage(
                    "post-drag snap and rollback failed after retries",
                    key: "post-drag-rollback-failed-\(capturedPID)",
                    interval: 5
                )
                completion(capturedWindow, false)
                return
            }
            guard isStillValid() else {
                completion(capturedWindow, false)
                return
            }
            let retryDelay: TimeInterval = attempt == 0 ? 0.06 : 0.12
            DispatchQueue.main.asyncAfter(deadline: .now() + retryDelay) {
                performPostDragRollbackAttempt(
                    capturedWindow: capturedWindow,
                    droppedFrame: droppedFrame,
                    capturedPID: capturedPID,
                    attempt: attempt + 1,
                    isStillValid: isStillValid,
                    completion: completion
                )
            }
        }
    }

    private static func recordSuccessfulSnap(_ targetNS: CGRect, to window: AXUIElement, preSnapFrame: CGRect?) {
        if let preSnapFrame {
            recordUndoFrame(preSnapFrame, for: window)
        }

        let key = windowHash(window)
        // Any snap invalidates the cycle chain; the cycling code re-records
        // its state right after calling applySnap.
        cycleStates[key] = nil
        if let pre = preSnapFrame {
            // Snapping from one snap position to another keeps the original restore size.
            let wasSnapped = snapFrames[key].map { framesMatch(pre, $0, tolerance: 15) } ?? false
            if !wasSnapped {
                dragRestoreSizes[key] = pre.size
            }
        }
        snapFrames[key] = targetNS
    }

    private static func recordUndoFrame(_ frame: CGRect, for window: AXUIElement) {
        let key = windowHash(window)
        undoStacks[key, default: []].append(frame)
        if undoStacks[key]!.count > maxUndoDepth {
            undoStacks[key]!.removeFirst()
        }
        redoStacks[key] = nil
    }

    /// If the window currently sits at its recorded snap frame, the size to restore on drag-away.
    static func dragRestoreSize(for window: AXUIElement) -> CGSize? {
        let key = windowHash(window)
        guard let snapped = snapFrames[key],
              let size = dragRestoreSizes[key],
              let current = currentNSFrame(of: window),
              framesMatch(current, snapped, tolerance: 15) else { return nil }
        return size
    }

    /// Resize mid-drag. Size-only: a position change would fight the system's
    /// drag tracking, but a size change sticks while the window keeps following the mouse.
    static func restoreSizeDuringDrag(of window: AXUIElement, to size: CGSize) {
        let appElement = getAppElement(for: window)
        let hadEnhancedUI = shouldManageEnhancedUI(for: window) && getEnhancedUI(appElement)
        if hadEnhancedUI { setEnhancedUI(appElement, enabled: false) }
        _ = setSize(of: window, to: size)
        if hadEnhancedUI { setEnhancedUI(appElement, enabled: true) }
    }

    private static func currentNSFrame(of window: AXUIElement) -> CGRect? {
        guard let axPos = getPosition(of: window),
              let axSize = getSize(of: window) else { return nil }
        let primaryHeight = NSScreen.screens[0].frame.height
        return CGRect(
            x: axPos.x,
            y: primaryHeight - axPos.y - axSize.height,
            width: axSize.width,
            height: axSize.height
        )
    }

    private static func windowHash(_ window: AXUIElement) -> Int {
        let pid = processID(of: window)
        // Combine PID with window title for uniqueness
        var title: AnyObject?
        AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &title)
        let titleStr = (title as? String) ?? ""
        var hasher = Hasher()
        hasher.combine(pid)
        hasher.combine(titleStr)
        return hasher.finalize()
    }

    private static func processID(of window: AXUIElement) -> pid_t {
        var pid: pid_t = 0
        _ = AXUIElementGetPid(window, &pid)
        return pid
    }

    private static func isChromeAppShim(pid: pid_t) -> Bool {
        NSRunningApplication(processIdentifier: pid)?.bundleIdentifier?.hasPrefix("com.google.Chrome.app.") == true
    }

    private static func isFinder(pid: pid_t) -> Bool {
        NSRunningApplication(processIdentifier: pid)?.bundleIdentifier == "com.apple.finder"
    }

    // MARK: - Monitor Flow Helpers

    enum FlowDirection {
        case left, right, up, down, none
    }

    private static func framesMatch(_ a: CGRect, _ b: CGRect, tolerance: CGFloat) -> Bool {
        abs(a.origin.x - b.origin.x) < tolerance &&
        abs(a.origin.y - b.origin.y) < tolerance &&
        abs(a.width - b.width) < tolerance &&
        abs(a.height - b.height) < tolerance
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

    private static func moveToScreen(offset: Int) {
        guard AccessibilityChecker.isGranted else { return }
        guard let window = getFocusedWindow() else { return }
        let screens = NSScreen.screens
        guard screens.count > 1 else { return }

        let currentScreen = screenForWindow(window) ?? NSScreen.main ?? screens[0]
        guard let currentIndex = screens.firstIndex(where: { $0 == currentScreen }) else { return }

        let nextIndex = (currentIndex + offset + screens.count) % screens.count
        let targetScreen = screens[nextIndex]

        guard let axPos = getPosition(of: window),
              let axSize = getSize(of: window) else { return }

        let primaryHeight = screens[0].frame.height
        let srcVF = currentScreen.visibleFrame
        let dstVF = targetScreen.visibleFrame

        let nsX = axPos.x
        let nsY = primaryHeight - axPos.y - axSize.height

        let relX = (nsX - srcVF.origin.x) / srcVF.width
        let relY = (nsY - srcVF.origin.y) / srcVF.height
        let relW = axSize.width / srcVF.width
        let relH = axSize.height / srcVF.height

        let targetNS = CGRect(
            x: dstVF.origin.x + relX * dstVF.width,
            y: dstVF.origin.y + relY * dstVF.height,
            width: relW * dstVF.width,
            height: relH * dstVF.height
        )
        applyFrame(targetNS, to: window)
    }


    // MARK: - Apply

    static func applyFrame(_ targetNS: CGRect, to window: AXUIElement, animated: Bool = true) {
        let primaryHeight = NSScreen.screens[0].frame.height
        let targetPos = CGPoint(x: targetNS.origin.x, y: primaryHeight - targetNS.origin.y - targetNS.height)

        // Disable AXEnhancedUserInterface (used by Terminal, Xcode, etc.)
        // which blocks programmatic resize when enabled (e.g. for VoiceOver).
        let appElement = getAppElement(for: window)
        let hadEnhancedUI = shouldManageEnhancedUI(for: window) && getEnhancedUI(appElement)
        if hadEnhancedUI {
            setEnhancedUI(appElement, enabled: false)
        }

        if animated && AppSettings.shared.animateSnap {
            WindowAnimator.animate(window: window, to: targetNS) { _ in
                if hadEnhancedUI {
                    setEnhancedUI(appElement, enabled: true)
                }
                raise(window)
            }
        } else {
            // Rectangle's approach: SIZE → POSITION → SIZE.
            // macOS enforces sizes that fit the current display position.
            // First SIZE shrinks the window so POSITION doesn't get clamped.
            // Second SIZE corrects any size constraint from the old position.
            _ = setSize(of: window, to: targetNS.size)
            _ = setPosition(of: window, to: targetPos)
            _ = setSize(of: window, to: targetNS.size)

            if hadEnhancedUI {
                setEnhancedUI(appElement, enabled: true)
            }
            raise(window)
        }
    }

    // MARK: - Enhanced UI Helpers

    private static let kAXEnhancedUserInterface = "AXEnhancedUserInterface" as CFString

    private static func getAppElement(for window: AXUIElement) -> AXUIElement? {
        var pid: pid_t = 0
        AXUIElementGetPid(window, &pid)
        guard pid != 0 else { return nil }
        return AXUIElementCreateApplication(pid)
    }

    /// Chrome PWAs use an app-shim process whose accessibility tree is enabled
    /// asynchronously. Toggling Enhanced UI while it starts can invalidate the
    /// remote window proxy, so leave that attribute untouched for app shims.
    private static func shouldManageEnhancedUI(for window: AXUIElement) -> Bool {
        var pid: pid_t = 0
        guard AXUIElementGetPid(window, &pid) == .success,
              let bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier else {
            return true
        }
        return !bundleID.hasPrefix("com.google.Chrome.app.")
    }

    private static func getEnhancedUI(_ app: AXUIElement?) -> Bool {
        guard let app = app else { return false }
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(app, kAXEnhancedUserInterface, &value) == .success else { return false }
        return (value as? Bool) ?? false
    }

    private static func setEnhancedUI(_ app: AXUIElement?, enabled: Bool) {
        guard let app = app else { return }
        let error = AXUIElementSetAttributeValue(app, kAXEnhancedUserInterface, enabled as CFBoolean)
        if error != .success {
            logAX("set enhanced UI=\(enabled)", error: error, for: app)
        }
    }

    // MARK: - AX Helpers

    static func getFocusedWindow() -> AXUIElement? {
        struct AppCandidate {
            let element: AXUIElement
            let pid: pid_t
            let bundleID: String?
            let source: String
        }

        var appCandidates: [AppCandidate] = []
        var seenPIDs = Set<pid_t>()

        func addApp(_ element: AXUIElement, source: String) {
            var pid: pid_t = 0
            let pidError = AXUIElementGetPid(element, &pid)
            guard pidError == .success, pid != 0, seenPIDs.insert(pid).inserted else { return }
            let bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
            appCandidates.append(AppCandidate(element: element, pid: pid, bundleID: bundleID, source: source))
        }

        let workspaceApp = NSWorkspace.shared.frontmostApplication
        let workspaceIsChromeAppShim = workspaceApp?.bundleIdentifier?
            .hasPrefix("com.google.Chrome.app.") == true

        // For Chrome PWAs, prefer the concrete workspace App Shim. During startup,
        // the system-wide AX focus may temporarily point at Chrome's browser process.
        if workspaceIsChromeAppShim, let workspaceApp {
            addApp(
                AXUIElementCreateApplication(workspaceApp.processIdentifier),
                source: "workspace-app-shim"
            )
        }

        // Ask the system-wide element first for regular apps. This preserves the AX
        // server's view of focus when it differs from NSWorkspace during activation.
        let systemWide = AXUIElementCreateSystemWide()
        var focusedApp: AnyObject?
        let focusedAppError = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedApplicationAttribute as CFString,
            &focusedApp
        )
        if focusedAppError == .success, let app = axElement(from: focusedApp) {
            addApp(app, source: "system-wide")
        } else if focusedAppError != .success {
            logAX("read focused application", error: focusedAppError, for: systemWide)
        }

        // Also consider NSWorkspace. Electron launchers can expose a different
        // process identity from the actual window-owning process.
        if !workspaceIsChromeAppShim, let workspaceApp {
            addApp(
                AXUIElementCreateApplication(workspaceApp.processIdentifier),
                source: "workspace"
            )
        }

        for app in appCandidates {
            // Reading AXRole intentionally wakes Chromium's lazy accessibility tree.
            var appRole: AnyObject?
            let roleError = AXUIElementCopyAttributeValue(
                app.element,
                kAXRoleAttribute as CFString,
                &appRole
            )
            if roleError != .success {
                logAX(
                    "initialize app accessibility",
                    error: roleError,
                    pid: app.pid,
                    bundleID: app.bundleID,
                    path: app.source
                )
            }

            var seenWindows = Set<CFHashCode>()
            let directAttributes: [(CFString, String)] = [
                (kAXFocusedWindowAttribute as CFString, "focusedWindow"),
                (kAXMainWindowAttribute as CFString, "mainWindow")
            ]

            for (attribute, path) in directAttributes {
                var value: AnyObject?
                let error = AXUIElementCopyAttributeValue(app.element, attribute, &value)
                if error == .success, let window = axElement(from: value) {
                    let hash = CFHash(window)
                    guard seenWindows.insert(hash).inserted else { continue }
                    if isUsableWindow(window) {
                        logAXSelection(pid: app.pid, bundleID: app.bundleID, path: "\(app.source).\(path)")
                        return window
                    }
                } else if error != .noValue && error != .attributeUnsupported {
                    logAX(
                        "read \(path)",
                        error: error,
                        pid: app.pid,
                        bundleID: app.bundleID,
                        path: app.source
                    )
                }
            }

            var windowsValue: AnyObject?
            let windowsError = AXUIElementCopyAttributeValue(
                app.element,
                kAXWindowsAttribute as CFString,
                &windowsValue
            )
            if windowsError == .success, let rawWindows = windowsValue as? [AnyObject] {
                for rawWindow in rawWindows {
                    guard let window = axElement(from: rawWindow) else { continue }
                    let hash = CFHash(window)
                    guard seenWindows.insert(hash).inserted else { continue }
                    if isUsableWindow(window) {
                        logAXSelection(pid: app.pid, bundleID: app.bundleID, path: "\(app.source).windows")
                        return window
                    }
                }
            } else if windowsError != .noValue && windowsError != .attributeUnsupported {
                logAX(
                    "read windows",
                    error: windowsError,
                    pid: app.pid,
                    bundleID: app.bundleID,
                    path: app.source
                )
            }
        }

        let identities = appCandidates.map {
            "\($0.pid):\($0.bundleID ?? "unknown")[\($0.source)]"
        }.joined(separator: ",")
        logAXMessage("no usable focused window apps=\(identities)", key: "no-window-\(identities)")
        return nil
    }

    static func setPositionPublic(of window: AXUIElement, to point: CGPoint) {
        _ = setPosition(of: window, to: point)
    }

    @discardableResult
    private static func setPosition(of window: AXUIElement, to point: CGPoint) -> AXError {
        var p = point
        guard let value = AXValueCreate(.cgPoint, &p) else {
            logAX("create position value", error: .failure, for: window)
            return .failure
        }
        let error = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value)
        if error != .success {
            logAX("set position", error: error, for: window)
        }
        return error
    }

    @discardableResult
    private static func setSize(of window: AXUIElement, to size: CGSize) -> AXError {
        var s = size
        guard let value = AXValueCreate(.cgSize, &s) else {
            logAX("create size value", error: .failure, for: window)
            return .failure
        }
        let error = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, value)
        if error != .success {
            logAX("set size", error: error, for: window)
        }
        return error
    }

    static func getPosition(of window: AXUIElement) -> CGPoint? {
        var value: AnyObject?
        let error = AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &value)
        guard error == .success, let axValue = axValue(from: value), AXValueGetType(axValue) == .cgPoint else {
            return nil
        }
        var point = CGPoint.zero
        guard AXValueGetValue(axValue, .cgPoint, &point) else { return nil }
        return point
    }

    static func getSize(of window: AXUIElement) -> CGSize? {
        var value: AnyObject?
        let error = AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &value)
        guard error == .success, let axValue = axValue(from: value), AXValueGetType(axValue) == .cgSize else {
            return nil
        }
        var size = CGSize.zero
        guard AXValueGetValue(axValue, .cgSize, &size) else { return nil }
        return size
    }

    private static func isUsableWindow(_ window: AXUIElement) -> Bool {
        var pid: pid_t = 0
        _ = AXUIElementGetPid(window, &pid)

        var roleValue: AnyObject?
        let roleError = AXUIElementCopyAttributeValue(
            window,
            kAXRoleAttribute as CFString,
            &roleValue
        )
        guard roleError == .success,
              let role = roleValue as? String,
              role == (kAXWindowRole as String) else {
            if roleError != .success {
                logAX("validate window role", error: roleError, for: window)
            }
            return false
        }

        var minimizedValue: AnyObject?
        let minimizedError = AXUIElementCopyAttributeValue(
            window,
            kAXMinimizedAttribute as CFString,
            &minimizedValue
        )
        if minimizedError == .success, (minimizedValue as? Bool) == true {
            return false
        }
        if minimizedError != .success,
           minimizedError != .noValue,
           minimizedError != .attributeUnsupported {
            logAX("read minimized state", error: minimizedError, for: window)
            return false
        }

        guard getPosition(of: window) != nil, getSize(of: window) != nil else {
            logAXMessage("rejected window pid=\(pid) reason=unreadable-frame", key: "unreadable-frame-\(pid)")
            return false
        }

        var positionSettable = DarwinBoolean(false)
        let positionError = AXUIElementIsAttributeSettable(
            window,
            kAXPositionAttribute as CFString,
            &positionSettable
        )
        guard positionError == .success, positionSettable.boolValue else {
            if positionError != .success {
                logAX("check position settable", error: positionError, for: window)
            }
            return false
        }

        var sizeSettable = DarwinBoolean(false)
        let sizeError = AXUIElementIsAttributeSettable(
            window,
            kAXSizeAttribute as CFString,
            &sizeSettable
        )
        guard sizeError == .success, sizeSettable.boolValue else {
            if sizeError != .success {
                logAX("check size settable", error: sizeError, for: window)
            }
            return false
        }

        return true
    }

    private static func axElement(from value: AnyObject?) -> AXUIElement? {
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeBitCast(value, to: AXUIElement.self)
    }

    private static func axValue(from value: AnyObject?) -> AXValue? {
        guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        return unsafeBitCast(value, to: AXValue.self)
    }

    private static func raise(_ window: AXUIElement) {
        let error = AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        if error != .success {
            logAX("raise window", error: error, for: window)
        }
    }

    private static func logAXSelection(pid: pid_t, bundleID: String?, path: String) {
        logAXMessage(
            "AX window selected pid=\(pid) bundle=\(bundleID ?? "unknown") path=\(path)",
            key: "selection-\(pid)-\(path)",
            interval: 30
        )
    }

    private static func logAX(_ operation: String, error: AXError, for element: AXUIElement) {
        var pid: pid_t = 0
        _ = AXUIElementGetPid(element, &pid)
        let bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
        logAX(operation, error: error, pid: pid, bundleID: bundleID, path: nil)
    }

    private static func logAX(
        _ operation: String,
        error: AXError,
        pid: pid_t,
        bundleID: String?,
        path: String?
    ) {
        let pathDescription = path.map { " path=\($0)" } ?? ""
        let message = "AX \(operation) failed error=\(error.rawValue) pid=\(pid) "
            + "bundle=\(bundleID ?? "unknown")\(pathDescription)"
        logAXMessage(message, key: "\(operation)-\(error.rawValue)-\(pid)-\(path ?? "")")
    }

    private static func logAXMessage(
        _ message: String,
        key: String,
        interval: TimeInterval = axLogThrottleInterval
    ) {
        let now = Date.timeIntervalSinceReferenceDate
        if let last = lastAXLogTimes[key], now - last < interval { return }
        lastAXLogTimes[key] = now
        NSLog("[EpycZones] %@", message)
    }

    static func screenForWindow(_ window: AXUIElement) -> NSScreen? {
        guard let axPos = getPosition(of: window),
              let axSize = getSize(of: window) else { return nil }

        let centerAX = CGPoint(x: axPos.x + axSize.width / 2, y: axPos.y + axSize.height / 2)
        let primaryHeight = NSScreen.screens[0].frame.height
        let centerNS = NSPoint(x: centerAX.x, y: primaryHeight - centerAX.y)

        for screen in NSScreen.screens {
            if screen.frame.contains(centerNS) {
                return screen
            }
        }
        return nil
    }
}
