import AppKit
import ApplicationServices

/// Watches apps that have rules and auto-snaps their new windows.
/// Uses one AXObserver per ruled app (kAXWindowCreatedNotification).
final class AppRuleMonitor {
    static let shared = AppRuleMonitor()

    private var observers: [pid_t: AXObserver] = [:]
    private var started = false

    private init() {}

    func start() {
        guard !started, AccessibilityChecker.isGranted else { return }
        started = true

        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.observeIfRuled(app)
        }
        nc.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.removeObserver(pid: app.processIdentifier)
        }
        reload()
    }

    /// Sync observers with the current rule list. Called on start and when rules change.
    func reload() {
        guard started else { return }
        let ruledIDs = Set(AppRuleStore.shared.rules.map(\.bundleID))

        for pid in Array(observers.keys) {
            let bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
            if bundleID == nil || !ruledIDs.contains(bundleID!) {
                removeObserver(pid: pid)
            }
        }
        for app in NSWorkspace.shared.runningApplications {
            observeIfRuled(app)
        }
    }

    // MARK: - Observers

    private func observeIfRuled(_ app: NSRunningApplication) {
        guard let bundleID = app.bundleIdentifier,
              AppRuleStore.shared.rule(for: bundleID) != nil else { return }
        addObserver(for: app)
    }

    private func addObserver(for app: NSRunningApplication) {
        let pid = app.processIdentifier
        guard pid > 0, observers[pid] == nil else { return }

        let callback: AXObserverCallback = { _, element, _, refcon in
            guard let refcon = refcon else { return }
            let monitor = Unmanaged<AppRuleMonitor>.fromOpaque(refcon).takeUnretainedValue()
            monitor.handleNewWindow(element)
        }

        var observer: AXObserver?
        guard AXObserverCreate(pid, callback, &observer) == .success, let obs = observer else { return }

        let appElement = AXUIElementCreateApplication(pid)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard AXObserverAddNotification(obs, appElement, kAXWindowCreatedNotification as CFString, refcon) == .success else { return }

        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)
        observers[pid] = obs
    }

    private func removeObserver(pid: pid_t) {
        guard let obs = observers.removeValue(forKey: pid) else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)
    }

    // MARK: - Window Handling

    private func handleNewWindow(_ window: AXUIElement) {
        var pid: pid_t = 0
        AXUIElementGetPid(window, &pid)
        guard let app = NSRunningApplication(processIdentifier: pid),
              let bundleID = app.bundleIdentifier,
              let rule = AppRuleStore.shared.rule(for: bundleID) else { return }

        // Standard windows only — skip dialogs, sheets, palettes.
        var subrole: AnyObject?
        AXUIElementCopyAttributeValue(window, kAXSubroleAttribute as CFString, &subrole)
        guard (subrole as? String) == kAXStandardWindowSubrole else { return }

        // Let the app finish its own initial sizing before snapping.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.apply(rule, to: window)
        }
    }

    private func apply(_ rule: AppRule, to window: AXUIElement) {
        guard let screen = WindowManager.screenForWindow(window) ?? NSScreen.main else { return }

        let targetNS: CGRect
        switch rule.target {
        case .position(let position):
            targetNS = position.frame(in: screen.visibleFrame)
        case .zone(let index):
            guard let layout = LayoutStore.shared.activeLayout(for: screen),
                  index < layout.zones.count else { return }
            targetNS = layout.zones[index].rect.frame(in: screen.visibleFrame, gap: AppSettings.shared.zoneGap)
        }
        WindowManager.applySnap(targetNS, to: window, animated: false)
    }
}
