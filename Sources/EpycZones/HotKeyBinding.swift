import Carbon
import SwiftUI

/// Persistable hotkey binding: a key code + modifier flags.
struct HotKeyBinding: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32 // Carbon modifier flags

    /// Human-readable description, e.g. "⌃⌥←".
    var displayString: String {
        modifierSymbols + keyName
    }

    /// Modifier glyphs in Apple's order: ⌃⌥⇧⌘.
    var modifierSymbols: String {
        var parts: [String] = []
        if modifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        if modifiers & UInt32(optionKey) != 0 { parts.append("⌥") }
        if modifiers & UInt32(shiftKey) != 0 { parts.append("⇧") }
        if modifiers & UInt32(cmdKey) != 0 { parts.append("⌘") }
        return parts.joined()
    }

    var keyName: String {
        keyCodeName(keyCode)
    }

    static let defaultModifiers = UInt32(controlKey | optionKey)

    /// No binding assigned.
    static let none = HotKeyBinding(keyCode: UInt32.max, modifiers: 0)
    var isNone: Bool { keyCode == UInt32.max }

    /// Zone shortcuts for digits 1 … 9 with the given modifiers, in zone order.
    static func zoneBindings(modifiers: UInt32) -> [HotKeyBinding] {
        [
            kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5,
            kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9,
        ].map { HotKeyBinding(keyCode: UInt32($0), modifiers: modifiers) }
    }

    enum Validation: Equatable {
        case valid
        /// Global shortcuts need ⌃, ⌥ or ⌘; Shift alone would capture typing.
        case needsModifier
        /// Already used; carries the name of the action or zone that owns it.
        case conflict(String)
    }

    /// Checks whether `self` can become the shortcut for `action`, given the
    /// other actions' current bindings and the zone shortcuts.
    func validate(
        for action: HotKeyAction,
        customBindings: [String: HotKeyBinding],
        zoneModifiers: UInt32 = ZoneShortcutModifiers.default.rawValue
    ) -> Validation {
        let requiredModifiers = UInt32(controlKey | optionKey | cmdKey)
        guard modifiers & requiredModifiers != 0 else { return .needsModifier }

        if let zoneIndex = Self.zoneBindings(modifiers: zoneModifiers).firstIndex(of: self) {
            return .conflict("Zone \(zoneIndex + 1)")
        }
        for other in HotKeyAction.allCases where other != action {
            let otherBinding = customBindings[other.rawValue] ?? other.defaultBinding
            if otherBinding == self {
                return .conflict(other.displayName)
            }
        }
        return .valid
    }
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
        case .leftHalf:           return String(localized: "Left Half")
        case .rightHalf:          return String(localized: "Right Half")
        case .topHalf:            return String(localized: "Top Half")
        case .bottomHalf:         return String(localized: "Bottom Half")
        case .centerHalf:         return String(localized: "Center Half")
        case .topLeftQuarter:     return String(localized: "Top Left")
        case .topRightQuarter:    return String(localized: "Top Right")
        case .bottomLeftQuarter:  return String(localized: "Bottom Left")
        case .bottomRightQuarter: return String(localized: "Bottom Right")
        case .firstThird:         return String(localized: "First Third")
        case .centerThird:        return String(localized: "Center Third")
        case .lastThird:          return String(localized: "Last Third")
        case .firstTwoThirds:     return String(localized: "First Two Thirds")
        case .centerTwoThirds:    return String(localized: "Center Two Thirds")
        case .lastTwoThirds:      return String(localized: "Last Two Thirds")
        case .firstFourth:        return String(localized: "First Fourth")
        case .secondFourth:       return String(localized: "Second Fourth")
        case .thirdFourth:        return String(localized: "Third Fourth")
        case .lastFourth:         return String(localized: "Last Fourth")
        case .topLeftSixth:       return String(localized: "Top Left Sixth")
        case .topCenterSixth:     return String(localized: "Top Center Sixth")
        case .topRightSixth:      return String(localized: "Top Right Sixth")
        case .bottomLeftSixth:    return String(localized: "Bottom Left Sixth")
        case .bottomCenterSixth:  return String(localized: "Bottom Center Sixth")
        case .bottomRightSixth:   return String(localized: "Bottom Right Sixth")
        case .maximize:           return String(localized: "Maximize")
        case .almostMaximize:     return String(localized: "Almost Maximize")
        case .maximizeHeight:     return String(localized: "Maximize Height")
        case .center:             return String(localized: "Center")
        case .makeSmaller:        return String(localized: "Make Smaller")
        case .makeLarger:         return String(localized: "Make Larger")
        case .restore:            return String(localized: "Restore")
        case .dockLeft:           return String(localized: "Dock Left")
        case .dockRight:          return String(localized: "Dock Right")
        case .nextMonitor:        return String(localized: "Next Display")
        case .prevMonitor:        return String(localized: "Previous Display")
        case .cycleLayout:        return String(localized: "Cycle Layout")
        }
    }

    var category: HotKeyCategory {
        switch self {
        case .leftHalf, .rightHalf, .topHalf, .bottomHalf, .centerHalf:
            return .halves
        case .topLeftQuarter, .topRightQuarter, .bottomLeftQuarter, .bottomRightQuarter:
            return .quarters
        case .firstThird, .centerThird, .lastThird:
            return .thirds
        case .firstTwoThirds, .centerTwoThirds, .lastTwoThirds:
            return .twoThirds
        case .firstFourth, .secondFourth, .thirdFourth, .lastFourth:
            return .fourths
        case .topLeftSixth, .topCenterSixth, .topRightSixth,
             .bottomLeftSixth, .bottomCenterSixth, .bottomRightSixth:
            return .sixths
        case .maximize, .almostMaximize, .maximizeHeight, .center, .makeSmaller, .makeLarger, .restore,
             .dockLeft, .dockRight:
            return .special
        case .nextMonitor, .prevMonitor, .cycleLayout:
            return .navigation
        }
    }

    /// An SF Symbol for actions that are not a place on the screen.
    var symbol: String? {
        switch self {
        case .makeSmaller: return "arrow.down.right.and.arrow.up.left"
        case .makeLarger: return "arrow.up.left.and.arrow.down.right"
        case .restore: return "arrow.uturn.backward"
        case .nextMonitor: return "arrow.right.to.line"
        case .prevMonitor: return "arrow.left.to.line"
        case .cycleLayout: return "square.grid.2x2"
        default: return nil
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

/// Groups of actions, in the order the Shortcuts settings show them.
enum HotKeyCategory: CaseIterable, Identifiable {
    case halves, quarters, thirds, twoThirds, fourths, sixths, special, navigation

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .halves: return "Halves"
        case .quarters: return "Quarters"
        case .thirds: return "Thirds"
        case .twoThirds: return "Two Thirds"
        case .fourths: return "Fourths"
        case .sixths: return "Sixths"
        case .special: return "Size and Position"
        case .navigation: return "Displays and Layouts"
        }
    }
}

/// Resolve binding: custom if set, otherwise default.
@MainActor
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
    case kVK_ANSI_KeypadDecimal:  return "Num."
    case kVK_ANSI_KeypadMultiply: return "Num*"
    case kVK_ANSI_KeypadPlus:     return "Num+"
    case kVK_ANSI_KeypadMinus:    return "Num-"
    case kVK_ANSI_KeypadDivide:   return "Num/"
    case kVK_ANSI_KeypadEquals:   return "Num="
    case kVK_ANSI_KeypadEnter:    return "⌤"
    case kVK_ANSI_KeypadClear:    return "⌧"
    case kVK_ANSI_LeftBracket:    return "["
    case kVK_ANSI_RightBracket:   return "]"
    case kVK_ANSI_Semicolon:      return ";"
    case kVK_ANSI_Quote:          return "'"
    case kVK_ANSI_Comma:          return ","
    case kVK_ANSI_Period:         return "."
    case kVK_ANSI_Slash:          return "/"
    case kVK_ANSI_Backslash:      return "\\"
    case kVK_ANSI_Grave:          return "`"
    case kVK_ForwardDelete:       return "⌦"
    case kVK_Home:                return "↖"
    case kVK_End:                 return "↘"
    case kVK_PageUp:              return "⇞"
    case kVK_PageDown:            return "⇟"
    case kVK_F1:  return "F1"
    case kVK_F2:  return "F2"
    case kVK_F3:  return "F3"
    case kVK_F4:  return "F4"
    case kVK_F5:  return "F5"
    case kVK_F6:  return "F6"
    case kVK_F7:  return "F7"
    case kVK_F8:  return "F8"
    case kVK_F9:  return "F9"
    case kVK_F10: return "F10"
    case kVK_F11: return "F11"
    case kVK_F12: return "F12"
    case kVK_F13: return "F13"
    case kVK_F14: return "F14"
    case kVK_F15: return "F15"
    case kVK_F16: return "F16"
    case kVK_F17: return "F17"
    case kVK_F18: return "F18"
    case kVK_F19: return "F19"
    case kVK_F20: return "F20"
    default:
        if keyCode == UInt32.max { return "—" }
        return "Key\(keyCode)"
    }
}
