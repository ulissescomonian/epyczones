import AppKit
import Carbon
import OSLog

// Carbon hotkey callback — must be a non-capturing function usable as a C function pointer.
// The handler is installed once, by the HotKeyManager singleton, so it
// dispatches to `HotKeyManager.shared` instead of decoding its user data.
private func carbonHotKeyCallback(
    _: EventHandlerCallRef?,
    _ event: EventRef?,
    _: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event = event else {
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

    // Carbon delivers hotkeys through the application event target, which
    // dispatches on the main thread.
    let id = hotKeyID.id
    MainActor.assumeIsolated {
        HotKeyManager.shared.handleHotKey(id: id)
    }
    return noErr
}

@MainActor
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

        InstallEventHandler(
            GetApplicationEventTarget(),
            carbonHotKeyCallback,
            1,
            &eventType,
            nil,
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
                        // Cycle the display under the cursor and announce it there.
                        let mouseLocation = NSEvent.mouseLocation
                        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) })
                                ?? NSScreen.main,
                              let layout = LayoutStore.shared.cycleLayout(on: screen) else { return }
                        LayoutNotification.show(layout: layout, on: screen)
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

    /// Register hotkeys for zone indices 1-9 with the configured modifiers (⌃⌥ by default).
    func registerZoneHotKeys() {
        let modifiers = AppSettings.shared.zoneHotKeyModifiers.rawValue
        for (index, binding) in HotKeyBinding.zoneBindings(modifiers: modifiers).enumerated() {
            let zoneIndex = index
            register(keyCode: binding.keyCode, modifiers: binding.modifiers) {
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
            Log.hotKeys.debug("Registered hotkey id=\(id) keyCode=\(keyCode) mods=\(modifiers)")
        } else {
            Log.hotKeys.error("Failed to register hotkey keyCode=\(keyCode) mods=\(modifiers) status=\(status)")
        }
    }

    // MARK: - Callback

    func handleHotKey(id: UInt32) {
        handlers[id]?()
    }

    // No deinit: the shared instance lives as long as the app, and the system
    // releases its hotkeys and event handler when the process exits.
}
