import Carbon
import Foundation

/// Persistable hotkey binding: a key code + modifier flags.
struct HotKeyBinding: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32 // Carbon modifier flags

    /// Human-readable description, e.g. "⌃⌥←".
    var displayString: String {
        var parts: [String] = []
        if modifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        if modifiers & UInt32(optionKey) != 0 { parts.append("⌥") }
        if modifiers & UInt32(shiftKey) != 0 { parts.append("⇧") }
        if modifiers & UInt32(cmdKey) != 0 { parts.append("⌘") }
        parts.append(keyCodeName(keyCode))
        return parts.joined()
    }

    static let defaultModifiers = UInt32(controlKey | optionKey)

    /// No binding assigned.
    static let none = HotKeyBinding(keyCode: UInt32.max, modifiers: 0)
    var isNone: Bool { keyCode == UInt32.max }
}

/// All configurable hotkey actions, grouped by category.
enum HotKeyAction: String, CaseIterable, Identifiable {
    // Halves
    case leftHalf, rightHalf, topHalf, bottomHalf, centerHalf
    // Quarters
    case topLeftQuarter, topRightQuarter, bottomLeftQuarter, bottomRightQuarter
    // Thirds
    case firstThird, centerThird, lastThird
    // Two-thirds
    case firstTwoThirds, centerTwoThirds, lastTwoThirds
    // Fourths
    case firstFourth, secondFourth, thirdFourth, lastFourth
    // Sixths
    case topLeftSixth, topCenterSixth, topRightSixth
    case bottomLeftSixth, bottomCenterSixth, bottomRightSixth
    // Special
    case maximize, almostMaximize, maximizeHeight, center
    case makeSmaller, makeLarger, restore
    case dockLeft, dockRight
    // Navigation
    case nextMonitor, prevMonitor
    case cycleLayout

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .leftHalf:           return "Left Half"
        case .rightHalf:          return "Right Half"
        case .topHalf:            return "Top Half"
        case .bottomHalf:         return "Bottom Half"
        case .centerHalf:         return "Center Half"
        case .topLeftQuarter:     return "Top Left"
        case .topRightQuarter:    return "Top Right"
        case .bottomLeftQuarter:  return "Bottom Left"
        case .bottomRightQuarter: return "Bottom Right"
        case .firstThird:         return "First Third"
        case .centerThird:        return "Center Third"
        case .lastThird:          return "Last Third"
        case .firstTwoThirds:     return "First Two Thirds"
        case .centerTwoThirds:    return "Center Two Thirds"
        case .lastTwoThirds:      return "Last Two Thirds"
        case .firstFourth:        return "First Fourth"
        case .secondFourth:       return "Second Fourth"
        case .thirdFourth:        return "Third Fourth"
        case .lastFourth:         return "Last Fourth"
        case .topLeftSixth:       return "Top Left Sixth"
        case .topCenterSixth:     return "Top Center Sixth"
        case .topRightSixth:      return "Top Right Sixth"
        case .bottomLeftSixth:    return "Bottom Left Sixth"
        case .bottomCenterSixth:  return "Bottom Center Sixth"
        case .bottomRightSixth:   return "Bottom Right Sixth"
        case .maximize:           return "Maximize"
        case .almostMaximize:     return "Almost Maximize"
        case .maximizeHeight:     return "Maximize Height"
        case .center:             return "Center"
        case .makeSmaller:        return "Make Smaller"
        case .makeLarger:         return "Make Larger"
        case .restore:            return "Restore"
        case .dockLeft:           return "Dock Left"
        case .dockRight:          return "Dock Right"
        case .nextMonitor:        return "Next Display"
        case .prevMonitor:        return "Previous Display"
        case .cycleLayout:        return "Cycle Layout"
        }
    }

    var category: String {
        switch self {
        case .leftHalf, .rightHalf, .topHalf, .bottomHalf, .centerHalf:
            return "Halves"
        case .topLeftQuarter, .topRightQuarter, .bottomLeftQuarter, .bottomRightQuarter:
            return "Quarters"
        case .firstThird, .centerThird, .lastThird:
            return "Thirds"
        case .firstTwoThirds, .centerTwoThirds, .lastTwoThirds:
            return "Two Thirds"
        case .firstFourth, .secondFourth, .thirdFourth, .lastFourth:
            return "Fourths"
        case .topLeftSixth, .topCenterSixth, .topRightSixth,
             .bottomLeftSixth, .bottomCenterSixth, .bottomRightSixth:
            return "Sixths"
        case .maximize, .almostMaximize, .maximizeHeight, .center, .makeSmaller, .makeLarger, .restore,
             .dockLeft, .dockRight:
            return "Special"
        case .nextMonitor, .prevMonitor, .cycleLayout:
            return "Navigation"
        }
    }

    /// Corresponding SnapPosition (nil for navigation/non-snap actions).
    var snapPosition: SnapPosition? {
        switch self {
        case .leftHalf:           return .leftHalf
        case .rightHalf:          return .rightHalf
        case .topHalf:            return .topHalf
        case .bottomHalf:         return .bottomHalf
        case .centerHalf:         return .centerHalf
        case .topLeftQuarter:     return .topLeftQuarter
        case .topRightQuarter:    return .topRightQuarter
        case .bottomLeftQuarter:  return .bottomLeftQuarter
        case .bottomRightQuarter: return .bottomRightQuarter
        case .firstThird:         return .firstThird
        case .centerThird:        return .centerThird
        case .lastThird:          return .lastThird
        case .firstTwoThirds:     return .firstTwoThirds
        case .centerTwoThirds:    return .centerTwoThirds
        case .lastTwoThirds:      return .lastTwoThirds
        case .firstFourth:        return .firstFourth
        case .secondFourth:       return .secondFourth
        case .thirdFourth:        return .thirdFourth
        case .lastFourth:         return .lastFourth
        case .topLeftSixth:       return .topLeftSixth
        case .topCenterSixth:     return .topCenterSixth
        case .topRightSixth:      return .topRightSixth
        case .bottomLeftSixth:    return .bottomLeftSixth
        case .bottomCenterSixth:  return .bottomCenterSixth
        case .bottomRightSixth:   return .bottomRightSixth
        case .maximize:           return .maximize
        case .almostMaximize:     return .almostMaximize
        case .maximizeHeight:     return .maximizeHeight
        case .center:             return .center
        case .makeSmaller:        return .makeSmaller
        case .makeLarger:         return .makeLarger
        case .restore:            return .restore
        case .dockLeft:           return .dockLeft
        case .dockRight:          return .dockRight
        default:                  return nil
        }
    }

    /// Preview rect for visual icon (0–1, top-left origin).
    var previewRect: (x: Double, y: Double, w: Double, h: Double) {
        snapPosition?.previewRect ?? (0.2, 0.2, 0.6, 0.6)
    }

    var defaultBinding: HotKeyBinding {
        let mods = HotKeyBinding.defaultModifiers
        switch self {
        case .leftHalf:           return HotKeyBinding(keyCode: UInt32(kVK_ANSI_Keypad4), modifiers: mods)
        case .rightHalf:          return HotKeyBinding(keyCode: UInt32(kVK_ANSI_Keypad6), modifiers: mods)
        case .topHalf:            return HotKeyBinding(keyCode: UInt32(kVK_ANSI_Keypad8), modifiers: mods)
        case .bottomHalf:         return HotKeyBinding(keyCode: UInt32(kVK_ANSI_Keypad2), modifiers: mods)
        case .centerHalf:         return .none
        case .topLeftQuarter:     return HotKeyBinding(keyCode: UInt32(kVK_ANSI_U), modifiers: mods)
        case .topRightQuarter:    return HotKeyBinding(keyCode: UInt32(kVK_ANSI_I), modifiers: mods)
        case .bottomLeftQuarter:  return HotKeyBinding(keyCode: UInt32(kVK_ANSI_J), modifiers: mods)
        case .bottomRightQuarter: return HotKeyBinding(keyCode: UInt32(kVK_ANSI_K), modifiers: mods)
        case .firstThird:         return HotKeyBinding(keyCode: UInt32(kVK_ANSI_D), modifiers: mods)
        case .centerThird:        return HotKeyBinding(keyCode: UInt32(kVK_ANSI_F), modifiers: mods)
        case .lastThird:          return HotKeyBinding(keyCode: UInt32(kVK_ANSI_G), modifiers: mods)
        case .firstTwoThirds:     return HotKeyBinding(keyCode: UInt32(kVK_ANSI_E), modifiers: mods)
        case .centerTwoThirds:    return HotKeyBinding(keyCode: UInt32(kVK_ANSI_R), modifiers: mods)
        case .lastTwoThirds:      return HotKeyBinding(keyCode: UInt32(kVK_ANSI_T), modifiers: mods)
        case .firstFourth:        return .none
        case .secondFourth:       return .none
        case .thirdFourth:        return .none
        case .lastFourth:         return .none
        case .topLeftSixth:       return .none
        case .topCenterSixth:     return .none
        case .topRightSixth:      return .none
        case .bottomLeftSixth:    return .none
        case .bottomCenterSixth:  return .none
        case .bottomRightSixth:   return .none
        case .maximize:           return HotKeyBinding(keyCode: UInt32(kVK_Return), modifiers: mods)
        case .almostMaximize:     return .none
        case .maximizeHeight:     return HotKeyBinding(keyCode: UInt32(kVK_ANSI_H), modifiers: mods)
        case .center:             return HotKeyBinding(keyCode: UInt32(kVK_ANSI_Keypad5), modifiers: mods)
        case .makeSmaller:        return HotKeyBinding(keyCode: UInt32(kVK_ANSI_Minus), modifiers: mods)
        case .makeLarger:         return HotKeyBinding(keyCode: UInt32(kVK_ANSI_Equal), modifiers: mods)
        case .restore:            return HotKeyBinding(keyCode: UInt32(kVK_Delete), modifiers: mods)
        case .dockLeft:           return HotKeyBinding(keyCode: UInt32(kVK_ANSI_Keypad7), modifiers: mods)
        case .dockRight:          return HotKeyBinding(keyCode: UInt32(kVK_ANSI_Keypad9), modifiers: mods)
        case .nextMonitor:        return HotKeyBinding(keyCode: UInt32(kVK_ANSI_N), modifiers: mods)
        case .prevMonitor:        return HotKeyBinding(keyCode: UInt32(kVK_ANSI_P), modifiers: mods)
        case .cycleLayout:        return HotKeyBinding(keyCode: UInt32(kVK_ANSI_L), modifiers: mods)
        }
    }
}

/// Resolve binding: custom if set, otherwise default.
func resolvedBinding(for action: HotKeyAction) -> HotKeyBinding {
    AppSettings.shared.customHotKeys[action.rawValue] ?? action.defaultBinding
}

// MARK: - Key Code Name Lookup

func keyCodeName(_ keyCode: UInt32) -> String {
    switch Int(keyCode) {
    case kVK_LeftArrow:    return "←"
    case kVK_RightArrow:   return "→"
    case kVK_UpArrow:      return "↑"
    case kVK_DownArrow:    return "↓"
    case kVK_Return:       return "⏎"
    case kVK_Tab:          return "⇥"
    case kVK_Space:        return "Space"
    case kVK_Delete:       return "⌫"
    case kVK_Escape:       return "⎋"
    case kVK_ANSI_Minus:   return "-"
    case kVK_ANSI_Equal:   return "="
    case kVK_ANSI_A:       return "A"
    case kVK_ANSI_B:       return "B"
    case kVK_ANSI_C:       return "C"
    case kVK_ANSI_D:       return "D"
    case kVK_ANSI_E:       return "E"
    case kVK_ANSI_F:       return "F"
    case kVK_ANSI_G:       return "G"
    case kVK_ANSI_H:       return "H"
    case kVK_ANSI_I:       return "I"
    case kVK_ANSI_J:       return "J"
    case kVK_ANSI_K:       return "K"
    case kVK_ANSI_L:       return "L"
    case kVK_ANSI_M:       return "M"
    case kVK_ANSI_N:       return "N"
    case kVK_ANSI_O:       return "O"
    case kVK_ANSI_P:       return "P"
    case kVK_ANSI_Q:       return "Q"
    case kVK_ANSI_R:       return "R"
    case kVK_ANSI_S:       return "S"
    case kVK_ANSI_T:       return "T"
    case kVK_ANSI_U:       return "U"
    case kVK_ANSI_V:       return "V"
    case kVK_ANSI_W:       return "W"
    case kVK_ANSI_X:       return "X"
    case kVK_ANSI_Y:       return "Y"
    case kVK_ANSI_Z:       return "Z"
    case kVK_ANSI_0:       return "0"
    case kVK_ANSI_1:       return "1"
    case kVK_ANSI_2:       return "2"
    case kVK_ANSI_3:       return "3"
    case kVK_ANSI_4:       return "4"
    case kVK_ANSI_5:       return "5"
    case kVK_ANSI_6:       return "6"
    case kVK_ANSI_7:       return "7"
    case kVK_ANSI_8:       return "8"
    case kVK_ANSI_9:       return "9"
    case kVK_ANSI_Keypad0:   return "Num0"
    case kVK_ANSI_Keypad1:   return "Num1"
    case kVK_ANSI_Keypad2:   return "Num2"
    case kVK_ANSI_Keypad3:   return "Num3"
    case kVK_ANSI_Keypad4:   return "Num4"
    case kVK_ANSI_Keypad5:   return "Num5"
    case kVK_ANSI_Keypad6:   return "Num6"
    case kVK_ANSI_Keypad7:   return "Num7"
    case kVK_ANSI_Keypad8:   return "Num8"
    case kVK_ANSI_Keypad9:   return "Num9"
    default:
        if keyCode == UInt32.max { return "—" }
        return "Key\(keyCode)"
    }
}
