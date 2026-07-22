import Foundation

enum SnapPosition: String, CaseIterable, Codable {
    // Halves
    case leftHalf, rightHalf, topHalf, bottomHalf, centerHalf
    // Quarters
    case topLeftQuarter, topRightQuarter, bottomLeftQuarter, bottomRightQuarter
    // Thirds (vertical)
    case firstThird, centerThird, lastThird
    // Two-thirds (vertical)
    case firstTwoThirds, centerTwoThirds, lastTwoThirds
    // Fourths (vertical)
    case firstFourth, secondFourth, thirdFourth, lastFourth
    // Three-fourths (vertical)
    case firstThreeFourths, centerThreeFourths, lastThreeFourths
    // Sixths
    case topLeftSixth, topCenterSixth, topRightSixth
    case bottomLeftSixth, bottomCenterSixth, bottomRightSixth
    // Special
    case maximize, almostMaximize, maximizeHeight
    case center
    case dockLeft, dockRight
    // Resize
    case makeSmaller, makeLarger
    // Restore
    case restore

    var displayName: String {
        switch self {
        case .leftHalf:            return "Left Half"
        case .rightHalf:           return "Right Half"
        case .topHalf:             return "Top Half"
        case .bottomHalf:          return "Bottom Half"
        case .centerHalf:          return "Center Half"
        case .topLeftQuarter:      return "Top Left"
        case .topRightQuarter:     return "Top Right"
        case .bottomLeftQuarter:   return "Bottom Left"
        case .bottomRightQuarter:  return "Bottom Right"
        case .firstThird:          return "First Third"
        case .centerThird:         return "Center Third"
        case .lastThird:           return "Last Third"
        case .firstTwoThirds:      return "First Two Thirds"
        case .centerTwoThirds:     return "Center Two Thirds"
        case .lastTwoThirds:       return "Last Two Thirds"
        case .firstFourth:         return "First Fourth"
        case .secondFourth:        return "Second Fourth"
        case .thirdFourth:         return "Third Fourth"
        case .lastFourth:          return "Last Fourth"
        case .firstThreeFourths:   return "First Three Fourths"
        case .centerThreeFourths:  return "Center Three Fourths"
        case .lastThreeFourths:    return "Last Three Fourths"
        case .topLeftSixth:        return "Top Left Sixth"
        case .topCenterSixth:      return "Top Center Sixth"
        case .topRightSixth:       return "Top Right Sixth"
        case .bottomLeftSixth:     return "Bottom Left Sixth"
        case .bottomCenterSixth:   return "Bottom Center Sixth"
        case .bottomRightSixth:    return "Bottom Right Sixth"
        case .maximize:            return "Maximize"
        case .almostMaximize:      return "Almost Maximize"
        case .maximizeHeight:      return "Maximize Height"
        case .center:              return "Center"
        case .dockLeft:            return "Dock Left"
        case .dockRight:           return "Dock Right"
        case .makeSmaller:         return "Make Smaller"
        case .makeLarger:          return "Make Larger"
        case .restore:             return "Restore"
        }
    }

    /// Relative rect (0–1) for the visual preview icon. (0,0) = top-left.
    var previewRect: (x: Double, y: Double, w: Double, h: Double) {
        switch self {
        // Halves
        case .leftHalf:            return (0, 0, 0.5, 1)
        case .rightHalf:           return (0.5, 0, 0.5, 1)
        case .topHalf:             return (0, 0, 1, 0.5)
        case .bottomHalf:          return (0, 0.5, 1, 0.5)
        case .centerHalf:          return (0.25, 0, 0.5, 1)
        // Quarters
        case .topLeftQuarter:      return (0, 0, 0.5, 0.5)
        case .topRightQuarter:     return (0.5, 0, 0.5, 0.5)
        case .bottomLeftQuarter:   return (0, 0.5, 0.5, 0.5)
        case .bottomRightQuarter:  return (0.5, 0.5, 0.5, 0.5)
        // Thirds
        case .firstThird:          return (0, 0, 1.0/3, 1)
        case .centerThird:         return (1.0/3, 0, 1.0/3, 1)
        case .lastThird:           return (2.0/3, 0, 1.0/3, 1)
        // Two-thirds
        case .firstTwoThirds:      return (0, 0, 2.0/3, 1)
        case .centerTwoThirds:     return (1.0/6, 0, 2.0/3, 1)
        case .lastTwoThirds:       return (1.0/3, 0, 2.0/3, 1)
        // Fourths
        case .firstFourth:         return (0, 0, 0.25, 1)
        case .secondFourth:        return (0.25, 0, 0.25, 1)
        case .thirdFourth:         return (0.5, 0, 0.25, 1)
        case .lastFourth:          return (0.75, 0, 0.25, 1)
        // Three-fourths
        case .firstThreeFourths:   return (0, 0, 0.75, 1)
        case .centerThreeFourths:  return (0.125, 0, 0.75, 1)
        case .lastThreeFourths:    return (0.25, 0, 0.75, 1)
        // Sixths
        case .topLeftSixth:        return (0, 0, 1.0/3, 0.5)
        case .topCenterSixth:      return (1.0/3, 0, 1.0/3, 0.5)
        case .topRightSixth:       return (2.0/3, 0, 1.0/3, 0.5)
        case .bottomLeftSixth:     return (0, 0.5, 1.0/3, 0.5)
        case .bottomCenterSixth:   return (1.0/3, 0.5, 1.0/3, 0.5)
        case .bottomRightSixth:    return (2.0/3, 0.5, 1.0/3, 0.5)
        // Special
        case .maximize:            return (0, 0, 1, 1)
        case .almostMaximize:      return (0.03, 0.03, 0.94, 0.94)
        case .maximizeHeight:      return (0.25, 0, 0.5, 1)
        case .center:              return (0.2, 0.1, 0.6, 0.8)
        case .dockLeft:            return (0, 0.1, 0.4, 0.8)
        case .dockRight:           return (0.6, 0.1, 0.4, 0.8)
        case .makeSmaller:         return (0.15, 0.15, 0.7, 0.7)
        case .makeLarger:          return (0.05, 0.05, 0.9, 0.9)
        case .restore:             return (0.2, 0.15, 0.6, 0.7)
        }
    }

    /// Direction to search for adjacent monitor when window already matches this position.
    var flowDirection: WindowManager.FlowDirection {
        switch self {
        // Positions touching the left edge → flow left
        case .leftHalf, .topLeftQuarter, .bottomLeftQuarter,
             .firstThird, .firstTwoThirds, .firstFourth, .firstThreeFourths,
             .topLeftSixth, .bottomLeftSixth:
            return .left
        // Positions touching the right edge → flow right
        case .rightHalf, .topRightQuarter, .bottomRightQuarter,
             .lastThird, .lastTwoThirds, .lastFourth, .lastThreeFourths,
             .topRightSixth, .bottomRightSixth:
            return .right
        // Positions touching the top edge → flow up
        case .topHalf:
            return .up
        // Positions touching the bottom edge → flow down
        case .bottomHalf:
            return .down
        default:
            return .none
        }
    }

    /// The position the window should arrive at on the adjacent monitor.
    /// E.g. leftHalf flowing left → arrives as rightHalf on the left monitor.
    var arrivalPosition: SnapPosition {
        switch self {
        case .leftHalf:           return .rightHalf
        case .rightHalf:          return .leftHalf
        case .topHalf:            return .bottomHalf
        case .bottomHalf:         return .topHalf
        case .topLeftQuarter:     return .topRightQuarter
        case .topRightQuarter:    return .topLeftQuarter
        case .bottomLeftQuarter:  return .bottomRightQuarter
        case .bottomRightQuarter: return .bottomLeftQuarter
        case .firstThird:         return .lastThird
        case .lastThird:          return .firstThird
        case .firstTwoThirds:     return .lastTwoThirds
        case .lastTwoThirds:      return .firstTwoThirds
        case .firstFourth:        return .lastFourth
        case .lastFourth:         return .firstFourth
        case .firstThreeFourths:  return .lastThreeFourths
        case .lastThreeFourths:   return .firstThreeFourths
        case .topLeftSixth:       return .topRightSixth
        case .topRightSixth:      return .topLeftSixth
        case .bottomLeftSixth:    return .bottomRightSixth
        case .bottomRightSixth:   return .bottomLeftSixth
        default:                  return self
        }
    }

    /// Whether this position needs the current window frame (dynamic positions).
    var isDynamic: Bool {
        switch self {
        case .makeSmaller, .makeLarger, .restore, .maximizeHeight, .dockLeft, .dockRight:
            return true
        default:
            return false
        }
    }

    /// Calculate the target frame within a given screen area (NSScreen coordinates, bottom-left origin).
    func frame(in rect: CGRect) -> CGRect {
        let x = rect.origin.x
        let y = rect.origin.y
        let w = rect.width
        let h = rect.height
        let t = 1.0 / 3.0

        switch self {
        // Halves
        case .leftHalf:            return CGRect(x: x, y: y, width: w / 2, height: h)
        case .rightHalf:           return CGRect(x: x + w / 2, y: y, width: w / 2, height: h)
        case .topHalf:             return CGRect(x: x, y: y + h / 2, width: w, height: h / 2)
        case .bottomHalf:          return CGRect(x: x, y: y, width: w, height: h / 2)
        case .centerHalf:          return CGRect(x: x + w / 4, y: y, width: w / 2, height: h)
        // Quarters
        case .topLeftQuarter:      return CGRect(x: x, y: y + h / 2, width: w / 2, height: h / 2)
        case .topRightQuarter:     return CGRect(x: x + w / 2, y: y + h / 2, width: w / 2, height: h / 2)
        case .bottomLeftQuarter:   return CGRect(x: x, y: y, width: w / 2, height: h / 2)
        case .bottomRightQuarter:  return CGRect(x: x + w / 2, y: y, width: w / 2, height: h / 2)
        // Thirds
        case .firstThird:          return CGRect(x: x, y: y, width: w * t, height: h)
        case .centerThird:         return CGRect(x: x + w * t, y: y, width: w * t, height: h)
        case .lastThird:           return CGRect(x: x + w * t * 2, y: y, width: w * t, height: h)
        // Two-thirds
        case .firstTwoThirds:      return CGRect(x: x, y: y, width: w * t * 2, height: h)
        case .centerTwoThirds:     return CGRect(x: x + w / 6, y: y, width: w * t * 2, height: h)
        case .lastTwoThirds:       return CGRect(x: x + w * t, y: y, width: w * t * 2, height: h)
        // Fourths
        case .firstFourth:         return CGRect(x: x, y: y, width: w / 4, height: h)
        case .secondFourth:        return CGRect(x: x + w / 4, y: y, width: w / 4, height: h)
        case .thirdFourth:         return CGRect(x: x + w / 2, y: y, width: w / 4, height: h)
        case .lastFourth:          return CGRect(x: x + w * 3 / 4, y: y, width: w / 4, height: h)
        // Three-fourths
        case .firstThreeFourths:   return CGRect(x: x, y: y, width: w * 3 / 4, height: h)
        case .centerThreeFourths:  return CGRect(x: x + w / 8, y: y, width: w * 3 / 4, height: h)
        case .lastThreeFourths:    return CGRect(x: x + w / 4, y: y, width: w * 3 / 4, height: h)
        // Sixths
        case .topLeftSixth:        return CGRect(x: x, y: y + h / 2, width: w * t, height: h / 2)
        case .topCenterSixth:      return CGRect(x: x + w * t, y: y + h / 2, width: w * t, height: h / 2)
        case .topRightSixth:       return CGRect(x: x + w * t * 2, y: y + h / 2, width: w * t, height: h / 2)
        case .bottomLeftSixth:     return CGRect(x: x, y: y, width: w * t, height: h / 2)
        case .bottomCenterSixth:   return CGRect(x: x + w * t, y: y, width: w * t, height: h / 2)
        case .bottomRightSixth:    return CGRect(x: x + w * t * 2, y: y, width: w * t, height: h / 2)
        // Special
        case .maximize:            return rect
        case .almostMaximize:
            let m = 20.0 // margin
            return CGRect(x: x + m, y: y + m, width: w - m * 2, height: h - m * 2)
        case .maximizeHeight:      return rect // handled dynamically in WindowManager
        case .center:
            let cw = w * 0.6; let ch = h * 0.8
            return CGRect(x: x + (w - cw) / 2, y: y + (h - ch) / 2, width: cw, height: ch)
        // Dynamic — these return placeholder; real logic is in WindowManager
        case .makeSmaller, .makeLarger, .restore, .dockLeft, .dockRight:
            return rect
        }
    }
}
