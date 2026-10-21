import AppKit
import ApplicationServices

/// Snaps a window after the user drops it. Recent macOS releases may commit
/// AX size and position writes asynchronously, so each phase waits for the
/// window to settle before the next write is sent, and a direct attempt
/// falls back once through a safe position before restoring the dropped frame.
@MainActor
final class PostDragSnapCoordinator {
    private struct Geometry {
        let axPosition: CGPoint
        let size: CGSize
    }

    private enum WaitOutcome {
        case reached
        case settled
        case timedOut
        case cancelled
    }

    private struct GeometryWait {
        let token: Int
        let deadline: TimeInterval
        let stableEligibleAt: TimeInterval
        let stableInterval: TimeInterval?
        let predicate: (Geometry) -> Bool
        let completion: (WaitOutcome, Geometry?) -> Void
        var lastGeometry: Geometry?
        var lastChangeTime: TimeInterval
    }

    private static let observerCallback: AXObserverCallback = { _, _, _, refcon in
        guard let refcon else { return }
        let coordinator = Unmanaged<PostDragSnapCoordinator>
            .fromOpaque(refcon)
            .takeUnretainedValue()
        coordinator.evaluateActiveWait()
    }

    private let targetNS: CGRect
    private let capturedWindow: AXUIElement
    private let capturedPID: pid_t
    private let safeVisibleFrame: CGRect
    private let droppedFrame: CGRect
    private let isStillValid: () -> Bool
    private let completion: (AXUIElement, Bool) -> Void
    private let startedAt = ProcessInfo.processInfo.systemUptime

    private var window: AXUIElement
    private var observer: AXObserver?
    private var observesMove = false
    private var observesResize = false
    private var activeWait: GeometryWait?
    private var waitToken = 0
    private var isUsingFallback = false
    private var isFinished = false
    private var keepAlive: PostDragSnapCoordinator?

    init(
        targetNS: CGRect,
        capturedWindow: AXUIElement,
        safeVisibleFrame: CGRect,
        droppedFrame: CGRect,
        isStillValid: @escaping () -> Bool,
        completion: @escaping (AXUIElement, Bool) -> Void
    ) {
        self.targetNS = targetNS
        self.capturedWindow = capturedWindow
        self.capturedPID = AXWindow.processID(of: capturedWindow)
        self.safeVisibleFrame = safeVisibleFrame
        self.droppedFrame = droppedFrame
        self.isStillValid = isStillValid
        self.completion = completion
        self.window = capturedWindow
    }

    func start() {
        keepAlive = self
        let preserveCapturedWindow = AXWindow.isChromeAppShim(pid: capturedPID)
        window = Self.resolvedPostDragWindow(
            capturedWindow: capturedWindow,
            capturedPID: capturedPID,
            preserveCapturedWindow: preserveCapturedWindow
        )
        installObserver()

        // Start as soon as the frame has been quiet for a few display
        // refreshes. The timeout covers apps that keep reporting tiny
        // post-mouse-up changes or do not publish AX notifications.
        beginWait(
            timeout: 0.12,
            stableInterval: 0.035,
            minimumStableDelay: 0,
            predicate: { _ in false }
        ) { [weak self] outcome, _ in
            guard let self else { return }
            guard outcome != .cancelled else {
                self.finish(success: false)
                return
            }
            self.runSnapSequence(usingSafeStaging: false)
        }
    }

    private func runSnapSequence(usingSafeStaging: Bool) {
        guard validateOperation() else { return }
        isUsingFallback = usingSafeStaging
        if usingSafeStaging {
            applySafePosition()
        } else {
            applyCompactTargetFrame()
        }
    }

    private func applySafePosition() {
        let safePosition = ScreenCoordinates.axOrigin(of: safeVisibleFrame)
        AXWindow.logMessage(
            "post-drag snap using one safe fallback",
            key: "post-drag-safe-fallback-\(capturedPID)",
            interval: 1
        )
        let error = AXWindow.setPosition(of: window, to: safePosition)
        if error != .success {
            AXWindow.log("post-drag safe position", error: error, for: window)
        }
        waitForPosition(safePosition) { [weak self] outcome in
            guard let self else { return }
            guard outcome != .cancelled else {
                self.finish(success: false)
                return
            }
            self.applyCompactTargetFrame()
        }
    }

    /// Sends the complete target frame as one compact AX transaction. The
    /// WindowServer may animate how it commits these writes, but no further
    /// write is sent until that transition has reached or settled.
    private func applyCompactTargetFrame() {
        guard validateOperation() else { return }
        let targetPosition = axPosition(for: targetNS)
        WindowManager.applyFrame(targetNS, to: window, animated: false)
        beginWait(
            timeout: 0.65,
            stableInterval: 0.06,
            minimumStableDelay: 0.18,
            predicate: { [weak self] geometry in
                guard let self else { return false }
                return self.sizeMatches(geometry.size, self.targetNS.size)
                    && self.positionMatches(geometry.axPosition, targetPosition)
            }
        ) { [weak self] outcome, _ in
            guard let self else { return }
            guard outcome != .cancelled else {
                self.finish(success: false)
                return
            }
            self.verifySequence()
        }
    }

    private func verifySequence() {
        guard validateOperation() else { return }
        if let actual = AXWindow.frame(of: window),
           actual.isClose(to: targetNS, tolerance: 2)
                || isUsingFallback
                && Self.frameReachedOrAdvanced(from: droppedFrame, to: actual, toward: targetNS) {
            let elapsedMs = (ProcessInfo.processInfo.systemUptime - startedAt) * 1_000
            let mode = isUsingFallback ? "safe-fallback" : "direct"
            AXWindow.logMessage(
                String(format: "post-drag snap completed mode=%@ elapsed=%.0fms", mode, elapsedMs),
                key: "post-drag-completed-\(capturedPID)-\(mode)",
                interval: 1
            )
            SnapHistory.recordSnap(targetNS, to: window, preSnapFrame: droppedFrame)
            AXWindow.raise(window)
            finish(success: true)
            return
        }

        if !isUsingFallback {
            runSnapSequence(usingSafeStaging: true)
        } else {
            restoreDroppedFrame()
        }
    }

    private func restoreDroppedFrame() {
        guard validateOperation() else { return }
        let droppedPosition = axPosition(for: droppedFrame)
        WindowManager.applyFrame(droppedFrame, to: window, animated: false)
        beginWait(
            timeout: 0.65,
            stableInterval: 0.06,
            minimumStableDelay: 0.18,
            predicate: { [weak self] geometry in
                guard let self else { return false }
                return self.sizeMatches(geometry.size, self.droppedFrame.size)
                    && self.positionMatches(geometry.axPosition, droppedPosition)
            }
        ) { [weak self] outcome, _ in
            guard let self else { return }
            if outcome != .cancelled {
                AXWindow.logMessage(
                    "post-drag snap failed; restored dropped frame",
                    key: "post-drag-restored-\(self.capturedPID)",
                    interval: 5
                )
            }
            self.finish(success: false)
        }
    }

    private func waitForPosition(_ target: CGPoint, completion: @escaping (WaitOutcome) -> Void) {
        beginWait(
            timeout: 0.45,
            stableInterval: 0.05,
            predicate: { [weak self] geometry in
                self?.positionMatches(geometry.axPosition, target) == true
            }
        ) { outcome, _ in
            completion(outcome)
        }
    }

    private func beginWait(
        timeout: TimeInterval,
        stableInterval: TimeInterval?,
        minimumStableDelay: TimeInterval = 0.14,
        predicate: @escaping (Geometry) -> Bool,
        completion: @escaping (WaitOutcome, Geometry?) -> Void
    ) {
        waitToken += 1
        let token = waitToken
        let now = ProcessInfo.processInfo.systemUptime
        let geometry = readGeometry()
        activeWait = GeometryWait(
            token: token,
            deadline: now + timeout,
            stableEligibleAt: now + minimumStableDelay,
            stableInterval: stableInterval,
            predicate: predicate,
            completion: completion,
            lastGeometry: geometry,
            lastChangeTime: now
        )
        evaluateActiveWait()
        schedulePoll(token: token)
    }

    private func evaluateActiveWait() {
        guard var wait = activeWait else { return }
        guard isStillValid() else {
            completeWait(wait, outcome: .cancelled, geometry: readGeometry())
            return
        }

        let now = ProcessInfo.processInfo.systemUptime
        let geometry = readGeometry()
        if let geometry, wait.predicate(geometry) {
            completeWait(wait, outcome: .reached, geometry: geometry)
            return
        }

        if let geometry {
            if let previous = wait.lastGeometry, geometryChanged(previous, geometry) {
                wait.lastChangeTime = now
            }
            wait.lastGeometry = geometry
        }

        if let stableInterval = wait.stableInterval,
           geometry != nil,
           now >= wait.stableEligibleAt,
           now - wait.lastChangeTime >= stableInterval {
            completeWait(wait, outcome: .settled, geometry: geometry)
            return
        }

        if now >= wait.deadline {
            completeWait(wait, outcome: .timedOut, geometry: geometry)
            return
        }
        activeWait = wait
    }

    private func completeWait(_ wait: GeometryWait, outcome: WaitOutcome, geometry: Geometry?) {
        guard activeWait?.token == wait.token else { return }
        activeWait = nil
        waitToken += 1
        wait.completion(outcome, geometry)
    }

    private func schedulePoll(token: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.012) { [weak self] in
            guard let self, self.activeWait?.token == token else { return }
            self.evaluateActiveWait()
            if self.activeWait?.token == token {
                self.schedulePoll(token: token)
            }
        }
    }

    private func installObserver() {
        var createdObserver: AXObserver?
        guard AXObserverCreate(capturedPID, Self.observerCallback, &createdObserver) == .success,
              let createdObserver else { return }

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        observesMove = AXObserverAddNotification(
            createdObserver,
            window,
            kAXMovedNotification as CFString,
            refcon
        ) == .success
        observesResize = AXObserverAddNotification(
            createdObserver,
            window,
            kAXResizedNotification as CFString,
            refcon
        ) == .success
        guard observesMove || observesResize else { return }

        observer = createdObserver
        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(createdObserver),
            .commonModes
        )
    }

    private func removeObserver() {
        guard let observer else { return }
        if observesMove {
            _ = AXObserverRemoveNotification(observer, window, kAXMovedNotification as CFString)
        }
        if observesResize {
            _ = AXObserverRemoveNotification(observer, window, kAXResizedNotification as CFString)
        }
        CFRunLoopRemoveSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(observer),
            .commonModes
        )
        self.observer = nil
    }

    private func readGeometry() -> Geometry? {
        guard let position = AXWindow.position(of: window),
              let size = AXWindow.size(of: window) else { return nil }
        return Geometry(axPosition: position, size: size)
    }

    private func axPosition(for frame: CGRect) -> CGPoint {
        ScreenCoordinates.axOrigin(of: frame)
    }

    private func sizeMatches(_ lhs: CGSize, _ rhs: CGSize) -> Bool {
        abs(lhs.width - rhs.width) < 2 && abs(lhs.height - rhs.height) < 2
    }

    private func positionMatches(_ lhs: CGPoint, _ rhs: CGPoint) -> Bool {
        abs(lhs.x - rhs.x) < 2 && abs(lhs.y - rhs.y) < 2
    }

    private func geometryChanged(_ lhs: Geometry, _ rhs: Geometry) -> Bool {
        abs(lhs.axPosition.x - rhs.axPosition.x) >= 0.5
            || abs(lhs.axPosition.y - rhs.axPosition.y) >= 0.5
            || abs(lhs.size.width - rhs.size.width) >= 0.5
            || abs(lhs.size.height - rhs.size.height) >= 0.5
    }

    private func validateOperation() -> Bool {
        guard isStillValid() else {
            finish(success: false)
            return false
        }
        return true
    }

    private func finish(success: Bool) {
        guard !isFinished else { return }
        isFinished = true
        activeWait = nil
        waitToken += 1
        removeObserver()
        completion(window, success)
        keepAlive = nil
    }

    /// A constrained window may not reach the requested size exactly. It is a
    /// successful snap when every requested component is either within the
    /// normal tolerance or has measurably moved toward its requested value.
    nonisolated static func frameReachedOrAdvanced(from before: CGRect, to after: CGRect, toward target: CGRect) -> Bool {
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
              let focused = WindowManager.getFocusedWindow(),
              AXWindow.processID(of: focused) == capturedPID,
              CFEqual(focused, capturedWindow) else {
            return capturedWindow
        }
        return focused
    }
}
