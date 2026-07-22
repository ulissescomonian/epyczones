import AppKit
import SwiftUI

/// Owns the two user-facing windows so every route opens or focuses the same
/// native window and the Dock follows their actual lifecycle.
@MainActor
final class PrimaryWindowCoordinator {
    enum Kind: Hashable {
        case layoutEditor
        case settings

        var sceneID: String {
            switch self {
            case .layoutEditor:
                return "layout-editor"
            case .settings:
                return "settings"
            }
        }
    }

    static let shared = PrimaryWindowCoordinator()

    private var windows: [Kind: NSWindow] = [:]
    private var openingKinds = Set<Kind>()
    private var openingRequestTokens: [Kind: UUID] = [:]
    private let closingWindows = NSHashTable<NSWindow>.weakObjects()
    private var observerTokens: [Kind: [NSObjectProtocol]] = [:]
    private var focusOrder: [Kind] = []
    private var pendingRestorationKinds = Set<Kind>()

    private let openingRecoveryDelay: TimeInterval = 1

    private init() {}

    /// Opens a primary scene once, or restores and focuses its existing window.
    func openOrFocus(_ kind: Kind, using openWindow: OpenWindowAction) {
        applyDockPolicy()

        if let window = windows[kind], !isClosing(window) {
            focus(window, for: kind)
            return
        }

        if let closingWindow = windows[kind] {
            removeWindow(closingWindow, for: kind)
        }

        guard openingKinds.insert(kind).inserted else { return }
        let requestToken = UUID()
        openingRequestTokens[kind] = requestToken
        openWindow(id: kind.sceneID)
        scheduleOpeningRecovery(for: kind, requestToken: requestToken)
    }

    /// Called by the scene bridge after SwiftUI creates its backing NSWindow.
    func register(_ window: NSWindow, for kind: Kind) {
        let shouldFocus = openingKinds.contains(kind)

        guard !isClosing(window) else { return }

        if windows[kind] === window {
            return
        }

        if let existing = windows[kind], existing !== window {
            // A coalesced request should never produce two primary windows. If
            // SwiftUI hands us a duplicate, retain the established one.
            window.close()
            return
        }

        windows[kind] = window
        openingKinds.remove(kind)
        openingRequestTokens.removeValue(forKey: kind)
        installObservers(for: window, kind: kind)
        applyDockPolicy()
        if shouldFocus {
            focus(window, for: kind)
        }
    }

    /// Handles a Dock click while a primary window is minimized or behind
    /// another application. Returning true prevents AppKit from trying to
    /// create a new scene for a window that already exists.
    func handleReopen() -> Bool {
        guard let (kind, window) = mostRecentOpenWindow() else { return false }
        focus(window, for: kind)
        return true
    }

    /// Some Dock and Launch Services activation paths for a dynamically
    /// promoted menu-bar app do not invoke `applicationShouldHandleReopen`.
    /// Restore only when there is no visible primary window, so ordinary app
    /// activation never steals focus from a window the user is already using.
    func restoreMostRecentWindowIfNeededAfterActivation() {
        let trackedWindows = windows.values.filter { !isClosing($0) }
        guard !trackedWindows.isEmpty,
              trackedWindows.allSatisfy({ $0.isMiniaturized || !$0.isVisible }),
              let (kind, window) = mostRecentOpenWindow() else { return }

        focus(window, for: kind)
    }

    private func installObservers(for window: NSWindow, kind: Kind) {
        guard observerTokens[kind] == nil else { return }

        let center = NotificationCenter.default
        observerTokens[kind] = [
            center.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { [weak self, weak window] _ in
                guard let self, let window else { return }
                MainActor.assumeIsolated {
                    self.closingWindows.add(window)
                    self.removeWindow(window, for: kind)
                }
            },
            center.addObserver(
                forName: NSWindow.didMiniaturizeNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                guard let self else { return }
                MainActor.assumeIsolated {
                    self.applyDockPolicy()
                }
            },
            center.addObserver(
                forName: NSWindow.didDeminiaturizeNotification,
                object: window,
                queue: .main
            ) { [weak self, weak window] _ in
                guard let self, let window else { return }
                MainActor.assumeIsolated {
                    self.applyDockPolicy()
                    guard self.pendingRestorationKinds.remove(kind) != nil,
                          self.windows[kind] === window,
                          !self.isClosing(window) else { return }
                    self.bringToFront(window)
                }
            },
        ]
    }

    private func scheduleOpeningRecovery(for kind: Kind, requestToken: UUID) {
        DispatchQueue.main.asyncAfter(deadline: .now() + openingRecoveryDelay) { [weak self] in
            MainActor.assumeIsolated {
                guard let self,
                      self.openingRequestTokens[kind] == requestToken,
                      self.windows[kind] == nil else { return }

                // SwiftUI did not attach an NSWindow within the bounded
                // interval. Clear only the coalescing lock; a late, otherwise
                // valid window is still accepted by `register`.
                self.openingKinds.remove(kind)
                self.openingRequestTokens.removeValue(forKey: kind)
                self.applyDockPolicy()
            }
        }
    }

    private func removeWindow(_ window: NSWindow, for kind: Kind) {
        guard windows[kind] === window else { return }
        windows.removeValue(forKey: kind)
        pendingRestorationKinds.remove(kind)
        focusOrder.removeAll { $0 == kind }
        removeObservers(for: kind)
        applyDockPolicy()
    }

    private func isClosing(_ window: NSWindow) -> Bool {
        closingWindows.contains(window)
    }

    private func removeObservers(for kind: Kind) {
        guard let tokens = observerTokens.removeValue(forKey: kind) else { return }
        let center = NotificationCenter.default
        tokens.forEach(center.removeObserver)
    }

    private func applyDockPolicy() {
        let hasPrimaryWindow = !windows.isEmpty || !openingKinds.isEmpty
        NSApp.setActivationPolicy(hasPrimaryWindow ? .regular : .accessory)
    }

    private func mostRecentOpenWindow() -> (Kind, NSWindow)? {
        for kind in focusOrder.reversed() {
            if let window = windows[kind], !isClosing(window) {
                return (kind, window)
            }
        }

        for kind in [Kind.layoutEditor, .settings] {
            if let window = windows[kind], !isClosing(window) {
                return (kind, window)
            }
        }

        return nil
    }

    private func focus(_ window: NSWindow, for kind: Kind) {
        guard windows[kind] === window, !isClosing(window) else { return }
        focusOrder.removeAll { $0 == kind }
        focusOrder.append(kind)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        if window.isMiniaturized {
            pendingRestorationKinds.insert(kind)
            window.deminiaturize(nil)
            DispatchQueue.main.async { [weak self, weak window] in
                guard let self, let window else { return }
                MainActor.assumeIsolated {
                    guard self.windows[kind] === window,
                          !self.isClosing(window) else { return }
                    if window.isMiniaturized {
                        window.deminiaturize(nil)
                    } else {
                        self.pendingRestorationKinds.remove(kind)
                        self.bringToFront(window)
                    }
                }
            }
            return
        }

        bringToFront(window)
    }

    private func bringToFront(_ window: NSWindow) {
        guard !isClosing(window) else { return }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

/// Bridges a SwiftUI scene to its native NSWindow without putting lifecycle
/// policy in individual views.
struct PrimaryWindowBridge: NSViewRepresentable {
    let kind: PrimaryWindowCoordinator.Kind

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                PrimaryWindowCoordinator.shared.register(window, for: kind)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let window = nsView.window {
                PrimaryWindowCoordinator.shared.register(window, for: kind)
            }
        }
    }
}
