import SwiftUI

struct ShortcutsSettingsPane: View {
    @State private var settings = AppSettings.shared
    @State private var recorder = HotKeyRecorder()
    @State private var search = ""
    @State private var confirmingReset = false

    var body: some View {
        Form {
            Section {
                Picker("Modifier keys", selection: $settings.zoneHotKeyModifiers) {
                    ForEach(ZoneShortcutModifiers.allCases) { choice in
                        Text(verbatim: "\(choice.symbols)  1 … 9").tag(choice)
                    }
                }
                .onChange(of: settings.zoneHotKeyModifiers) {
                    HotKeyManager.shared.reloadHotKeys()
                }
                LabeledContent("Zones 1 to 9") {
                    let zones = HotKeyBinding.zoneBindings(modifiers: settings.zoneHotKeyModifiers.rawValue)
                    HStack(spacing: 6) {
                        KeyCaps(binding: zones[0])
                        Text(verbatim: "…").foregroundStyle(.secondary)
                        KeyCaps(binding: zones[8])
                    }
                }
            } header: {
                VStack(spacing: 0) {
                    PaneHeader(
                        symbol: SettingsPane.shortcuts.symbol,
                        color: SettingsPane.shortcuts.color,
                        title: "Shortcuts",
                        subtitle: "Move the focused window from the keyboard. Click a shortcut, then press the new keys."
                    )
                    Text("Zones")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } footer: {
                Text("Sends the focused window to that zone of the layout on its display.")
            }

            ForEach(HotKeyCategory.allCases) { category in
                let actions = visibleActions(in: category)
                if !actions.isEmpty {
                    Section(category.title) {
                        ForEach(actions) { action in
                            ShortcutRow(action: action, recorder: recorder)
                        }
                    }
                }
            }

            if search.isEmpty {
                Section {
                    Button("Restore Default Shortcuts…") {
                        confirmingReset = true
                    }
                }
            } else if HotKeyCategory.allCases.allSatisfy({ visibleActions(in: $0).isEmpty }) {
                Section {
                    EmptyListMessage(
                        symbol: "magnifyingglass",
                        title: "No Shortcuts Found",
                        message: "Try another name, such as “half” or “display”."
                    )
                }
            }
        }
        .formStyle(.grouped)
        .searchable(text: $search, placement: .toolbar, prompt: Text("Search shortcuts"))
        .confirmationDialog("Restore the default shortcuts?", isPresented: $confirmingReset) {
            Button("Restore Defaults", role: .destructive) {
                recorder.stop()
                settings.customHotKeys = [:]
                settings.zoneHotKeyModifiers = .default
                HotKeyManager.shared.reloadHotKeys()
            }
        } message: {
            Text("Every shortcut you changed goes back to its original keys.")
        }
        .onDisappear { recorder.stop() }
    }

    private func visibleActions(in category: HotKeyCategory) -> [HotKeyAction] {
        let actions = HotKeyAction.allCases.filter { $0.category == category }
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return actions }
        return actions.filter { $0.displayName.localizedStandardContains(query) }
    }
}

/// One action: what it does, drawn, and its shortcut.
private struct ShortcutRow: View {
    let action: HotKeyAction
    let recorder: HotKeyRecorder

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                ActionIcon(action: action)
                    .frame(width: 30, height: 19)
                Text(verbatim: action.displayName)
                Spacer(minLength: 12)
                ShortcutField(action: action, recorder: recorder)
            }
            if recorder.action == action, let message = recorder.message {
                Text(verbatim: message)
                    .font(.caption)
                    .foregroundStyle(recorder.messageIsError ? Color.red : Color.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.15), value: recorder.message)
    }
}

/// A snap position drawn on a tiny screen, or a symbol for other actions.
private struct ActionIcon: View {
    let action: HotKeyAction

    var body: some View {
        if let symbol = action.symbol {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                )
        } else {
            PositionMap(rect: action.previewRect)
        }
    }
}

/// Shows a shortcut as keycaps; click to record a new one.
struct ShortcutField: View {
    let action: HotKeyAction
    let recorder: HotKeyRecorder
    @State private var isHovering = false

    var body: some View {
        let binding = resolvedBinding(for: action)
        let isRecording = recorder.action == action
        let isCustomized = AppSettings.shared.customHotKeys[action.rawValue] != nil

        HStack(spacing: 6) {
            Button {
                if isRecording {
                    recorder.stop()
                } else {
                    recorder.start(action)
                }
            } label: {
                Group {
                    if isRecording {
                        Text("Type a shortcut")
                            .foregroundStyle(Color.accentColor)
                    } else if binding.isNone {
                        Text("None")
                            .foregroundStyle(.tertiary)
                    } else {
                        KeyCaps(binding: binding)
                    }
                }
                .font(.callout)
                .frame(minWidth: 104, minHeight: 27)
                .padding(.horizontal, 6)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isRecording
                              ? Color.accentColor.opacity(0.12)
                              : Color.primary.opacity(isHovering ? 0.09 : 0.045))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(isRecording ? Color.accentColor : Color.clear, lineWidth: 1.5)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { isHovering = $0 }
            .help(Text("Click, then press the new shortcut. Esc cancels, Delete removes it."))

            Button {
                recorder.stop()
                AppSettings.shared.customHotKeys[action.rawValue] = nil
                HotKeyManager.shared.reloadHotKeys()
            } label: {
                Image(systemName: "arrow.uturn.backward.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(Text("Restore the default shortcut"))
            .opacity(isCustomized ? 1 : 0)
            .disabled(!isCustomized)
        }
    }
}
