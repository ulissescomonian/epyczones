import ApplicationServices
import CoreGraphics
import Foundation

/// Per-window memory of snaps: the undo stack for Restore, the step of the
/// repeated half-width cycle, and the size to give back when a snapped window
/// is dragged away.
enum SnapHistory {

    // MARK: - Undo

    private static let maxUndoDepth = 20

    /// Frames before each snap or resize, most recent last.
    private static var undoStacks = WindowStateMap<[CGRect]>()

    /// Pushes the window's current frame onto its undo stack.
    static func saveFrame(of window: AXUIElement) {
        guard let frame = AXWindow.frame(of: window) else { return }
        pushUndo(frame, for: window)
    }

    static func pushUndo(_ frame: CGRect, for window: AXUIElement) {
        var stack = undoStacks[window] ?? []
        stack.append(frame)
        if stack.count > maxUndoDepth {
            stack.removeFirst()
        }
        undoStacks[window] = stack
    }

    /// Takes the most recent frame off the window's undo stack.
    static func popUndo(for window: AXUIElement) -> CGRect? {
        guard var stack = undoStacks[window], let previous = stack.popLast() else { return nil }
        undoStacks[window] = stack.isEmpty ? nil : stack
        return previous
    }

    // MARK: - Half-width Cycle

    /// One step of the repeated half-snap width cycle.
    struct CycleStep {
        let position: SnapPosition
        let index: Int
        /// The requested frame, so clamped windows (min width > step width)
        /// still advance the cycle instead of looping forever.
        let frame: CGRect
        let recordedAt: TimeInterval
    }

    /// How long a recorded cycle step is trusted without comparing frames:
    /// longer than the snap animation, shorter than a deliberate pause.
    static let cycleAnimationGrace: TimeInterval = 0.5

    private static var cycleSteps = WindowStateMap<CycleStep>()

    static func cycleStep(for window: AXUIElement) -> CycleStep? {
        cycleSteps[window]
    }

    static func setCycleStep(_ step: CycleStep?, for window: AXUIElement) {
        cycleSteps[window] = step
    }

    // MARK: - Snaps and Drag-away Restore

    /// Last applied snap frame per window.
    private static var snapFrames = WindowStateMap<CGRect>()
    /// Window size before the first snap in a chain, restored when the window is dragged away.
    private static var dragRestoreSizes = WindowStateMap<CGSize>()

    /// Records a completed snap: undo, cycle reset and drag-away size.
    static func recordSnap(_ targetNS: CGRect, to window: AXUIElement, preSnapFrame: CGRect?) {
        if let preSnapFrame {
            pushUndo(preSnapFrame, for: window)
        }

        // Any snap invalidates the cycle chain; the cycling code re-records
        // its state right after calling applySnap.
        cycleSteps[window] = nil
        if let pre = preSnapFrame {
            // Snapping from one snap position to another keeps the original restore size.
            let wasSnapped = snapFrames[window].map { pre.isClose(to: $0, tolerance: 15) } ?? false
            if !wasSnapped {
                dragRestoreSizes[window] = pre.size
            }
        }
        snapFrames[window] = targetNS
    }

    /// If the window currently sits at its recorded snap frame, the size to restore on drag-away.
    static func dragRestoreSize(for window: AXUIElement) -> CGSize? {
        guard let snapped = snapFrames[window],
              let size = dragRestoreSizes[window],
              let current = AXWindow.frame(of: window),
              current.isClose(to: snapped, tolerance: 15) else { return nil }
        return size
    }
}
