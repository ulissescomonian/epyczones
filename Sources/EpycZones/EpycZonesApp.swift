import SwiftUI

@main
struct EpycZonesApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var store = LayoutStore.shared

    var body: some Scene {
        MenuBarExtra("EpycZones", systemImage: "rectangle.split.2x2") {
            MenuBarView()
                .environment(store)
        }

        Window("Layout Editor", id: "layout-editor") {
            LayoutEditorView()
                .environment(store)
                .background(PrimaryWindowBridge(kind: .layoutEditor))
        }
        .defaultSize(width: 860, height: 560)

        Window("Settings", id: "settings") {
            SettingsView()
                .background(PrimaryWindowBridge(kind: .settings))
        }
        .defaultSize(width: 560, height: 420)
    }
}

struct MenuBarView: View {
    @Environment(LayoutStore.self) private var store
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        // Layout selection
        if store.layouts.count > 1 {
            Section("Layouts") {
                ForEach(store.layouts) { layout in
                    Button {
                        store.setActive(id: layout.id)
                    } label: {
                        HStack {
                            if layout.id == store.activeLayoutID {
                                Image(systemName: "checkmark")
                            }
                            Text(layout.name)
                        }
                    }
                }
            }

            Divider()
        }

        Button("Edit Layouts...") {
            PrimaryWindowCoordinator.shared.openOrFocus(.layoutEditor, using: openWindow)
        }

        Button("Settings...") {
            PrimaryWindowCoordinator.shared.openOrFocus(.settings, using: openWindow)
        }

        Button("Quit") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}

// MARK: - Layout Preview (mini zone map in menu bar)

struct LayoutPreviewView: View {
    let layout: Layout

    private let zoneColors: [Color] = [
        .blue, .green, .orange, .purple, .pink, .teal, .indigo, .mint, .cyan, .red,
    ]

    var body: some View {
        GeometryReader { geo in
            ZStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.primary.opacity(0.05))
                    .stroke(Color.primary.opacity(0.15), lineWidth: 0.5)

                ForEach(Array(layout.zones.enumerated()), id: \.element.id) { index, zone in
                    let r = zone.rect
                    let color = zoneColors[index % zoneColors.count]

                    RoundedRectangle(cornerRadius: 2)
                        .fill(color.opacity(0.3))
                        .overlay(
                            RoundedRectangle(cornerRadius: 2)
                                .stroke(color.opacity(0.6), lineWidth: 1)
                        )
                        .overlay(
                            Text("\(index + 1)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(color)
                        )
                        .frame(
                            width: r.width * geo.size.width - 2,
                            height: r.height * geo.size.height - 2
                        )
                        .position(
                            x: (r.x + r.width / 2) * geo.size.width,
                            y: (r.y + r.height / 2) * geo.size.height
                        )
                }
            }
        }
    }
}
