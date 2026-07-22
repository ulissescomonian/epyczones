import AppKit

// MARK: - Private CGS API Declarations

private typealias CGSConnectionID = UInt32
private typealias CGSSpaceID = UInt64

@_silgen_name("CGSMainConnectionID")
private func CGSMainConnectionID() -> CGSConnectionID

@_silgen_name("CGSGetActiveSpace")
private func CGSGetActiveSpace(_ cid: CGSConnectionID) -> CGSSpaceID

@_silgen_name("CGSManagedDisplayGetCurrentSpace")
private func CGSManagedDisplayGetCurrentSpace(_ cid: CGSConnectionID, _ displayUuid: CFString) -> CGSSpaceID

@_silgen_name("CGSCopyManagedDisplaySpaces")
private func CGSCopyManagedDisplaySpaces(_ cid: CGSConnectionID) -> CFArray

// MARK: - NSScreen Display UUID

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    func displayUUID() -> String? {
        guard let id = displayID,
              let cfUUID = CGDisplayCreateUUIDFromDisplayID(id) else { return nil }
        let str = CFUUIDCreateString(nil, cfUUID.takeRetainedValue()) as String
        return str
    }
}

// MARK: - Space Detector

/// Detects macOS Spaces using private CGS APIs. Space UUIDs are persistent across reboots.
final class SpaceDetector {
    static let shared = SpaceDetector()

    struct SpaceInfo {
        let spaceID: UInt64
        let uuid: String
        let type: Int           // 0 = user desktop, 4 = fullscreen, 5 = tiled
        let displayUUID: String
        let index: Int          // 1-based index within the display (for UI display)
    }

    private let cgsConnection: UInt32

    private init() {
        cgsConnection = CGSMainConnectionID()
    }

    /// Get all user-desktop spaces across all displays.
    func allSpaces() -> [SpaceInfo] {
        let displays = CGSCopyManagedDisplaySpaces(cgsConnection) as! [NSDictionary]
        var result: [SpaceInfo] = []

        for display in displays {
            var displayID = display["Display Identifier"] as? String ?? ""
            if displayID == "Main", let mainUuid = NSScreen.main?.displayUUID() {
                displayID = mainUuid
            }

            let spaces = display["Spaces"] as? [NSDictionary] ?? []
            var userIndex = 0
            for space in spaces {
                let type = space["type"] as? Int ?? -1
                // Only include user desktops (type 0), skip fullscreen (4) and tiled (5)
                guard type == 0 else { continue }
                userIndex += 1

                let spaceID = space["id64"] as? UInt64 ?? 0
                let uuid = space["uuid"] as? String ?? ""

                result.append(SpaceInfo(
                    spaceID: spaceID,
                    uuid: uuid,
                    type: type,
                    displayUUID: displayID,
                    index: userIndex
                ))
            }
        }
        return result
    }

    /// Get the UUID of the current space on a specific screen.
    func currentSpaceUUID(for screen: NSScreen) -> String? {
        guard let displayUuid = screen.displayUUID() else { return nil }
        let spaceID = CGSManagedDisplayGetCurrentSpace(cgsConnection, displayUuid as CFString)
        return allSpaces().first(where: { $0.spaceID == spaceID })?.uuid
    }

    /// Get the UUID of the active space (on the focused display).
    func currentSpaceUUID() -> String? {
        let activeID = CGSGetActiveSpace(cgsConnection)
        return allSpaces().first(where: { $0.spaceID == activeID })?.uuid
    }

    /// Get the SpaceInfo for the current space on a specific screen.
    func currentSpace(for screen: NSScreen) -> SpaceInfo? {
        guard let displayUuid = screen.displayUUID() else { return nil }
        let spaceID = CGSManagedDisplayGetCurrentSpace(cgsConnection, displayUuid as CFString)
        return allSpaces().first(where: { $0.spaceID == spaceID })
    }
}
