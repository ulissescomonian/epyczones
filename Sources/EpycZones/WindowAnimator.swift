import AppKit
import ApplicationServices
import OSLog

/// Animates window snapping with smooth interpolation.
/// All AX calls are dispatched to the main thread (required by macOS Tahoe).
enum WindowAnimator {
    private static let steps = 8
    private static let totalDuration: TimeInterval = 0.15

    private final class AnimationResult {
        var succeeded = true
    }

    /// Smoothly animate a window from its current position/size to a target frame.
    /// `targetNS` is in NSScreen coordinates (bottom-left origin).
    /// Call on the main thread: the starting frame is read synchronously.
    ///
    /// - Parameter isCurrent: Checked before every step; once it returns
    ///   false, a newer write owns the window and the remaining steps are skipped.
    static func animate(
        window: AXUIElement,
        to targetNS: CGRect,
        isCurrent: @escaping () -> Bool = { true },
        completion: ((Bool) -> Void)? = nil
    ) {
        // Get current window frame in AX coords
        guard let currentPos = AXWindow.position(of: window),
              let currentSize = AXWindow.size(of: window) else {
            // Fallback: instant snap on main thread
            DispatchQueue.main.async {
                finish(succeeded: AXWindow.setFrame(targetNS, of: window), completion: completion)
            }
            return
        }

        // Interpolate in AX coords: the top-left corner travels in a straight line.
        let targetAX = ScreenCoordinates.axOrigin(of: targetNS)
        let targetSize = targetNS.size

        let stepInterval = totalDuration / Double(steps)
        let result = AnimationResult()

        // Schedule each animation step on the main thread
        for i in 1...steps {
            let delay = stepInterval * Double(i - 1)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard isCurrent() else {
                    if i == steps { finish(succeeded: result.succeeded, completion: completion) }
                    return
                }
                let t = easeOutCubic(Double(i) / Double(steps))

                let x = currentPos.x + (targetAX.x - currentPos.x) * t
                let y = currentPos.y + (targetAX.y - currentPos.y) * t
                let w = currentSize.width + (targetSize.width - currentSize.width) * t
                let h = currentSize.height + (targetSize.height - currentSize.height) * t

                let stepFrame = ScreenCoordinates.nsFrame(
                    axOrigin: CGPoint(x: x, y: y),
                    size: CGSize(width: w, height: h)
                )
                let stepSucceeded = AXWindow.setFrame(stepFrame, of: window)
                result.succeeded = result.succeeded && stepSucceeded

                if i == steps {
                    finish(succeeded: result.succeeded, completion: completion)
                }
            }
        }
    }

    private static func finish(succeeded: Bool, completion: ((Bool) -> Void)?) {
        if !succeeded {
            Log.accessibility.notice("Window animation AX write failed")
        }
        completion?(succeeded)
    }

    /// Ease-out cubic: fast start, smooth deceleration.
    private static func easeOutCubic(_ t: Double) -> Double {
        1 - pow(1 - t, 3)
    }
}
