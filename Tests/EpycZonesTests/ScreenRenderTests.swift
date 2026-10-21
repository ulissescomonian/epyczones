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

    func testRenderLayouts() async throws {
        let directory = try XCTUnwrap(outputDirectory)
        let displays = DisplayInfo.connected()
        let main = try XCTUnwrap(displays.first(where: \.isPrimary))
        let portrait = displays.first(where: \.isPortrait) ?? main
        let size = CGSize(width: 1080, height: 760)

        func render(_ name: String, dark: Bool, display: DisplayInfo, session: LayoutEditSession? = nil) async throws {
            let view = LayoutsView(displays: displays, selectedDisplayID: display.id, session: session)
                .environment(Samples.layoutStore())
            try await ScreenRenderer.render(
                view,
                size: size,
                dark: dark,
                to: directory.appendingPathComponent("layouts-\(name)-\(dark ? "dark" : "light").png")
            )
        }

        for dark in [false, true] {
            try await render("browse-main", dark: dark, display: main)
            let grid = LayoutEditSession(editing: Samples.grid, display: main, applyOnSave: nil)
            grid.selection = Samples.grid.zones[1].id
            try await render("editor-main", dark: dark, display: main, session: grid)
        }
        try await render("browse-portrait", dark: false, display: portrait)

        let rows = LayoutEditSession(editing: Samples.rows, display: portrait, applyOnSave: nil)
        rows.setName("Chat", of: Samples.rows.zones[1].id)
        try await render("editor-portrait", dark: false, display: portrait, session: rows)

        let template = LayoutEditSession(
            editing: Layout.template(.mainAndStack),
            copyName: "Main and Stack Copy",
            display: main,
            applyOnSave: .display(main.id)
        )
        if let first = template.zones.first?.id {
            template.perform { $0[0].rect.width = 0.5 }
            template.selection = first
        }
        template.addZone()
        try await render("editor-issues", dark: false, display: main, session: template)
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
        // No fade-in: a capture during it comes out washed out.
        window.animationBehavior = .none
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.toolbarStyle = .unified
        window.contentViewController = hosting
        window.setContentSize(size)
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) - 1)
        let main = NSScreen.screens.first?.visibleFrame ?? .zero
        window.setFrameOrigin(NSPoint(x: main.minX + 40, y: main.maxY - window.frame.height - 40))
        window.orderFrontRegardless()
        defer { window.close() }

        // Let SwiftUI lay out, resolve the toolbar and finish first-frame
        // animations; capture again while the window still looks unsettled.
        var image: CGImage?
        for attempt in 0..<5 {
            try await Task.sleep(for: .milliseconds(attempt == 0 ? 1000 : 700))
            guard let captured = try? await capture(window) else { continue }
            image = captured
            if hasContrast(captured) { break }
        }
        guard let image else { throw RenderError.capture }
        guard let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            throw RenderError.encoding
        }
        try png.write(to: url)
    }

    private static func capture(_ window: NSWindow) async throws -> CGImage {
        let shareable = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let captured = shareable.windows.first(where: { $0.windowID == CGWindowID(window.windowNumber) }) else {
            throw RenderError.capture
        }
        let configuration = SCStreamConfiguration()
        configuration.width = Int(window.frame.width * window.backingScaleFactor)
        configuration.height = Int(window.frame.height * window.backingScaleFactor)
        configuration.showsCursor = false
        configuration.ignoreShadowsSingleWindow = true
        return try await SCScreenshotManager.captureImage(
            contentFilter: SCContentFilter(desktopIndependentWindow: captured),
            configuration: configuration
        )
    }

    /// False for a blank or faded capture: every real screen has text, so
    /// some pixels are far darker or lighter than others.
    private static func hasContrast(_ image: CGImage) -> Bool {
        let rep = NSBitmapImageRep(cgImage: image)
        var lowest = 1.0
        var highest = 0.0
        let step = max(1, min(rep.pixelsWide, rep.pixelsHigh) / 120)
        for y in stride(from: 0, to: rep.pixelsHigh, by: step) {
            for x in stride(from: 0, to: rep.pixelsWide, by: step) {
                guard let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                let luminance = 0.2126 * color.redComponent + 0.7152 * color.greenComponent + 0.0722 * color.blueComponent
                lowest = min(lowest, luminance)
                highest = max(highest, luminance)
            }
        }
        return highest - lowest > 0.6
    }

    enum RenderError: Error { case capture, encoding }
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
    static let rows = Layout(name: "2 Rows", zones: Layout.template(.twoRows).zones.map { Zone(rect: $0.rect) })
    static let coding = Layout(name: "Coding", zones: [
        Zone(rect: RelativeRect(x: 0, y: 0, width: 0.625, height: 1), name: "Editor"),
        Zone(rect: RelativeRect(x: 0.625, y: 0, width: 0.375, height: 0.5), name: "Browser"),
        Zone(rect: RelativeRect(x: 0.625, y: 0.5, width: 0.375, height: 0.5), name: "Terminal"),
    ])

    /// The real displays, the main one on Grid 2×2 and the others on 2 Rows,
    /// plus a display that is not connected.
    static func layoutStore() -> LayoutStore {
        var displays: [String: UUID] = ["sample-disconnected": coding.id]
        for (index, screen) in NSScreen.screens.enumerated() {
            if let uuid = screen.displayUUID() {
                displays[uuid] = index == 0 ? grid.id : rows.id
            }
        }
        return .inMemory(
            layouts: [grid, rows, coding],
            defaultLayoutID: grid.id,
            displayLayouts: displays,
            displayNames: ["sample-disconnected": "ARZOPA (1)"]
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
