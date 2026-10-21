import AppKit
import SwiftUI

struct SnappingSettingsPane: View {
    @State private var settings = AppSettings.shared
    @Environment(LayoutStore.self) private var store

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $settings.zoneDragEnabled) {
                    Text("Show zones while dragging")
                    Text("Hold the key below while you drag a window to see your layout. Drop on the border between two zones to span both.")
                }
                Picker("Key to hold", selection: $settings.zoneDragModifier) {
                    ForEach(ZoneDragModifier.allCases) { modifier in
                        Text(verbatim: "\(modifier.symbol)  \(modifier.name)").tag(modifier)
                    }
                }
                .disabled(!settings.zoneDragEnabled)
                if settings.zoneDragEnabled && settings.zoneDragModifier == .option {
                    InlineNotice(
                        kind: .info,
                        text: String(localized: "macOS also offers its own tiling while you drag with Option held.")
                    )
                }
            } header: {
                PaneHeader(
                    symbol: SettingsPane.snapping.symbol,
                    color: SettingsPane.snapping.color,
                    title: "Snapping",
                    subtitle: "How dragging a window reveals your zones and the edges of the screen."
                )
            }

            Section {
                ValueSlider(
                    title: "Space between zones",
                    value: $settings.zoneGap,
                    range: 0...24,
                    step: 1,
                    label: { String(localized: "\(Int($0)) pt") }
                )
                GapPreview(zones: previewZones, gap: settings.zoneGap)
            } header: {
                Text("Zones")
            } footer: {
                Text("Windows keep this distance from each other and from the edges of their zone.")
            }

            Section {
                Toggle(isOn: $settings.edgeSnapEnabled) {
                    Text("Snap to screen edges")
                    Text("Drag a window to an edge for half the screen, or into a corner for a quarter.")
                }
                Group {
                    ValueSlider(
                        title: "Distance from the edge",
                        value: $settings.edgeSnapThreshold,
                        range: 5...50,
                        step: 1,
                        label: { String(localized: "\(Int($0)) pt") }
                    )
                    ValueSlider(
                        title: "Wait before showing",
                        value: $settings.edgeSnapDelay,
                        range: 0.1...1.0,
                        step: 0.1,
                        label: { String(format: "%.1f s", $0) }
                    )
                    Toggle("Top edge maximizes the window", isOn: $settings.edgeSnapTopMaximize)
                    Toggle(isOn: $settings.edgeSnapIgnoresSharedEdges) {
                        Text("Ignore edges between displays")
                        Text("Moving a window to another display never snaps it on the way.")
                    }
                }
                .disabled(!settings.edgeSnapEnabled)
            } header: {
                Text("Screen Edges")
            }
        }
        .formStyle(.grouped)
    }

    /// Zones of the layout on the main display, or two columns when there is none.
    private var previewZones: [Zone] {
        let zones = NSScreen.main.flatMap { store.activeLayout(for: $0)?.zones } ?? []
        return zones.isEmpty ? Layout.twoColumns().zones : zones
    }
}

/// The current layout with the zone gap applied, magnified so a few points
/// of space are visible in a thumbnail.
private struct GapPreview: View {
    let zones: [Zone]
    let gap: Double

    var body: some View {
        HStack(spacing: 14) {
            ZoneMap(zones: zones, aspectRatio: 16.0 / 9.0, spacing: 1.5 + gap * 0.4, cornerRadius: 3.5)
                .frame(width: 128)
                .animation(.easeOut(duration: 0.15), value: gap)
            Text("Preview of the layout on your main display, with the space magnified.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }
}
