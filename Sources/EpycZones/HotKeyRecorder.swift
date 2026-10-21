import AppKit
import Carbon
import Observation

/// Records one shortcut at a time for the Hotkeys settings.
///
/// Global hotkeys are unregistered while recording so they cannot intercept
/// the key press. Every way out of a recording (a valid shortcut, ⎋, clicking
/// the button again, leaving the tab, closing the window or switching apps)
/// therefore has to end in `stop()`, which registers them again.
@Observable
@MainActor
final class HotKeyRecorder {
    /// The action being recorded, or nil when idle.
    private(set) var action: HotKeyAction?
    /// Guidance for the row being recorded, or why the last keys were rejected.
    private(set) var message: String?
    private(set) var messageIsError = false

    @ObservationIgnored private var keyMonitor: Any?
    @ObservationIgnored private var resignObserver: NSObjectProtocol?

    private static let hint = "Type the new shortcut. ⎋ cancels, ⌫ removes it."

    deinit {
        // Owned by SwiftUI view state, which is released on the main thread.
        MainActor.assumeIsolated {
            guard action != nil else { return }
            removeMonitors()
            HotKeyManager.shared.reloadHotKeys()
        }
    }

    func start(_ newAction: HotKeyAction) {
        if action == nil {
            HotKeyManager.shared.unregisterAll()
            installMonitors()
        }
        action = newAction
        message = Self.hint
        messageIsError = false
    }

    func stop() {
        guard action != nil else { return }
        action = nil
        message = nil
        messageIsError = false
        removeMonitors()
        HotKeyManager.shared.reloadHotKeys()
    }

    // MARK: - Events

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard let action else { return event }
        guard !event.isARepeat else { return nil }

        let modifiers = Self.carbonModifiers(from: event.modifierFlags)
        let keyCode = Int(event.keyCode)

        if modifiers == 0 && keyCode == kVK_Escape {
            stop()
            return nil
        }
        if modifiers == 0 && (keyCode == kVK_Delete || keyCode == kVK_ForwardDelete) {
            // Spelled out: `.none` would mean Optional.none and reset to the default.
            AppSettings.shared.customHotKeys[action.rawValue] = HotKeyBinding.none
            stop()
            return nil
        }

        let binding = HotKeyBinding(keyCode: UInt32(keyCode), modifiers: modifiers)
        switch binding.validate(for: action, customBindings: AppSettings.shared.customHotKeys) {
        case .valid:
            AppSettings.shared.customHotKeys[action.rawValue] = binding
            stop()
        case .needsModifier:
            reject("\(binding.displayString) needs ⌃, ⌥ or ⌘.")
        case .conflict(let owner):
            reject("\(binding.displayString) is already used by \(owner).")
        }
        return nil
    }

    private func reject(_ text: String) {
        message = text
        messageIsError = true
    }

    private static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var modifiers: UInt32 = 0
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        return modifiers
    }

    // MARK: - Monitors

    private func installMonitors() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // `handle` returns nil to consume the event; keep that nil.
            guard let self else { return event }
            return self.handle(event)
        }
        // Local monitors see nothing while another app is active, so hotkeys
        // would stay unregistered until the user came back.
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.stop() }
        }
    }

    private func removeMonitors() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        if let resignObserver {
            NotificationCenter.default.removeObserver(resignObserver)
            self.resignObserver = nil
        }
    }
}
