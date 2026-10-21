import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct AppRulesSettingsPane: View {
    @Environment(AppRuleStore.self) private var ruleStore
    @State private var draft: AppRuleDraft?
    @State private var pendingDeletion: AppRule?

    var body: some View {
        Form {
            Section {
                if ruleStore.rules.isEmpty {
                    EmptyListMessage(
                        symbol: "app.badge.checkmark",
                        title: "No App Rules Yet",
                        message: "Add a rule to open every new window of an app in the same place."
                    )
                } else {
                    ForEach(ruleStore.rules) { rule in
                        AppRuleRow(
                            rule: rule,
                            onEdit: { draft = AppRuleDraft(rule: rule) },
                            onDelete: { pendingDeletion = rule }
                        )
                    }
                }
            } header: {
                PaneHeader(
                    symbol: SettingsPane.appRules.symbol,
                    color: SettingsPane.appRules.color,
                    title: "App Rules",
                    subtitle: "Choose where new windows of an app open, so you never place them by hand."
                )
            } footer: {
                HStack(alignment: .firstTextBaseline) {
                    Text("Rules apply to new document windows, not to dialogs or panels.")
                    Spacer()
                    Button("Add Rule…") { draft = AppRuleDraft() }
                }
            }
        }
        .formStyle(.grouped)
        .sheet(item: $draft) { draft in
            AppRuleEditor(draft: draft)
        }
        .confirmationDialog(
            "Delete this rule?",
            isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }),
            presenting: pendingDeletion
        ) { rule in
            Button("Delete Rule", role: .destructive) {
                ruleStore.remove(id: rule.id)
            }
        } message: { rule in
            Text("New windows of \(rule.appName) will open where the app places them.")
        }
    }
}

// MARK: - Row

private struct AppRuleRow: View {
    let rule: AppRule
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: AppIcons.icon(forBundleID: rule.bundleID))
                .resizable()
                .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: rule.appName)
                Text(verbatim: rule.target.displayName)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            TargetThumbnail(target: rule.target)
                .frame(width: 48)
            Menu {
                Button("Edit Rule…", action: onEdit)
                Button("Delete Rule…", role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 15))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: onEdit)
        .contextMenu {
            Button("Edit Rule…", action: onEdit)
            Button("Delete Rule…", role: .destructive, action: onDelete)
        }
    }
}

/// Where a rule puts windows: a position, or a zone of the main display's layout.
private struct TargetThumbnail: View {
    let target: AppRule.Target
    @Environment(LayoutStore.self) private var store

    var body: some View {
        switch target {
        case .position(let position):
            PositionMap(rect: position.previewRect)
        case .zone(let index):
            let screen = NSScreen.main ?? NSScreen.screens.first
            let zones = screen.map { store.layout(for: $0).zones } ?? []
            ZoneMap(zones: zones, highlighted: [index])
        }
    }
}

// MARK: - Editor

/// A rule being created or edited in the sheet.
struct AppRuleDraft: Identifiable {
    enum Kind: Hashable { case position, zone }

    let id = UUID()
    /// The rule being edited, or nil for a new rule.
    var ruleID: UUID?
    var originalBundleID: String?
    var bundleID = ""
    var appName = ""
    var kind = Kind.position
    var position = SnapPosition.leftHalf
    var zoneIndex = 0

    init() {}

    init(rule: AppRule) {
        ruleID = rule.id
        originalBundleID = rule.bundleID
        bundleID = rule.bundleID
        appName = rule.appName
        switch rule.target {
        case .position(let position):
            kind = .position
            self.position = position
        case .zone(let index):
            kind = .zone
            zoneIndex = index
        }
    }

    var target: AppRule.Target {
        kind == .position ? .position(position) : .zone(zoneIndex)
    }
}

struct AppRuleEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppRuleStore.self) private var ruleStore
    @Environment(LayoutStore.self) private var layoutStore
    @State var draft: AppRuleDraft
    @State private var chosenApps: [AppChoice] = []
    @State private var previewScreenIndex = 0

    /// Positions offered for rules, in reading order.
    private static let positions: [SnapPosition] = [
        .leftHalf, .rightHalf, .topHalf, .bottomHalf,
        .topLeftQuarter, .topRightQuarter, .bottomLeftQuarter, .bottomRightQuarter,
        .firstThird, .centerThird, .lastThird,
        .firstTwoThirds, .lastTwoThirds,
        .maximize, .almostMaximize, .center,
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                IconTile(symbol: SettingsPane.appRules.symbol, color: SettingsPane.appRules.color, size: 28)
                Group {
                    if draft.ruleID == nil {
                        Text("New App Rule")
                    } else {
                        Text("Edit App Rule")
                    }
                }
                .font(.title3.weight(.semibold))
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 2)

            Form {
                Section {
                    Picker("App", selection: $draft.bundleID) {
                        Text("Choose an App").tag("")
                        ForEach(appChoices) { app in
                            Label {
                                Text(verbatim: app.name)
                            } icon: {
                                Image(nsImage: AppIcons.menuIcon(forBundleID: app.bundleID))
                            }
                            .tag(app.bundleID)
                        }
                    }
                    .onChange(of: draft.bundleID) {
                        draft.appName = appChoices.first { $0.bundleID == draft.bundleID }?.name ?? draft.appName
                    }
                    Button("Choose Another App…", action: chooseApp)
                    if let replaced = replacedRule {
                        InlineNotice(
                            kind: .info,
                            text: String(localized: "This replaces the current rule for \(replaced.appName).")
                        )
                    }
                }

                Section {
                    Picker("Open new windows in", selection: $draft.kind) {
                        Text("A Position").tag(AppRuleDraft.Kind.position)
                        Text("A Zone").tag(AppRuleDraft.Kind.zone)
                    }
                    .pickerStyle(.segmented)

                    if draft.kind == .position {
                        positionGrid
                    } else {
                        zoneGrid
                    }
                } header: {
                    Text("Placement")
                } footer: {
                    if draft.kind == .zone {
                        Text("Zone numbers follow the layout of the display where the window opens.")
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(draft.ruleID == nil ? "Add Rule" : "Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(draft.bundleID.isEmpty)
            }
            .padding(16)
        }
        .frame(width: 580, height: 620)
    }

    // MARK: Placement grids

    private var positionGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 10)], spacing: 10) {
            ForEach(Self.positions, id: \.self) { position in
                ChoiceTile(isSelected: draft.position == position, title: position.displayName) {
                    PositionMap(rect: position.previewRect)
                } action: {
                    draft.position = position
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var zoneGrid: some View {
        let screens = NSScreen.screens
        if screens.count > 1 {
            Picker("Show the layout of", selection: $previewScreenIndex) {
                ForEach(screens.indices, id: \.self) { index in
                    Text(verbatim: screens[index].localizedName).tag(index)
                }
            }
        }
        let screen = screens.indices.contains(previewScreenIndex) ? screens[previewScreenIndex] : screens.first
        let zones = screen.map { layoutStore.layout(for: $0).zones } ?? []
        let aspect = screen.map { $0.visibleFrame.width / max(1, $0.visibleFrame.height) } ?? 16.0 / 10.0

        if zones.isEmpty {
            InlineNotice(kind: .warning, text: String(localized: "This display has no layout with zones yet."))
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: aspect < 1 ? 70 : 110), spacing: 10)], spacing: 10) {
                ForEach(zones.indices, id: \.self) { index in
                    ChoiceTile(
                        isSelected: draft.zoneIndex == index,
                        title: String(localized: "Zone \(index + 1)")
                    ) {
                        ZoneMap(zones: zones, aspectRatio: aspect, highlighted: [index])
                    } action: {
                        draft.zoneIndex = index
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: Apps

    private var appChoices: [AppChoice] {
        var choices = AppChoice.runningApps() + chosenApps
        if !draft.bundleID.isEmpty, !choices.contains(where: { $0.bundleID == draft.bundleID }) {
            choices.append(AppChoice(bundleID: draft.bundleID, name: draft.appName))
        }
        var seen = Set<String>()
        return choices
            .filter { seen.insert($0.bundleID).inserted }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Another rule this one would replace: one rule per app.
    private var replacedRule: AppRule? {
        guard !draft.bundleID.isEmpty, draft.bundleID != draft.originalBundleID else { return nil }
        return ruleStore.rule(for: draft.bundleID)
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = String(localized: "Choose")
        guard panel.runModal() == .OK,
              let url = panel.url,
              let bundleID = Bundle(url: url)?.bundleIdentifier else { return }
        let choice = AppChoice(bundleID: bundleID, name: AppIcons.name(ofAppAt: url))
        chosenApps.append(choice)
        draft.bundleID = bundleID
        draft.appName = choice.name
    }

    private func save() {
        if let ruleID = draft.ruleID, draft.originalBundleID != draft.bundleID {
            ruleStore.remove(id: ruleID)
        }
        ruleStore.add(AppRule(
            id: draft.ruleID ?? UUID(),
            bundleID: draft.bundleID,
            appName: draft.appName,
            target: draft.target
        ))
        dismiss()
    }
}

/// A selectable picture with a caption, for grids of choices.
struct ChoiceTile<Preview: View>: View {
    let isSelected: Bool
    let title: String
    @ViewBuilder let preview: () -> Preview
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                preview()
                    .frame(maxHeight: 64)
                Text(verbatim: title)
                    .font(.caption)
                    .lineLimit(1)
                    .foregroundStyle(isSelected ? Color.accentColor : .primary)
            }
            .padding(8)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.035))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: isSelected ? 2 : 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Apps

struct AppChoice: Identifiable, Hashable {
    let bundleID: String
    let name: String
    var id: String { bundleID }

    /// Regular apps running now, EpycZones excluded.
    static func runningApps() -> [AppChoice] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.processIdentifier != getpid() }
            .compactMap { app in
                app.bundleIdentifier.map { AppChoice(bundleID: $0, name: app.localizedName ?? $0) }
            }
    }
}

enum AppIcons {
    static func icon(forBundleID bundleID: String) -> NSImage {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return NSWorkspace.shared.icon(for: .application)
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    /// A 16 pt copy, the size menus draw item icons at.
    static func menuIcon(forBundleID bundleID: String) -> NSImage {
        let icon = icon(forBundleID: bundleID).copy() as? NSImage ?? NSImage()
        icon.size = NSSize(width: 16, height: 16)
        return icon
    }

    static func name(ofAppAt url: URL) -> String {
        let displayName = FileManager.default.displayName(atPath: url.path)
        return displayName.hasSuffix(".app") ? String(displayName.dropLast(4)) : displayName
    }

    static func name(forBundleID bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
        return name(ofAppAt: url)
    }
}
