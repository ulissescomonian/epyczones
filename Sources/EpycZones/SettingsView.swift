import AppKit
import Carbon
import SwiftUI

struct SettingsView: View {
    @State private var settings = AppSettings.shared
    @State private var workspaces = WorkspaceManager.loadAll()
    @State private var newWorkspaceName = ""
    @State private var recordingAction: HotKeyAction?
    @State private var keyMonitor: Any?
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
    }

    // MARK: - General

    private var generalTab: some View {
        Form {
            Toggle("Launch at Login", isOn: $settings.launchAtLogin)
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
                            }
                        }
                    }
                }

                Section {
                    Button("Reset All to Defaults") {
                        settings.customHotKeys = [:]
                        HotKeyManager.shared.reloadHotKeys()
                    }
                }
            }
            .padding()
        }
    }

    private func hotkeyButton(for action: HotKeyAction) -> some View {
        let binding = resolvedBinding(for: action)
        let isRecording = recordingAction == action

        return Button {
            // Unregister all hotkeys so they don't intercept the key press
            HotKeyManager.shared.unregisterAll()
            recordingAction = action
            // Install a local event monitor to capture the next key press
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                guard self.recordingAction == action else { return event }

                var carbonMods: UInt32 = 0
                if event.modifierFlags.contains(.control) { carbonMods |= UInt32(controlKey) }
                if event.modifierFlags.contains(.option) { carbonMods |= UInt32(optionKey) }
                if event.modifierFlags.contains(.shift) { carbonMods |= UInt32(shiftKey) }
                if event.modifierFlags.contains(.command) { carbonMods |= UInt32(cmdKey) }

                guard carbonMods != 0 else { return event }

                let keyCode = UInt32(event.keyCode)

                // Escape cancels recording
                if event.keyCode == 53 { // kVK_Escape
                    self.stopRecording()
                    return nil
                }

                self.settings.customHotKeys[action.rawValue] = HotKeyBinding(keyCode: keyCode, modifiers: carbonMods)
                self.stopRecording()
                return nil // consume the event
            }
        } label: {
            Text(isRecording ? "Press keys..." : binding.displayString)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(isRecording ? .orange : .primary)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
    }

    private func stopRecording() {
        recordingAction = nil
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
        HotKeyManager.shared.reloadHotKeys()
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
                                WorkspaceManager.restore(ws)
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

// MARK: - Key Press → Carbon Key Code

/// Convert a SwiftUI KeyEquivalent character to a Carbon virtual key code.
private func carbonKeyCode(from key: KeyEquivalent) -> UInt32 {
    let ch = key.character
    let map: [Character: Int] = [
        "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D,
        "e": kVK_ANSI_E, "f": kVK_ANSI_F, "g": kVK_ANSI_G, "h": kVK_ANSI_H,
        "i": kVK_ANSI_I, "j": kVK_ANSI_J, "k": kVK_ANSI_K, "l": kVK_ANSI_L,
        "m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O, "p": kVK_ANSI_P,
        "q": kVK_ANSI_Q, "r": kVK_ANSI_R, "s": kVK_ANSI_S, "t": kVK_ANSI_T,
        "u": kVK_ANSI_U, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X,
        "y": kVK_ANSI_Y, "z": kVK_ANSI_Z,
        "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3,
        "4": kVK_ANSI_4, "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7,
        "8": kVK_ANSI_8, "9": kVK_ANSI_9,
    ]

    // Arrow keys and special keys
    switch ch {
    case "\u{F702}": return UInt32(kVK_LeftArrow)   // NSLeftArrowFunctionKey
    case "\u{F703}": return UInt32(kVK_RightArrow)
    case "\u{F700}": return UInt32(kVK_UpArrow)
    case "\u{F701}": return UInt32(kVK_DownArrow)
    case "\r", "\n": return UInt32(kVK_Return)
    case "\t":       return UInt32(kVK_Tab)
    case " ":        return UInt32(kVK_Space)
    default: break
    }

    if let code = map[Character(String(ch).lowercased())] {
        return UInt32(code)
    }

    // - and = keys
    if ch == "-" { return UInt32(kVK_ANSI_Minus) }
    if ch == "=" { return UInt32(kVK_ANSI_Equal) }

    return UInt32.max
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
