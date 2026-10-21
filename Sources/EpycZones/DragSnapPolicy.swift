/// Which snap UI a drag gesture may show.
enum DragSnapMode: Equatable {
    case none
    /// Shift + drag: the active layout's zones.
    case zones
    /// Plain drag near a screen edge: the half or quarter preview.
    case edge
}

/// Decides the snap UI for the current drag event.
///
/// Only a gesture that actually moves a window may snap. Shift is also how
/// apps extend a text selection, select files or constrain a shape, so Shift
/// alone must never show zones or snap the focused window on mouse up.
enum DragSnapPolicy {
    static func mode(
        windowIsMoving: Bool,
        shiftHeld: Bool,
        suppressed: Bool,
        edgeSnapEnabled: Bool
    ) -> DragSnapMode {
        guard windowIsMoving, !suppressed else { return .none }
        if shiftHeld { return .zones }
        return edgeSnapEnabled ? .edge : .none
    }
}
