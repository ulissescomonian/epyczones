import ApplicationServices
import XCTest
@testable import EpycZones

/// Application elements stand in for windows: creating them needs no
/// Accessibility permission and they compare with the same CFEqual rules.
final class WindowStateMapTests: XCTestCase {
    func testSeparatelyCreatedElementsForTheSameObjectShareState() {
        var map = WindowStateMap<Int>()
        map[AXUIElementCreateApplication(4242)] = 7
        XCTAssertEqual(map[AXUIElementCreateApplication(4242)], 7)
        XCTAssertNil(map[AXUIElementCreateApplication(4243)])
    }

    func testAssigningNilRemovesTheEntry() {
        var map = WindowStateMap<Int>()
        let element = AXUIElementCreateApplication(4242)
        map[element] = 1
        map[element] = 2
        XCTAssertEqual(map.count, 1)
        map[element] = nil
        XCTAssertNil(map[element])
        XCTAssertEqual(map.count, 0)
    }

    func testPruneKeepsOnlyLiveWindows() {
        var map = WindowStateMap<String>()
        map[AXUIElementCreateApplication(1001)] = "closed"
        map[AXUIElementCreateApplication(1002)] = "open"

        map.prune { element in
            var pid: pid_t = 0
            AXUIElementGetPid(element, &pid)
            return pid == 1002
        }

        XCTAssertEqual(map.count, 1)
        XCTAssertNil(map[AXUIElementCreateApplication(1001)])
        XCTAssertEqual(map[AXUIElementCreateApplication(1002)], "open")
    }
}
