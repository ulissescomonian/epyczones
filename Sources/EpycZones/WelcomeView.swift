import AppKit
import SwiftUI

/// The first-run guide: allow Accessibility, then choose a layout for each
/// display. A copy that lost the permission sees only the first step.
struct WelcomeView: View {
    enum Step: Hashable {
        case accessibility
        case layouts
    }

    let steps: [Step]
    let onFinish: () -> Void

    @State private var index = 0
    private var accessibility = AccessibilityStatus.shared

    init(steps: [Step], startingAt index: Int = 0, onFinish: @escaping () -> Void) {
        self.steps = steps
        self.onFinish = onFinish
        _index = State(initialValue: index)
    }

    private var step: Step { steps[index] }
    private var isLast: Bool { index == steps.count - 1 }
    private var isFirstRun: Bool { steps.contains(.layouts) }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch step {
                case .accessibility:
                    AccessibilityStep(isFirstRun: isFirstRun, isGranted: accessibility.isGranted)
                case .layouts:
                    LayoutsStep()
                }
            }
            .padding(.horizontal, 48)
            .padding(.vertical, 28)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            HStack(spacing: 10) {
                if steps.count > 1 {
                    HStack(spacing: 6) {
                        ForEach(steps.indices, id: \.self) { dot in
                            Circle()
                                .fill(dot == index ? Color.accentColor : Color.primary.opacity(0.2))
                                .frame(width: 7, height: 7)
                        }
                    }
                    .accessibilityElement()
                    .accessibilityLabel(Text("Step \(index + 1) of \(steps.count)"))
                }
                Spacer()
                buttons
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .frame(width: 620, height: 600)
        .animation(.easeInOut(duration: 0.2), value: index)
    }

    @ViewBuilder
    private var buttons: some View {
        switch step {
        case .accessibility:
            if !accessibility.isGranted {
                Button("Later", action: advance)
            }
            Button(isLast ? "Done" : "Continue", action: advance)
                .keyboardShortcut(.defaultAction)
                .disabled(!accessibility.isGranted)
        case .layouts:
            if index > 0 {
                Button("Back") { index -= 1 }
            }
            Button("Done", action: advance)
                .keyboardShortcut(.defaultAction)
        }
    }

    private func advance() {
        if isLast {
            onFinish()
        } else {
            index += 1
        }
    }
}

// MARK: - Steps

private struct AccessibilityStep: View {
    let isFirstRun: Bool
    let isGranted: Bool

    var body: some View {
        VStack(spacing: 18) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
                .shadow(color: .black.opacity(0.15), radius: 8, y: 3)

            VStack(spacing: 8) {
                Text(isFirstRun ? "Welcome to EpycZones" : "Allow EpycZones Again")
                    .font(.largeTitle.weight(.semibold))
                Group {
                    if isFirstRun {
                        Text("To move and resize the windows of other apps, EpycZones needs your permission in Accessibility.")
                    } else {
                        Text("macOS turned off Accessibility for this copy of EpycZones, as it does after some updates. Turn it on again to keep snapping windows.")
                    }
                }
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 14) {
                IconTile(symbol: "hand.raised.fill", color: .blue, size: 38)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Accessibility")
                        .font(.headline)
                    Group {
                        if isGranted {
                            Text("Allowed. EpycZones can move windows.")
                        } else {
                            Text("Turn on EpycZones in Privacy & Security, then come back.")
                        }
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                if isGranted {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(.green)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    Button("Open Privacy Settings…") {
                        AccessibilityChecker.openPrivacySettings()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(isGranted ? Color.green.opacity(0.5) : Color.primary.opacity(0.1), lineWidth: 1)
            )
            .animation(.spring(duration: 0.3), value: isGranted)

            Label {
                Text("EpycZones only moves and resizes windows. It doesn’t read what is in them and never connects to the internet.")
            } icon: {
                Image(systemName: "lock.shield")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct LayoutsStep: View {
    @Environment(LayoutStore.self) private var store
    @State private var displays = DisplayInfo.connected()

    var body: some View {
        let modifier = AppSettings.shared.zoneDragModifier

        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Text("Choose a Layout for Each Display")
                    .font(.largeTitle.weight(.semibold))
                    .multilineTextAlignment(.center)
                Text("Hold \(modifier.symbol) \(modifier.name) while you drag a window to see the zones of its display. You can change layouts anytime from the menu bar.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            DisplayArrangementMap(displays: displays)
                .frame(height: 104)

            VStack(spacing: 0) {
                ForEach(Array(displays.enumerated()), id: \.element.id) { offset, display in
                    if offset > 0 {
                        Divider().padding(.leading, 48)
                    }
                    HStack(spacing: 12) {
                        Image(systemName: display.symbol)
                            .font(.system(size: 17))
                            .foregroundStyle(.secondary)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(verbatim: display.name)
                            Text(verbatim: display.resolutionDescription)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 12)
                        LayoutPicker(selection: Binding(
                            get: { store.resolution(forDisplay: display.id, name: display.name).layout.id },
                            set: { store.assign($0, to: .display(display.id)) }
                        ))
                        .fixedSize()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
            )
        }
        .onAppear(perform: suggestLayouts)
    }

    /// Gives each display without a layout of its own a template that suits
    /// its shape, so the first drag already looks right.
    private func suggestLayouts() {
        for display in displays
        where store.resolution(forDisplay: display.id, name: display.name).source == .defaultLayout {
            store.assign(Layout.template(.suggested(for: display)).id, to: .display(display.id))
        }
    }
}

extension LayoutTemplate {
    /// Rows for portrait displays, three columns for ultrawide ones, two
    /// columns otherwise.
    static func suggested(for display: DisplayInfo) -> LayoutTemplate {
        if display.isPortrait { return .twoRows }
        if display.aspectRatio >= 2.2 { return .threeColumns }
        return .twoColumns
    }
}

// MARK: - Window

/// Shows the welcome guide in its own window, outside the SwiftUI scenes,
/// so it can open at launch before any menu or window exists.
@MainActor
final class WelcomeWindowController {
    static let shared = WelcomeWindowController()

    private var window: NSWindow?
    private var closeObserver: NSObjectProtocol?

    private init() {}

    func show(steps: [WelcomeView.Step]) {
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let view = WelcomeView(steps: steps) { [weak self] in
            self?.window?.close()
        }
        .environment(LayoutStore.shared)

        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.title = String(localized: "Welcome to EpycZones")
        window.isReleasedWhenClosed = false
        window.center()

        // Closing the window, by Done or its close button, ends the guide.
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                AppSettings.shared.hasCompletedOnboarding = true
                if let observer = self?.closeObserver {
                    NotificationCenter.default.removeObserver(observer)
                }
                self?.closeObserver = nil
                self?.window = nil
            }
        }

        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
