import SwiftUI

@main
struct EpycZonesApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var store = LayoutStore.shared
    @State private var accessibility = AccessibilityStatus.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environment(store)
        } label: {
            // A warning while EpycZones cannot move windows.
            Image(systemName: accessibility.isGranted ? "rectangle.split.2x2" : "exclamationmark.triangle")
                .accessibilityLabel("EpycZones")
        }

        Window("Layouts", id: "layout-editor") {
            LayoutsView()
                .environment(store)
                .background(PrimaryWindowBridge(kind: .layoutEditor))
        }
        .defaultSize(width: 1080, height: 720)
        .windowResizability(.contentMinSize)

        Window("Settings", id: "settings") {
            SettingsView()
                .environment(store)
                .environment(AppRuleStore.shared)
                .environment(WorkspaceStore.shared)
                .background(PrimaryWindowBridge(kind: .settings))
        }
        .defaultSize(width: 840, height: 660)
        .windowResizability(.contentMinSize)
    }
}
