import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    private let dragDetector = DragDetector()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

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
        guard let screen = NSScreen.main,
              let spaceUUID = SpaceDetector.shared.currentSpaceUUID(for: screen),
              let _ = LayoutStore.shared.spaceLayouts[spaceUUID],
              let layout = LayoutStore.shared.activeLayout(for: screen) else { return }

        let space = SpaceDetector.shared.currentSpace(for: screen)
        let spaceLabel = space.map { "Space \($0.index)" } ?? "Space"
        LayoutNotification.show(text: "\(spaceLabel): \(layout.name)")
    }

    private func onAccessibilityReady() {
        HotKeyManager.shared.registerDefaults()
        HotKeyManager.shared.registerZoneHotKeys()
        AppRuleMonitor.shared.start()

        // Restore windows to their last recorded zones (delayed to let apps finish launching)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            WindowPersistence.restoreAll()
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
