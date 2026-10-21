import AppKit

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private let dragDetector = DragDetector()
    /// Follows the Accessibility permission, which changes in System Settings.
    private var accessibilityPoll: Timer?
    /// Hotkeys, rules and window restore start once, when the permission is there.
    private var startedAccessibilityFeatures = false

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
            MainActor.assumeIsolated { self.onSpaceChanged() }
        }

        // Remember display names, and migrate 1.0.x name-keyed assignments
        // of displays that connect.
        LayoutStore.shared.noteConnectedDisplays()
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { LayoutStore.shared.noteConnectedDisplays() }
        }

        // Hotkeys + window snapping require accessibility
        if AccessibilityChecker.isGranted {
            onAccessibilityReady()
        }
        pollAccessibility()
        showWelcomeIfNeeded()
    }

    /// The welcome window: both steps on a first run, and only the
    /// permission step when an installed copy lost Accessibility, as an
    /// update with a new signature makes it.
    private func showWelcomeIfNeeded() {
        let settings = AppSettings.shared
        // Asked of the store, which knows whether the file was there before
        // it saved the names of the connected displays.
        let isFirstRun = !settings.hasCompletedOnboarding && !LayoutStore.shared.hadSavedState
        if !isFirstRun {
            settings.hasCompletedOnboarding = true
        }
        if isFirstRun {
            WelcomeWindowController.shared.show(steps: [.accessibility, .layouts])
        } else if !AccessibilityChecker.isGranted {
            WelcomeWindowController.shared.show(steps: [.accessibility])
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
              LayoutStore.shared.spaceLayouts[spaceUUID] != nil else { return }

        let layout = LayoutStore.shared.layout(for: screen)
        let text = SpaceDetector.shared.currentSpace(for: screen).map {
            String(localized: "Desktop \($0.index): \(layout.name)")
        } ?? layout.name
        LayoutNotification.show(text: text, on: screen)
    }

    private func onAccessibilityReady() {
        guard !startedAccessibilityFeatures else { return }
        startedAccessibilityFeatures = true
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
        // Scheduled on the main run loop, so the block runs on the main thread.
        accessibilityPoll = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                AccessibilityStatus.shared.refresh()
                guard let self, AccessibilityStatus.shared.isGranted else { return }
                self.onAccessibilityReady()
            }
        }
    }
}
