import SwiftUI

/// Sections of the Settings window, in sidebar order.
enum SettingsPane: String, CaseIterable, Identifiable {
    case general, snapping, shortcuts, appRules, workspaces, about

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .general: return "General"
        case .snapping: return "Snapping"
        case .shortcuts: return "Shortcuts"
        case .appRules: return "App Rules"
        case .workspaces: return "Workspaces"
        case .about: return "About"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape.fill"
        case .snapping: return "rectangle.split.2x2.fill"
        case .shortcuts: return "command"
        case .appRules: return "app.badge.checkmark.fill"
        case .workspaces: return "square.stack.3d.up.fill"
        case .about: return "info"
        }
    }

    var color: Color {
        switch self {
        case .general: return .gray
        case .snapping: return .blue
        case .shortcuts: return .purple
        case .appRules: return .green
        case .workspaces: return .orange
        case .about: return .secondary
        }
    }
}

/// The Settings window: a sidebar of sections, each a grouped form.
struct SettingsView: View {
    @State private var selection: SettingsPane?

    init(initialPane: SettingsPane = .general) {
        _selection = State(initialValue: initialPane)
    }

    var body: some View {
        NavigationSplitView {
            List(SettingsPane.allCases, selection: $selection) { pane in
                Label {
                    Text(pane.title)
                } icon: {
                    IconTile(symbol: pane.symbol, color: pane.color)
                }
                .tag(pane)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
        } detail: {
            let pane = selection ?? .general
            detail(for: pane)
                .navigationTitle(pane.title)
        }
        .frame(minWidth: 760, minHeight: 560)
        .onChange(of: AppNavigation.shared.settingsPane, initial: true) { _, pane in
            guard let pane else { return }
            selection = pane
            AppNavigation.shared.settingsPane = nil
        }
    }

    @ViewBuilder
    private func detail(for pane: SettingsPane) -> some View {
        switch pane {
        case .general: GeneralSettingsPane()
        case .snapping: SnappingSettingsPane()
        case .shortcuts: ShortcutsSettingsPane()
        case .appRules: AppRulesSettingsPane()
        case .workspaces: WorkspacesSettingsPane()
        case .about: AboutSettingsPane()
        }
    }
}

// MARK: - Shared Rows

/// A slider row with its value shown in a fixed-width label.
struct ValueSlider: View {
    let title: LocalizedStringKey
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let label: (Double) -> String

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 10) {
                Slider(value: $value, in: range, step: step)
                    .frame(maxWidth: 240)
                Text(verbatim: label(value))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 48, alignment: .trailing)
            }
        }
    }
}

/// An empty list, explained, with the action that fills it.
struct EmptyListMessage: View {
    let symbol: String
    let title: LocalizedStringKey
    let message: LocalizedStringKey

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.tertiary)
                .padding(.bottom, 2)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
    }
}
