import AppKit
import SwiftUI

struct AboutSettingsPane: View {
    private static let repository = URL(string: "https://github.com/ulissescomonian/epyczones")!
    private static let license = URL(string: "https://github.com/ulissescomonian/epyczones/blob/main/LICENSE")!

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    private var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }

    var body: some View {
        Form {
            Section {
                VStack(spacing: 8) {
                    Image(nsImage: NSApplication.shared.applicationIconImage)
                        .resizable()
                        .frame(width: 96, height: 96)
                        .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
                    Text(verbatim: "EpycZones")
                        .font(.title.weight(.semibold))
                    Text("Version \(version) (\(build))")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Text("Custom window layouts and fast snapping for macOS.")
                        .font(.callout)
                        .padding(.top, 2)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }

            Section("Privacy") {
                Label {
                    Text("EpycZones has no network access, account or analytics. Layouts and settings stay on this Mac.")
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "lock.shield.fill")
                        .foregroundStyle(.green)
                }
            }

            Section("This Build") {
                Label {
                    Text("Signed on this Mac, not by an Apple Developer ID, and not notarized. Install it only from a source you trust.")
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "checkmark.seal")
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Link(destination: Self.repository) {
                    Label("Source Code on GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                }
                Link(destination: Self.license) {
                    Label("MIT License", systemImage: "doc.text")
                }
            }
        }
        .formStyle(.grouped)
    }
}
