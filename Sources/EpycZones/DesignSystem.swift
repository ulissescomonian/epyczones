import SwiftUI

// MARK: - Palette

/// Zone colors, shared by the overlay, the editor, thumbnails and menus so a
/// zone keeps its color everywhere. Ordered so neighbors contrast.
enum ZonePalette {
    static let colors: [Color] = [
        .blue, .orange, .green, .purple, .pink, .teal, .indigo, .yellow, .mint, .red,
    ]

    static func color(_ index: Int) -> Color {
        colors[index % colors.count]
    }
}

// MARK: - Icon Tile

/// A filled rounded square carrying an SF Symbol, as System Settings marks
/// its panes.
struct IconTile: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 20

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.52, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.235, style: .continuous)
                    .fill(color.gradient)
            )
            .accessibilityHidden(true)
    }
}

// MARK: - Pane Header

/// Centered header above a settings pane: large tile, title and one sentence
/// on what the pane is for.
struct PaneHeader: View {
    let symbol: String
    let color: Color
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey

    var body: some View {
        VStack(spacing: 8) {
            IconTile(symbol: symbol, color: color, size: 52)
                .shadow(color: color.opacity(0.25), radius: 6, y: 2)
            Text(title)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.primary)
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
        .padding(.bottom, 10)
        .textCase(nil)
    }
}

// MARK: - Key Caps

/// One key of a shortcut, drawn as a keycap.
struct KeyCap: View {
    let label: String
    var prominent = false

    var body: some View {
        Text(label)
            .font(.system(size: 11.5, weight: .semibold, design: .rounded))
            .foregroundStyle(prominent ? Color.accentColor : .primary)
            .padding(.horizontal, 5)
            .frame(minWidth: 21, minHeight: 21)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .shadow(color: .black.opacity(0.12), radius: 0, y: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
            )
    }
}

/// A shortcut drawn as keycaps, modifiers first: ⌃ ⌥ 4.
struct KeyCaps: View {
    let binding: HotKeyBinding

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(binding.modifierSymbols.enumerated()), id: \.offset) { _, symbol in
                KeyCap(label: String(symbol))
            }
            KeyCap(label: binding.keyName)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(binding.displayString)
    }
}

// MARK: - Zone Map

/// A layout's zones drawn in a display's proportions. Used for thumbnails,
/// pickers and previews, so every place shows the same picture of a layout.
struct ZoneMap: View {
    let zones: [Zone]
    /// Width divided by height of the display the layout is shown for.
    var aspectRatio: CGFloat = 16.0 / 10.0
    /// Space between zones, in points of the thumbnail.
    var spacing: CGFloat = 1.5
    var highlighted: Set<Int> = []
    var showsNumbers = false
    var cornerRadius: CGFloat = 3

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: cornerRadius + 1, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
                RoundedRectangle(cornerRadius: cornerRadius + 1, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.5)

                ForEach(Array(zones.enumerated()), id: \.element.id) { index, zone in
                    let rect = CGRect(
                        x: zone.rect.x * size.width,
                        y: zone.rect.y * size.height,
                        width: zone.rect.width * size.width,
                        height: zone.rect.height * size.height
                    ).insetBy(dx: spacing, dy: spacing)
                    let isHighlighted = highlighted.isEmpty || highlighted.contains(index)
                    let color = ZonePalette.color(index)

                    ZStack {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(color.opacity(isHighlighted ? 0.34 : 0.10))
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(color.opacity(isHighlighted ? 0.95 : 0.35), lineWidth: 1)
                        if showsNumbers {
                            Text(verbatim: "\(index + 1)")
                                .font(.system(size: max(8, min(rect.width, rect.height) * 0.38), weight: .bold, design: .rounded))
                                .foregroundStyle(color.opacity(isHighlighted ? 1 : 0.55))
                                .minimumScaleFactor(0.5)
                        }
                    }
                    .frame(width: max(0, rect.width), height: max(0, rect.height))
                    .offset(x: rect.minX, y: rect.minY)
                }
            }
        }
        .aspectRatio(aspectRatio, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

/// A snap position drawn like a one-zone layout on a 16:10 screen.
struct PositionMap: View {
    let rect: (x: Double, y: Double, w: Double, h: Double)
    var color: Color = .accentColor

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.18), lineWidth: 0.5)
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(color.opacity(0.75))
                    .frame(
                        width: max(0, rect.w * size.width - 3),
                        height: max(0, rect.h * size.height - 3)
                    )
                    .offset(x: rect.x * size.width + 1.5, y: rect.y * size.height + 1.5)
            }
        }
        .aspectRatio(16.0 / 10.0, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

// MARK: - Badge

/// A small capsule label for states such as "In use" or "Default".
struct Badge: View {
    let text: LocalizedStringKey
    var color: Color = .accentColor

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.14)))
    }
}

// MARK: - Inline Notice

/// A one-line status message with an icon, for results and warnings inside a form.
struct InlineNotice: View {
    enum Kind {
        case success, warning, info

        var symbol: String {
            switch self {
            case .success: return "checkmark.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .info: return "info.circle.fill"
            }
        }

        var color: Color {
            switch self {
            case .success: return .green
            case .warning: return .orange
            case .info: return .blue
            }
        }
    }

    let kind: Kind
    let text: String

    var body: some View {
        Label {
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: kind.symbol)
                .foregroundStyle(kind.color)
        }
    }
}
