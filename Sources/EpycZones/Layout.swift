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

    // MARK: - Templates

    static func twoColumns() -> Layout {
        Layout(name: "2 Columns", zones: [
            Zone(rect: RelativeRect(x: 0, y: 0, width: 0.5, height: 1)),
            Zone(rect: RelativeRect(x: 0.5, y: 0, width: 0.5, height: 1)),
        ])
    }

    static func threeColumns() -> Layout {
        let w = 1.0 / 3.0
        return Layout(name: "3 Columns", zones: [
            Zone(rect: RelativeRect(x: 0, y: 0, width: w, height: 1)),
            Zone(rect: RelativeRect(x: w, y: 0, width: w, height: 1)),
            Zone(rect: RelativeRect(x: w * 2, y: 0, width: w, height: 1)),
        ])
    }

    static func grid2x2() -> Layout {
        Layout(name: "Grid 2×2", zones: [
            Zone(rect: RelativeRect(x: 0, y: 0, width: 0.5, height: 0.5)),
            Zone(rect: RelativeRect(x: 0.5, y: 0, width: 0.5, height: 0.5)),
            Zone(rect: RelativeRect(x: 0, y: 0.5, width: 0.5, height: 0.5)),
            Zone(rect: RelativeRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)),
        ])
    }

    static func priorityRight() -> Layout {
        Layout(name: "Priority Right", zones: [
            Zone(rect: RelativeRect(x: 0, y: 0, width: 1.0 / 3.0, height: 1)),
            Zone(rect: RelativeRect(x: 1.0 / 3.0, y: 0, width: 2.0 / 3.0, height: 1)),
        ])
    }

    static func focusCenter() -> Layout {
        let side = 1.0 / 6.0
        let center = 4.0 / 6.0
        return Layout(name: "Focus Center", zones: [
            Zone(rect: RelativeRect(x: 0, y: 0, width: side, height: 1)),
            Zone(rect: RelativeRect(x: side, y: 0, width: center, height: 1)),
            Zone(rect: RelativeRect(x: side + center, y: 0, width: side, height: 1)),
        ])
    }

    static func twoRows() -> Layout {
        Layout(name: "2 Rows", zones: [
            Zone(rect: RelativeRect(x: 0, y: 0, width: 1, height: 0.5)),
            Zone(rect: RelativeRect(x: 0, y: 0.5, width: 1, height: 0.5)),
        ])
    }
}
