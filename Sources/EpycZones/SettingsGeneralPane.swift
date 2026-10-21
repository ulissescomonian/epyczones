import AppKit
import SwiftUI

struct GeneralSettingsPane: View {
    @State private var settings = AppSettings.shared

    var body: some View {
        Form {
            Section {
                AccessibilityStatusRow()
            } header: {
                PaneHeader(
                    symbol: SettingsPane.general.symbol,
                    color: SettingsPane.general.color,
                    title: "General",
                    subtitle: "Permissions, startup and how EpycZones looks while you arrange windows."
                )
            }

            Section("Startup") {
                Toggle("Open at login", isOn: $settings.launchAtLogin)
                Toggle(isOn: $settings.restoreWindowsOnLaunch) {
                    Text("Restore windows to their zones")
                    Text("When EpycZones opens, windows you snapped to a zone go back to it.")
                }
            }

            Section("Appearance") {
                Picker("Zone overlay", selection: $settings.overlayTheme) {
                    Text("Match System").tag("auto")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                .pickerStyle(.segmented)
                Toggle(isOn: $settings.animateSnap) {
                    Text("Animate snapping")
                    Text("Windows glide into place instead of jumping.")
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// Live Accessibility status with a way to fix it.
struct AccessibilityStatusRow: View {
    private var status = AccessibilityStatus.shared

    var body: some View {
        let granted = status.isGranted
        HStack(spacing: 12) {
            IconTile(symbol: "hand.raised.fill", color: .blue, size: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text("Accessibility")
                Group {
                    if granted {
                        Text("EpycZones can move and resize the windows of other apps.")
                    } else {
                        Text("Needed to move and resize the windows of other apps.")
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            if granted {
                Label("Allowed", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.callout.weight(.medium))
            } else {
                Button("Open Privacy Settings…") {
                    AccessibilityChecker.openPrivacySettings()
                }
            }
        }
        .padding(.vertical, 2)
    }
}
