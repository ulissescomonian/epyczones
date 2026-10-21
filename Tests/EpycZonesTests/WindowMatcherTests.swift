import XCTest
@testable import EpycZones

final class WindowMatcherTests: XCTestCase {
    private func window(_ bundleID: String, _ title: String) -> WindowMatcher.Window {
        WindowMatcher.Window(bundleID: bundleID, title: title)
    }

    func testSavedWindowMatchesTheOpenWindowWithTheSameAppAndTitle() {
        let saved = [window("com.apple.Notes", "Groceries")]
        let open = [window("com.apple.Notes", "Ideas"), window("com.apple.Notes", "Groceries")]
        XCTAssertEqual(WindowMatcher.match(saved: saved, open: open), [0: 1])
    }

    func testDifferentTitleOrAppDoesNotMatch() {
        let saved = [window("com.apple.Notes", "Groceries")]
        let open = [window("com.apple.Notes", "Ideas"), window("com.apple.TextEdit", "Groceries")]
        XCTAssertEqual(WindowMatcher.match(saved: saved, open: open), [:])
    }

    /// 1.0 restored an untitled record onto the app's first window, whatever it was.
    func testUntitledEntryNeedsTheAppsOnlyWindow() {
        let saved = [window("com.example.Tool", "")]
        XCTAssertEqual(
            WindowMatcher.match(saved: saved, open: [window("com.example.Tool", "Main")]),
            [0: 0]
        )
        XCTAssertEqual(
            WindowMatcher.match(
                saved: saved,
                open: [window("com.example.Tool", "Main"), window("com.example.Tool", "Inspector")]
            ),
            [:]
        )
    }

    func testEachOpenWindowIsUsedOnce() {
        let saved = [window("com.apple.Terminal", "zsh"), window("com.apple.Terminal", "zsh")]
        let open = [window("com.apple.Terminal", "zsh"), window("com.apple.Terminal", "zsh")]
        XCTAssertEqual(WindowMatcher.match(saved: saved, open: open), [0: 0, 1: 1])

        let oneOpen = [window("com.apple.Terminal", "zsh")]
        XCTAssertEqual(WindowMatcher.match(saved: saved, open: oneOpen), [0: 0])
    }

    func testTitledMatchesAreServedBeforeUntitledOnes() {
        // The untitled entry must not take the only window a titled entry needs.
        let saved = [window("com.example.Tool", ""), window("com.example.Tool", "Main")]
        let open = [window("com.example.Tool", "Main")]
        XCTAssertEqual(WindowMatcher.match(saved: saved, open: open), [1: 0])
    }
}
