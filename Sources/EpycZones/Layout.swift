import Foundation

/// A named collection of zones that defines a window arrangement.
struct Layout: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var zones: [Zone]

    init(id: UUID = UUID(), name: String, zones: [Zone]) {
        self.id = id
        self.name = name
        self.zones = zones
    }

    var isTemplate: Bool {
        LayoutTemplate.allCases.contains { $0.id == id }
    }

    /// The built-in template with this kind.
    static func template(_ kind: LayoutTemplate) -> Layout {
        templates[kind.rawValue]
    }

    /// Ready-made layouts that ship with the app. They are never stored or
    /// copied when used: displays refer to them by their fixed identifiers,
    /// and editing one creates a named copy.
    static let templates: [Layout] = LayoutTemplate.allCases.map(\.layout)
}

// MARK: - Built-in Templates

/// The built-in layouts. Identifiers derive from the raw value and are saved
/// in assignments, so cases may be appended but never reordered or removed.
enum LayoutTemplate: Int, CaseIterable {
    case twoColumns
    case threeColumns
    case grid
    case focusCenter
    case priorityLeft
    case priorityRight
    case mainAndStack
    case twoRows
    case threeRows

    var id: UUID { Self.identifier(self.rawValue, zone: 0) }

    var name: String {
        switch self {
        case .twoColumns:    return String(localized: "2 Columns")
        case .threeColumns:  return String(localized: "3 Columns")
        case .grid:          return String(localized: "Grid 2×2")
        case .focusCenter:   return String(localized: "Focus Center")
        case .priorityLeft:  return String(localized: "Priority Left")
        case .priorityRight: return String(localized: "Priority Right")
        case .mainAndStack:  return String(localized: "Main and Stack")
        case .twoRows:       return String(localized: "2 Rows")
        case .threeRows:     return String(localized: "3 Rows")
        }
    }

    private var rects: [RelativeRect] {
        let third = 1.0 / 3.0
        switch self {
        case .twoColumns:
            return [
                RelativeRect(x: 0, y: 0, width: 0.5, height: 1),
                RelativeRect(x: 0.5, y: 0, width: 0.5, height: 1),
            ]
        case .threeColumns:
            return [
                RelativeRect(x: 0, y: 0, width: third, height: 1),
                RelativeRect(x: third, y: 0, width: third, height: 1),
                RelativeRect(x: third * 2, y: 0, width: third, height: 1),
            ]
        case .grid:
            return [
                RelativeRect(x: 0, y: 0, width: 0.5, height: 0.5),
                RelativeRect(x: 0.5, y: 0, width: 0.5, height: 0.5),
                RelativeRect(x: 0, y: 0.5, width: 0.5, height: 0.5),
                RelativeRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5),
            ]
        case .focusCenter:
            return [
                RelativeRect(x: 0, y: 0, width: 1.0 / 6.0, height: 1),
                RelativeRect(x: 1.0 / 6.0, y: 0, width: 4.0 / 6.0, height: 1),
                RelativeRect(x: 5.0 / 6.0, y: 0, width: 1.0 / 6.0, height: 1),
            ]
        case .priorityLeft:
            return [
                RelativeRect(x: 0, y: 0, width: third * 2, height: 1),
                RelativeRect(x: third * 2, y: 0, width: third, height: 1),
            ]
        case .priorityRight:
            return [
                RelativeRect(x: 0, y: 0, width: third, height: 1),
                RelativeRect(x: third, y: 0, width: third * 2, height: 1),
            ]
        case .mainAndStack:
            return [
                RelativeRect(x: 0, y: 0, width: third * 2, height: 1),
                RelativeRect(x: third * 2, y: 0, width: third, height: 0.5),
                RelativeRect(x: third * 2, y: 0.5, width: third, height: 0.5),
            ]
        case .twoRows:
            return [
                RelativeRect(x: 0, y: 0, width: 1, height: 0.5),
                RelativeRect(x: 0, y: 0.5, width: 1, height: 0.5),
            ]
        case .threeRows:
            return [
                RelativeRect(x: 0, y: 0, width: 1, height: third),
                RelativeRect(x: 0, y: third, width: 1, height: third),
                RelativeRect(x: 0, y: third * 2, width: 1, height: third),
            ]
        }
    }

    var layout: Layout {
        Layout(
            id: id,
            name: name,
            zones: rects.enumerated().map { index, rect in
                Zone(id: Self.identifier(rawValue, zone: index + 1), rect: rect)
            }
        )
    }

    /// Fixed identifiers for a template (zone 0) and its zones.
    private static func identifier(_ template: Int, zone: Int) -> UUID {
        UUID(uuidString: String(format: "EC%06X-0000-4000-8000-%012X", template + 1, zone))!
    }
}
