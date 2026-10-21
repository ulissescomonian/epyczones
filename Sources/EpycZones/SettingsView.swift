import AppKit
import SwiftUI

struct SettingsView: View {
    @State private var settings = AppSettings.shared
    @State private var workspaces = WorkspaceManager.loadAll()
    @State private var newWorkspaceName = ""
    /// Result of the last workspace restore.
    @State private var workspaceReport: String?
    @State private var recorder = HotKeyRecorder()
    @State private var ruleStore = AppRuleStore.shared
    @State private var newRuleAppID = ""
    @State private var newRuleTargetTag = "position:leftHalf"

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gear") }
            snappingTab
                .tabItem { Label("Snapping", systemImage: "rectangle.split.3x3") }
            hotkeysTab
                .tabItem { Label("Hotkeys", systemImage: "keyboard") }
            appRulesTab
                .tabItem { Label("App Rules", systemImage: "app.badge.checkmark") }
            workspacesTab
                .tabItem { Label("Workspaces", systemImage: "square.stack.3d.up") }
        }
        .frame(minWidth: 520, minHeight: 500)
        .padding()
        // Closing the window must never leave global hotkeys unregistered.
        .onDisappear { recorder.stop() }
    }

    // MARK: - General

    private var generalTab: some View {
        Form {
            Toggle("Launch at Login", isOn: $settings.launchAtLogin)
            Toggle("Restore windows to their zones at launch", isOn: $settings.restoreWindowsOnLaunch)
            Toggle("Animate window snapping", isOn: $settings.animateSnap)

            Section("Overlay Theme") {
                Picker("Theme", selection: $settings.overlayTheme) {
                    Text("Auto (follow system)").tag("auto")
                    Text("Dark").tag("dark")
                    Text("Light").tag("light")
                }
                .pickerStyle(.radioGroup)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Snapping

    private var snappingTab: some View {
        Form {
            Section("Zone Gaps") {
                HStack {
                    Slider(value: $settings.zoneGap, in: 0...20, step: 1)
                    Text("\(Int(settings.zoneGap))px")
                        .frame(width: 40)
                        .monospacedDigit()
                }
            }

            Section("Edge Snapping") {
                Toggle("Snap to halves/quarters when dragging near screen edges", isOn: $settings.edgeSnapEnabled)
                if settings.edgeSnapEnabled {
                    HStack {
                        Text("Trigger distance")
                        Slider(value: $settings.edgeSnapThreshold, in: 5...50, step: 1)
                        Text("\(Int(settings.edgeSnapThreshold))px")
                            .frame(width: 40)
                            .monospacedDigit()
                    }
                    HStack {
                        Text("Delay")
                        Slider(value: $settings.edgeSnapDelay, in: 0.1...1.0, step: 0.1)
                        Text(String(format: "%.1fs", settings.edgeSnapDelay))
                            .frame(width: 40)
                            .monospacedDigit()
                    }
                    Toggle("Top edge maximizes (instead of top half)", isOn: $settings.edgeSnapTopMaximize)
                    Toggle("Ignore edges shared with another display", isOn: $settings.edgeSnapIgnoresSharedEdges)
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Hotkeys

    private var hotkeysTab: some View {
        ScrollView {
            Form {
                Text("Click a shortcut and press new keys to rebind.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                let categories = Dictionary(grouping: HotKeyAction.allCases, by: \.category)
                let order = ["Halves", "Quarters", "Thirds", "Two Thirds", "Fourths", "Sixths", "Special", "Navigation"]

                ForEach(order, id: \.self) { cat in
                    if let actions = categories[cat] {
                        Section(cat) {
                            ForEach(actions) { action in
                                HStack(spacing: 10) {
                                    // Visual preview icon
                                    SnapPreviewIcon(rect: action.previewRect)
                                        .frame(width: 28, height: 20)

                                    Text(action.displayName)
                                        .frame(width: 130, alignment: .leading)

                                    Spacer()

                                    hotkeyButton(for: action)
                                        .frame(width: 100)
                                }

                                if recorder.action == action, let message = recorder.message {
                                    Text(message)
                                        .font(.caption)
                                        .foregroundStyle(recorder.messageIsError ? .red : .secondary)
                                }
                            }
                        }
                    }
                }

                Section {
                    Button("Reset All to Defaults") {
                        recorder.stop()
                        settings.customHotKeys = [:]
                        HotKeyManager.shared.reloadHotKeys()
                    }
                }
            }
            .padding()
        }
        .onDisappear { recorder.stop() }
    }

    private func hotkeyButton(for action: HotKeyAction) -> some View {
        let binding = resolvedBinding(for: action)
        let isRecording = recorder.action == action

        return Button {
            // Clicking the button that is recording cancels it.
            if isRecording {
                recorder.stop()
            } else {
                recorder.start(action)
            }
        } label: {
            // The prompt is proportional: in monospace it overflows the 100 pt button.
            Text(isRecording ? "Press keys…" : binding.displayString)
                .font(.system(.body, design: isRecording ? .default : .monospaced))
                .lineLimit(1)
                .foregroundStyle(isRecording ? .orange : .primary)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
    }

    // MARK: - Workspaces

    // MARK: - App Rules

    private var appRulesTab: some View {
        Form {
            Section("Rules") {
                if ruleStore.rules.isEmpty {
                    Text("No rules yet. New windows of an app with a rule are snapped automatically.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(ruleStore.rules) { rule in
                        HStack {
                            Text(rule.appName)
                            Spacer()
                            Text(rule.target.displayName)
                                .foregroundStyle(.secondary)
                                .font(.caption)
                            Button(role: .destructive) {
                                ruleStore.remove(id: rule.id)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }

            Section("Add Rule") {
                Picker("App", selection: $newRuleAppID) {
                    Text("Choose an app…").tag("")
                    ForEach(runningApps, id: \.bundleID) { app in
                        Text(app.name).tag(app.bundleID)
                    }
                }
                Picker("Snap to", selection: $newRuleTargetTag) {
                    ForEach(ruleTargetOptions, id: \.tag) { opt in
                        Text(opt.label).tag(opt.tag)
                    }
                }
                Button("Add Rule") { addAppRule() }
                    .buttonStyle(.borderedProminent)
                    .disabled(newRuleAppID.isEmpty)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var runningApps: [(bundleID: String, name: String)] {
        var seen = Set<String>()
        var apps: [(bundleID: String, name: String)] = []
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            guard let bid = app.bundleIdentifier, !seen.contains(bid) else { continue }
            seen.insert(bid)
            apps.append((bundleID: bid, name: app.localizedName ?? bid))
        }
        return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var ruleTargetOptions: [(tag: String, label: String)] {
        let positions: [SnapPosition] = [
            .leftHalf, .rightHalf, .topHalf, .bottomHalf,
            .topLeftQuarter, .topRightQuarter, .bottomLeftQuarter, .bottomRightQuarter,
            .firstThird, .centerThird, .lastThird,
            .maximize, .almostMaximize, .center,
        ]
        var opts = positions.map { (tag: "position:\($0.rawValue)", label: $0.displayName) }
        opts += (0..<9).map { (tag: "zone:\($0)", label: "Zone \($0 + 1) (active layout)") }
        return opts
    }

    private func addAppRule() {
        guard !newRuleAppID.isEmpty else { return }
        let name = runningApps.first { $0.bundleID == newRuleAppID }?.name ?? newRuleAppID

        let target: AppRule.Target
        if newRuleTargetTag.hasPrefix("zone:"), let index = Int(newRuleTargetTag.dropFirst(5)) {
            target = .zone(index)
        } else if newRuleTargetTag.hasPrefix("position:"),
                  let position = SnapPosition(rawValue: String(newRuleTargetTag.dropFirst(9))) {
            target = .position(position)
        } else {
            return
        }

        ruleStore.add(AppRule(bundleID: newRuleAppID, appName: name, target: target))
        newRuleAppID = ""
    }

    private var workspacesTab: some View {
        Form {
            Section("Saved Workspaces") {
                if workspaces.isEmpty {
                    Text("No workspaces saved yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(workspaces) { ws in
                        HStack {
                            Text(ws.name)
                            Spacer()
                            Text("\(ws.entries.count) windows")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                            Button("Restore") {
                                workspaceReport = WorkspaceManager.restore(ws).summary
                            }
                            .buttonStyle(.bordered)
                            Button(role: .destructive) {
                                workspaces.removeAll { $0.id == ws.id }
                                WorkspaceManager.saveAll(workspaces)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }

                if let workspaceReport {
                    Text(workspaceReport)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Capture") {
                HStack {
                    TextField("Workspace name", text: $newWorkspaceName)
                        .textFieldStyle(.roundedBorder)
                    Button("Save Current") {
                        let name = newWorkspaceName.isEmpty ? "Workspace \(workspaces.count + 1)" : newWorkspaceName
                        let ws = WorkspaceManager.captureCurrentWorkspace(name: name)
                        workspaces.append(ws)
                        WorkspaceManager.saveAll(workspaces)
                        newWorkspaceName = ""
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }
}

// MARK: - Snap Preview Icon

/// Small visual icon showing where the window will be positioned.
struct SnapPreviewIcon: View {
    let rect: (x: Double, y: Double, w: Double, h: Double)

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Screen outline
                RoundedRectangle(cornerRadius: 2)
                    .stroke(Color.secondary.opacity(0.4), lineWidth: 0.5)

                // Highlighted area
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.accentColor.opacity(0.5))
                    .frame(
                        width: rect.w * geo.size.width - 2,
                        height: rect.h * geo.size.height - 2
                    )
                    .position(
                        x: (rect.x + rect.w / 2) * geo.size.width,
                        y: (rect.y + rect.h / 2) * geo.size.height
                    )
            }
        }
    }
}
