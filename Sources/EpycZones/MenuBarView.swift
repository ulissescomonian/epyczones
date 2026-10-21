import AppKit
import SwiftUI

/// The menu bar menu: a warning while Accessibility is off, one submenu per
/// display to choose its layout, and the app's windows.
struct MenuBarView: View {
    @Environment(LayoutStore.self) private var store
    @Environment(\.openWindow) private var openWindow
    @Environment(\.colorScheme) private var colorScheme
    private var accessibility = AccessibilityStatus.shared

    var body: some View {
        if !accessibility.isGranted {
            Button {
                AccessibilityChecker.openPrivacySettings()
            } label: {
                Label("Allow Accessibility…", systemImage: "exclamationmark.triangle.fill")
            }
            Text("Windows can’t snap until EpycZones is allowed.")
            Divider()
        }

        Section("Displays") {
            ForEach(DisplayInfo.connected()) { display in
                let current = store.resolution(forDisplay: display.id, name: display.name)
                Menu {
                    choices(for: display, current: current)
                } label: {
                    Label {
                        Text(verbatim: display.name)
                    } icon: {
                        Image(nsImage: thumbnail(current.layout, display: display))
                    }
                }
            }
        }

        Divider()

        Button("Layouts…") {
            AppNavigation.shared.layoutsDisplayID = nil
            PrimaryWindowCoordinator.shared.openOrFocus(.layoutEditor, using: openWindow)
        }
        .keyboardShortcut("l")

        Button("Settings…") {
            AppNavigation.shared.settingsPane = nil
            PrimaryWindowCoordinator.shared.openOrFocus(.settings, using: openWindow)
        }
        .keyboardShortcut(",")

        Divider()

        Button("About EpycZones") {
            AppNavigation.shared.settingsPane = .about
            PrimaryWindowCoordinator.shared.openOrFocus(.settings, using: openWindow)
        }

        Button("Quit EpycZones") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    @ViewBuilder
    private func choices(for display: DisplayInfo, current: LayoutStore.Resolution) -> some View {
        let target = store.choiceTarget(forDisplay: display.id)

        if !store.layouts.isEmpty {
            Section("Your Layouts") {
                ForEach(store.layouts) { layout in
                    choice(layout, display: display, current: current, target: target)
                }
            }
        }
        Section("Templates") {
            ForEach(Layout.templates) { layout in
                choice(layout, display: display, current: current, target: target)
            }
        }

        Divider()

        switch target {
        case .space:
            Button("Use the Display’s Layout on This Desktop") {
                store.clearAssignment(target)
            }
        case .display where current.source == .display:
            Button("Use the Default Layout") {
                store.clearAssignment(target)
            }
        default:
            EmptyView()
        }
        Button("Edit in Layouts…") {
            AppNavigation.shared.layoutsDisplayID = display.id
            PrimaryWindowCoordinator.shared.openOrFocus(.layoutEditor, using: openWindow)
        }
    }

    private func choice(
        _ layout: Layout,
        display: DisplayInfo,
        current: LayoutStore.Resolution,
        target: LayoutStore.Target
    ) -> some View {
        Toggle(isOn: Binding(
            get: { current.layout.id == layout.id },
            set: { _ in store.assign(layout.id, to: target) }
        )) {
            Label {
                Text(verbatim: layout.name)
            } icon: {
                Image(nsImage: thumbnail(layout, display: display))
            }
        }
    }

    private func thumbnail(_ layout: Layout, display: DisplayInfo) -> NSImage {
        MenuThumbnail.image(for: layout.zones, aspectRatio: display.aspectRatio, dark: colorScheme == .dark)
    }
}

/// Small pictures of layouts for menu items, which show images but not
/// views. Rendered once per look and kept.
@MainActor
enum MenuThumbnail {
    static let size = CGSize(width: 26, height: 16)
    private static var cache: [String: NSImage] = [:]

    static func image(for zones: [Zone], aspectRatio: CGFloat, dark: Bool) -> NSImage {
        let key = "\(dark)|\(Int((aspectRatio * 100).rounded()))|"
            + zones.map { "\($0.rect.x),\($0.rect.y),\($0.rect.width),\($0.rect.height)" }.joined(separator: ";")
        if let cached = cache[key] { return cached }

        let view = ZoneMap(zones: zones, aspectRatio: aspectRatio, spacing: 0.75, cornerRadius: 1.5, lineWidth: 0.75)
            .frame(width: size.width, height: size.height)
            .environment(\.colorScheme, dark ? .dark : .light)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let image = renderer.nsImage ?? NSImage(size: size)
        cache[key] = image
        return image
    }
}
