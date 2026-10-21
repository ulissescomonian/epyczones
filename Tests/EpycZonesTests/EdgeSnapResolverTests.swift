import CoreGraphics
import XCTest
@testable import EpycZones

final class EdgeSnapResolverTests: XCTestCase {
    /// 1000 x 800 screen: the corner band is clamp(800 * 0.15, 80, 200) = 120.
    private let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)

    private func position(_ x: CGFloat, _ y: CGFloat, topEdgeMaximizes: Bool = false) -> SnapPosition? {
        EdgeSnapResolver.position(
            at: CGPoint(x: x, y: y),
            in: screen,
            threshold: 30,
            topEdgeMaximizes: topEdgeMaximizes
        )
    }

    func testEdgesSnapToHalves() {
        XCTAssertEqual(position(10, 400), .leftHalf)
        XCTAssertEqual(position(990, 400), .rightHalf)
        XCTAssertEqual(position(500, 795), .topHalf)
        XCTAssertEqual(position(500, 5), .bottomHalf)
    }

    func testCornersSnapToQuarters() {
        XCTAssertEqual(position(10, 790), .topLeftQuarter)
        XCTAssertEqual(position(990, 50), .bottomRightQuarter)
        // Along the bottom edge but inside the left corner band.
        XCTAssertEqual(position(50, 5), .bottomLeftQuarter)
        XCTAssertEqual(position(950, 795), .topRightQuarter)
    }

    func testTopEdgeCanMaximize() {
        XCTAssertEqual(position(500, 795, topEdgeMaximizes: true), .maximize)
        // Corners keep their quarters.
        XCTAssertEqual(position(10, 790, topEdgeMaximizes: true), .topLeftQuarter)
    }

    func testInteriorPointsDoNotSnap() {
        XCTAssertNil(position(500, 400))
        XCTAssertNil(position(31, 400))
    }

    // MARK: - Edges shared with another display

    private func position(_ x: CGFloat, _ y: CGFloat, neighbors: [CGRect]) -> SnapPosition? {
        EdgeSnapResolver.position(
            at: CGPoint(x: x, y: y),
            in: screen,
            threshold: 30,
            topEdgeMaximizes: false,
            neighborFrames: neighbors
        )
    }

    /// A portrait display to the right, taller than this screen.
    private let rightPortrait = CGRect(x: 1000, y: -200, width: 500, height: 1200)

    func testEdgeSharedWithAnotherDisplayDoesNotSnap() {
        XCTAssertNil(position(995, 400, neighbors: [rightPortrait]))
        XCTAssertEqual(position(995, 400, neighbors: []), .rightHalf)
    }

    func testOuterEdgesStillSnapNextToAnotherDisplay() {
        XCTAssertEqual(position(5, 400, neighbors: [rightPortrait]), .leftHalf)
        // The top edge is open, so the top-right corner still gives a quarter.
        XCTAssertEqual(position(995, 795, neighbors: [rightPortrait]), .topRightQuarter)
    }

    func testOnlyTheStretchANeighborCoversIsShared() {
        let shortNeighbor = CGRect(x: 1000, y: 300, width: 400, height: 300)
        XCTAssertNil(position(995, 400, neighbors: [shortNeighbor]))
        XCTAssertEqual(position(995, 700, neighbors: [shortNeighbor]), .rightHalf)
    }

    func testFrameOffsetIsRespected() {
        let secondary = CGRect(x: -1080, y: -400, width: 1080, height: 2560)
        let snapped = EdgeSnapResolver.position(
            at: CGPoint(x: -1075, y: 800),
            in: secondary,
            threshold: 30,
            topEdgeMaximizes: false
        )
        XCTAssertEqual(snapped, .leftHalf)
    }
}
