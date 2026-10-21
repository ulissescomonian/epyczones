import AppKit
import Carbon

/// The key held during a drag to show the layout's zones.
enum ZoneDragModifier: String, CaseIterable, Identifiable {
    case shift, option, control, command

    var id: String { rawValue }

    var flag: NSEvent.ModifierFlags {
        switch self {
        case .shift: return .shift
        case .option: return .option
        case .control: return .control
        case .command: return .command
        }
    }

    var symbol: String {
        switch self {
        case .shift: return "⇧"
        case .option: return "⌥"
        case .control: return "⌃"
        case .command: return "⌘"
        }
    }

    var name: String {
        switch self {
        case .shift: return String(localized: "Shift")
        case .option: return String(localized: "Option")
        case .control: return String(localized: "Control")
        case .command: return String(localized: "Command")
        }
    }
}

/// Modifier sets offered for the fixed zone shortcuts, as Carbon flags.
/// Each includes Control or Command, so plain typing is never captured.
enum ZoneShortcutModifiers: UInt32, CaseIterable, Identifiable {
    case controlOption = 0x1800       // controlKey | optionKey
    case controlCommand = 0x1100      // controlKey | cmdKey
    case optionCommand = 0x0900       // optionKey | cmdKey
    case controlShift = 0x1200        // controlKey | shiftKey
    case controlOptionCommand = 0x1900

    var id: UInt32 { rawValue }

    static let `default` = ZoneShortcutModifiers.controlOption

    /// The modifiers as glyphs, in Apple's order: ⌃⌥⇧⌘.
    var symbols: String {
        HotKeyBinding(keyCode: UInt32(kVK_ANSI_1), modifiers: rawValue).modifierSymbols
    }
}
