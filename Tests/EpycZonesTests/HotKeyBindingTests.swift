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

    func testZoneShortcutsAreControlOptionDigits() {
        XCTAssertEqual(HotKeyBinding.zoneBindings.count, 9)
        XCTAssertTrue(HotKeyBinding.zoneBindings.allSatisfy { $0.modifiers == controlOption })
        XCTAssertEqual(HotKeyBinding.zoneBindings.first?.keyCode, UInt32(kVK_ANSI_1))
        XCTAssertEqual(HotKeyBinding.zoneBindings.last?.keyCode, UInt32(kVK_ANSI_9))
    }
}
