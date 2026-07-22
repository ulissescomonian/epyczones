import Carbon
import Foundation

// Carbon hotkey callback — must be a non-capturing function usable as a C function pointer.
private func carbonHotKeyCallback(
    _: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event = event, let userData = userData else {
        return OSStatus(eventNotHandledErr)
    }

    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        UInt32(kEventParamDirectObject),
        UInt32(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr else { return status }

    let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
    manager.handleHotKey(id: hotKeyID.id)
    return noErr
}

final class HotKeyManager {
    static let shared = HotKeyManager()

    private var handlers: [UInt32: () -> Void] = [:]
    private var hotKeyRefs: [EventHotKeyRef] = []
    private var nextID: UInt32 = 1
    private var eventHandlerRef: EventHandlerRef?

    // FourCharCode signature: "EPZN"
    private let signature: OSType = {
        let chars: [UInt8] = [0x45, 0x50, 0x5A, 0x4E]  // E P Z N
        return OSType(chars[0]) << 24 | OSType(chars[1]) << 16 | OSType(chars[2]) << 8 | OSType(chars[3])
    }()

    private init() {
        installCarbonHandler()
    }

    // MARK: - Setup

    private func installCarbonHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let selfPtr = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        InstallEventHandler(
            GetApplicationEventTarget(),
            carbonHotKeyCallback,
            1,
            &eventType,
            selfPtr,
            &eventHandlerRef
        )
    }

    /// Register all hotkeys using resolved (custom or default) bindings.
    func registerDefaults() {
        for action in HotKeyAction.allCases {
            let b = resolvedBinding(for: action)
            guard !b.isNone else { continue }

            if let position = action.snapPosition {
                register(keyCode: b.keyCode, modifiers: b.modifiers, position: position)
            } else {
                // Navigation actions
                switch action {
                case .nextMonitor:
                    register(keyCode: b.keyCode, modifiers: b.modifiers) { WindowManager.moveToNextScreen() }
                case .prevMonitor:
                    register(keyCode: b.keyCode, modifiers: b.modifiers) { WindowManager.moveToPreviousScreen() }
                case .cycleLayout:
                    register(keyCode: b.keyCode, modifiers: b.modifiers) {
                        LayoutStore.shared.cycleLayout()
                        LayoutNotification.show()
                    }
                default: break
                }
            }
        }
    }

    /// Temporarily unregister all hotkeys (e.g. during shortcut recording).
    func unregisterAll() {
        for ref in hotKeyRefs {
            UnregisterEventHotKey(ref)
        }
        hotKeyRefs.removeAll()
        handlers.removeAll()
        nextID = 1
    }

    /// Unregister all hotkeys and re-register with current settings.
    func reloadHotKeys() {
        unregisterAll()
        registerDefaults()
        registerZoneHotKeys()
    }

    /// Register hotkeys for zone indices 1-9 (Ctrl+Option+1 through Ctrl+Option+9).
    func registerZoneHotKeys() {
        let mods = UInt32(controlKey | optionKey)
        let numberKeyCodes: [UInt32] = [
            UInt32(kVK_ANSI_1), UInt32(kVK_ANSI_2), UInt32(kVK_ANSI_3),
            UInt32(kVK_ANSI_4), UInt32(kVK_ANSI_5), UInt32(kVK_ANSI_6),
            UInt32(kVK_ANSI_7), UInt32(kVK_ANSI_8), UInt32(kVK_ANSI_9),
        ]

        for (index, keyCode) in numberKeyCodes.enumerated() {
            let zoneIndex = index
            register(keyCode: keyCode, modifiers: mods) {
                WindowManager.snapToActiveZone(index: zoneIndex)
            }
        }
    }

    // MARK: - Registration

    private func register(keyCode: UInt32, modifiers: UInt32, position: SnapPosition) {
        register(keyCode: keyCode, modifiers: modifiers) {
            WindowManager.snap(to: position)
        }
    }

    private func register(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        let id = nextID
        nextID += 1
        handlers[id] = action

        let hotKeyID = EventHotKeyID(signature: signature, id: id)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)

        if status == noErr, let ref = ref {
            hotKeyRefs.append(ref)
            NSLog("[EpycZones] Registered hotkey id=%d keyCode=%d mods=%d", id, keyCode, modifiers)
        } else {
            NSLog("[EpycZones] FAILED to register hotkey: keyCode=%d, mods=%d, status=%d", keyCode, modifiers, status)
        }
    }

    // MARK: - Callback

    func handleHotKey(id: UInt32) {
        NSLog("[EpycZones] HotKey FIRED id=%d", id)
        handlers[id]?()
    }

    deinit {
        for ref in hotKeyRefs {
            UnregisterEventHotKey(ref)
        }
        if let handler = eventHandlerRef {
            RemoveEventHandler(handler)
        }
    }
}
