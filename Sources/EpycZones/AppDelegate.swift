import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    private let dragDetector = DragDetector()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // Bound every AX request before anything talks to other apps
        AccessibilityChecker.configureMessagingTimeout()

        // Load window persistence data
        WindowPersistence.load()

        // Drag detection works without accessibility (uses NSEvent monitors)
        dragDetector.start()

        // Listen for Space changes to update active layout
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil, queue: .main
        ) { _ in
            self.onSpaceChanged()
        }

        // A display that connects may still carry a 1.0.x name-keyed layout assignment.
        LayoutStore.shared.migrateLegacyAssignments()
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { _ in
            LayoutStore.shared.migrateLegacyAssignments()
        }

        // Hotkeys + window snapping require accessibility
        if AccessibilityChecker.isGranted {
            onAccessibilityReady()
        } else {
            AccessibilityChecker.requestAccess()
            pollAccessibility()
        }
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        PrimaryWindowCoordinator.shared.handleReopen()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        PrimaryWindowCoordinator.shared.restoreMostRecentWindowIfNeededAfterActivation()
    }

    private func onSpaceChanged() {
        // Show notification if the layout changed due to per-space assignment
        guard !LayoutStore.shared.spaceLayouts.isEmpty,
              let screen = NSScreen.main,
              let spaceUUID = SpaceDetector.shared.currentSpaceUUID(for: screen),
              let _ = LayoutStore.shared.spaceLayouts[spaceUUID],
              let layout = LayoutStore.shared.activeLayout(for: screen) else { return }

        let space = SpaceDetector.shared.currentSpace(for: screen)
        let spaceLabel = space.map { "Space \($0.index)" } ?? "Space"
        LayoutNotification.show(text: "\(spaceLabel): \(layout.name)", on: screen)
    }

    private func onAccessibilityReady() {
        HotKeyManager.shared.registerDefaults()
        HotKeyManager.shared.registerZoneHotKeys()
        AppRuleMonitor.shared.start()

        // Restore windows to their last recorded zones (delayed to let apps finish launching)
        if AppSettings.shared.restoreWindowsOnLaunch {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                WindowPersistence.restoreAll()
            }
        }
    }

    private func pollAccessibility() {
        Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] timer in
            if AccessibilityChecker.isGranted {
                timer.invalidate()
                self?.onAccessibilityReady()
            }
        }
    }
}
