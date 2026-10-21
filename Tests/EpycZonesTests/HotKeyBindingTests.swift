import Carbon
import XCTest
@testable import EpycZones

final class HotKeyBindingTests: XCTestCase {
    private let controlOption = UInt32(controlKey | optionKey)

    private func binding(_ keyCode: Int, _ modifiers: Int) -> HotKeyBinding {
        HotKeyBinding(keyCode: UInt32(keyCode), modifiers: UInt32(modifiers))
    }

    func testBindingsWithoutControlOptionOrCommandAreRejected() {
        XCTAssertEqual(binding(kVK_ANSI_A, 0).validate(for: .leftHalf, customBindings: [:]), .needsModifier)
        // Shift alone would capture every capital A typed anywhere.
        XCTAssertEqual(binding(kVK_ANSI_A, shiftKey).validate(for: .leftHalf, customBindings: [:]), .needsModifier)
    }

    func testCommandAloneIsAccepted() {
        XCTAssertEqual(binding(kVK_ANSI_X, cmdKey | shiftKey).validate(for: .leftHalf, customBindings: [:]), .valid)
    }

    func testZoneShortcutsAreReserved() {
        let zoneThree = binding(kVK_ANSI_3, controlKey | optionKey)
        XCTAssertEqual(zoneThree.validate(for: .leftHalf, customBindings: [:]), .conflict("Zone 3"))
    }

    func testAnotherActionsDefaultConflicts() {
        // ⌃⌥D is First Third by default.
        let controlOptionD = binding(kVK_ANSI_D, controlKey | optionKey)
        XCTAssertEqual(controlOptionD.validate(for: .leftHalf, customBindings: [:]), .conflict("First Third"))
    }

    func testRebindingFreesTheOldShortcut() {
        let controlOptionD = binding(kVK_ANSI_D, controlKey | optionKey)
        let custom = [HotKeyAction.firstThird.rawValue: binding(kVK_ANSI_X, controlKey | optionKey)]
        XCTAssertEqual(controlOptionD.validate(for: .leftHalf, customBindings: custom), .valid)
    }

    func testAClearedActionNoLongerConflicts() {
        let controlOptionD = binding(kVK_ANSI_D, controlKey | optionKey)
        let custom = [HotKeyAction.firstThird.rawValue: HotKeyBinding.none]
        XCTAssertEqual(controlOptionD.validate(for: .leftHalf, customBindings: custom), .valid)
    }

    func testKeepingTheSameShortcutIsValid() {
        let leftHalfDefault = HotKeyAction.leftHalf.defaultBinding
        XCTAssertEqual(leftHalfDefault.validate(for: .leftHalf, customBindings: [:]), .valid)
    }

    func testDefaultBindingsDoNotConflictWithEachOther() {
        for action in HotKeyAction.allCases where !action.defaultBinding.isNone {
            XCTAssertEqual(
                action.defaultBinding.validate(for: action, customBindings: [:]),
                .valid,
                "\(action) default collides with another shortcut"
            )
        }
    }

    func testZoneShortcutsAreTheDigitsWithTheChosenModifiers() {
        let zones = HotKeyBinding.zoneBindings(modifiers: controlOption)
        XCTAssertEqual(zones.count, 9)
        XCTAssertTrue(zones.allSatisfy { $0.modifiers == controlOption })
        XCTAssertEqual(zones.first?.keyCode, UInt32(kVK_ANSI_1))
        XCTAssertEqual(zones.last?.keyCode, UInt32(kVK_ANSI_9))
    }

    func testZoneModifiersDecideWhichShortcutsAreReserved() {
        let controlCommand = ZoneShortcutModifiers.controlCommand.rawValue
        let controlOption3 = binding(kVK_ANSI_3, controlKey | optionKey)
        let controlCommand3 = binding(kVK_ANSI_3, controlKey | cmdKey)
        XCTAssertEqual(controlOption3.validate(for: .leftHalf, customBindings: [:], zoneModifiers: controlCommand), .valid)
        XCTAssertEqual(
            controlCommand3.validate(for: .leftHalf, customBindings: [:], zoneModifiers: controlCommand),
            .conflict("Zone 3")
        )
    }

    func testEveryZoneModifierChoiceNeedsControlOrCommand() {
        for choice in ZoneShortcutModifiers.allCases {
            XCTAssertNotEqual(choice.rawValue & UInt32(controlKey | cmdKey), 0, "\(choice)")
        }
        XCTAssertEqual(ZoneShortcutModifiers.controlOption.symbols, "⌃⌥")
        XCTAssertEqual(ZoneShortcutModifiers.controlOptionCommand.symbols, "⌃⌥⌘")
    }

    func testFunctionAndPunctuationKeysHaveNames() {
        XCTAssertEqual(keyCodeName(UInt32(kVK_F5)), "F5")
        XCTAssertEqual(keyCodeName(UInt32(kVK_ANSI_LeftBracket)), "[")
        XCTAssertEqual(binding(kVK_ANSI_4, controlKey | optionKey).modifierSymbols, "⌃⌥")
    }
}
