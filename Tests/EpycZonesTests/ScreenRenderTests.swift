import AppKit
import ScreenCaptureKit
import SwiftUI
import XCTest
@testable import EpycZones

/// Renders app screens to PNG for design review, in light and dark mode at
/// 2x. Runs only when EPYCZONES_SCREENS names an output folder; see
/// `make screens`. Uses in-memory sample data, never the user's files.
@MainActor
final class ScreenRenderTests: XCTestCase {
    private var outputDirectory: URL?

    override func setUp() async throws {
        guard let path = ProcessInfo.processInfo.environment["EPYCZONES_SCREENS"], !path.isEmpty else {
            throw XCTSkip("Set EPYCZONES_SCREENS to render screens.")
        }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        outputDirectory = directory
        _ = NSApplication.shared
        // Accessory: may own windows, never shows in the Dock or takes focus.
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    func testRenderSettingsPanes() async throws {
        let directory = try XCTUnwrap(outputDirectory)
        let layouts = Samples.layoutStore()
        let rules = Samples.ruleStore()
        let workspaces = Samples.workspaceStore()

        for pane in SettingsPane.allCases {
            let height: CGFloat = pane == .shortcuts ? 1500 : 760
            for dark in [false, true] {
                let view = SettingsView(initialPane: pane)
                    .environment(layouts)
                    .environment(rules)
                    .environment(workspaces)
                try await ScreenRenderer.render(
                    view,
                    size: CGSize(width: 860, height: height),
                    dark: dark,
                    to: directory.appendingPathComponent("settings-\(pane.rawValue)-\(dark ? "dark" : "light").png")
                )
            }
        }
    }

    func testRenderAppRuleEditor() async throws {
        let directory = try XCTUnwrap(outputDirectory)
        var draft = AppRuleDraft()
        draft.bundleID = "com.apple.Safari"
        draft.appName = "Safari"
        for dark in [false, true] {
            let view = AppRuleEditor(draft: draft)
                .environment(Samples.layoutStore())
                .environment(Samples.ruleStore())
            try await ScreenRenderer.render(
                view,
                size: CGSize(width: 580, height: 620),
                dark: dark,
                to: directory.appendingPathComponent("app-rule-editor-\(dark ? "dark" : "light").png")
            )
        }
    }
}

// MARK: - Renderer

@MainActor
enum ScreenRenderer {
    /// Draws `content` in a real window and captures it as the window server
    /// composites it, so sidebars, materials and the toolbar render as in the
    /// app. The window sits below the desktop picture: it is composited but
    /// never visible, and the app is never activated. Needs the Screen
    /// Recording permission of the terminal running the tests.
    static func render<Content: View>(_ content: Content, size: CGSize, dark: Bool, to url: URL) async throws {
        let hosting = NSHostingController(rootView: content)
        hosting.sceneBridgingOptions = [.toolbars, .title]

        let window = RenderWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.toolbarStyle = .unified
        window.contentViewController = hosting
        window.setContentSize(size)
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) - 1)
        let main = NSScreen.screens.first?.visibleFrame ?? .zero
        window.setFrameOrigin(NSPoint(x: main.minX + 40, y: main.maxY - window.frame.height - 40))
        window.orderFrontRegardless()
        defer { window.close() }

        // Let SwiftUI lay out, resolve the toolbar and finish first-frame animations.
        try await Task.sleep(for: .milliseconds(900))

        let shareable = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let captured = shareable.windows.first(where: { $0.windowID == CGWindowID(window.windowNumber) }) else {
            throw RenderError.windowNotFound
        }
        let configuration = SCStreamConfiguration()
        configuration.width = Int(window.frame.width * window.backingScaleFactor)
        configuration.height = Int(window.frame.height * window.backingScaleFactor)
        configuration.showsCursor = false
        configuration.ignoreShadowsSingleWindow = true
        let image = try await SCScreenshotManager.captureImage(
            contentFilter: SCContentFilter(desktopIndependentWindow: captured),
            configuration: configuration
        )
        guard let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            throw RenderError.encoding
        }
        try png.write(to: url)
    }

    enum RenderError: Error { case windowNotFound, encoding }
}

/// A window that reports itself as key and accepts any frame.
private final class RenderWindow: NSWindow {
    override var isKeyWindow: Bool { true }
    override var isMainWindow: Bool { true }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

// MARK: - Sample Data

@MainActor
enum Samples {
    static let grid = Layout(name: "Grid 2×2", zones: [
        Zone(rect: RelativeRect(x: 0, y: 0, width: 0.5, height: 0.625)),
        Zone(rect: RelativeRect(x: 0.5, y: 0, width: 0.5, height: 0.625)),
        Zone(rect: RelativeRect(x: 0, y: 0.625, width: 0.5, height: 0.375)),
        Zone(rect: RelativeRect(x: 0.5, y: 0.625, width: 0.5, height: 0.375)),
    ])
    static let rows = Layout.twoRows()
    static let columns = Layout.threeColumns()
    static let focus = Layout.focusCenter()

    /// The real displays, the first one on Grid 2×2 and the others on 2 Rows.
    static func layoutStore() -> LayoutStore {
        var displays: [String: UUID] = [:]
        for (index, screen) in NSScreen.screens.enumerated() {
            if let uuid = screen.displayUUID() {
                displays[uuid] = index == 0 ? grid.id : rows.id
            }
        }
        return .inMemory(
            layouts: [grid, rows, columns, focus],
            defaultLayoutID: grid.id,
            displayLayouts: displays
        )
    }

    static func ruleStore() -> AppRuleStore {
        .inMemory(rules: [
            AppRule(bundleID: "com.apple.Safari", appName: "Safari", target: .position(.leftHalf)),
            AppRule(bundleID: "com.apple.Terminal", appName: "Terminal", target: .zone(1)),
            AppRule(bundleID: "com.apple.Notes", appName: "Notes", target: .position(.lastThird)),
        ])
    }

    static func workspaceStore() -> WorkspaceStore {
        func entry(_ bundleID: String, _ title: String) -> WorkspaceManager.Workspace.Entry {
            .init(bundleID: bundleID, windowTitle: title, screenName: "LG HDR 4K", displayUUID: nil, relativeFrame: .full)
        }
        return .inMemory([
            WorkspaceStore.Workspace(name: "Development", entries: [
                entry("com.apple.dt.Xcode", "EpycZones"),
                entry("com.apple.Terminal", "zsh"),
                entry("com.apple.Safari", "Docs"),
                entry("com.apple.Safari", "Pull request"),
            ]),
            WorkspaceStore.Workspace(name: "Writing", entries: [
                entry("com.apple.Notes", "Draft"),
                entry("com.apple.Safari", "Research"),
            ]),
        ])
    }
}
