import XCTest
@testable import StitchCore

final class StitchCoreTests: XCTestCase {
    func page(start: Int, height: Int = 220, header: Int = 0, footer: Int = 0) -> PixelGrid {
        let width = 32
        var pixels: [UInt8] = []
        for y in 0..<height {
            for x in 0..<width {
                if y < header || y >= height - footer {
                    pixels.append(UInt8(20 + x * 2))
                } else {
                    let row = y - header + start
                    var value = UInt64(row * 100 + x + 1)
                    value = (value ^ (value >> 30)) &* 0xbf58476d1ce4e5b9
                    value = (value ^ (value >> 27)) &* 0x94d049bb133111eb
                    pixels.append(UInt8(truncatingIfNeeded: value ^ (value >> 31)))
                }
            }
        }
        return PixelGrid(width: width, height: height, pixels: pixels)
    }

    func testExactScrollOverlap() {
        let match = StitchMatcher.match(page(start: 0), page(start: 130))
        XCTAssertEqual(match.overlap, 90)
        XCTAssertTrue(match.isReliable)
    }

    func testRecoverShuffledOrder() {
        let result = StitchMatcher.order([page(start: 260), page(start: 0), page(start: 130)], automatic: true)
        XCTAssertEqual(result.indices, [1, 2, 0])
        XCTAssertTrue(result.changed)
        XCTAssertTrue(result.reliable)
    }

    func testManualOrderRemainsUnchanged() {
        let result = StitchMatcher.order([page(start: 130), page(start: 0)], automatic: false)
        XCTAssertEqual(result.indices, [0, 1])
        XCTAssertFalse(result.changed)
    }

    func testDisconnectedImagesKeepSelectionOrder() {
        let result = StitchMatcher.order([page(start: 0), page(start: 310), page(start: 680)], automatic: true)
        XCTAssertEqual(result.indices, [0, 1, 2])
        XCTAssertFalse(result.reliable)
    }

    func testFlatImagesNeverPretendToMatch() {
        let blank = PixelGrid(width: 32, height: 220, pixels: Array(repeating: 240, count: 32 * 220))
        XCTAssertFalse(StitchMatcher.match(blank, blank).isReliable)
    }

    func testFixedChromeDetectionAndMatching() {
        let grids = [page(start: 0, header: 22, footer: 18), page(start: 120, header: 22, footer: 18)]
        let insets = StitchMatcher.fixedInsets(grids)
        XCTAssertEqual(insets.top, 22)
        XCTAssertEqual(insets.bottom, 18)
        let match = StitchMatcher.match(grids[0].cropped(top: 22, bottom: 18), grids[1].cropped(top: 22, bottom: 18))
        XCTAssertEqual(match.overlap, 60)
        XCTAssertTrue(match.isReliable)
    }

    func testCaptureDeduplicatesAndLimitsFrames() {
        var policy = CapturePolicy(limit: 2)
        XCTAssertTrue(policy.shouldCapture(page(start: 0)))
        XCTAssertFalse(policy.shouldCapture(page(start: 0)))
        XCTAssertTrue(policy.shouldCapture(page(start: 130)))
        XCTAssertFalse(policy.shouldCapture(page(start: 260)))
        XCTAssertEqual(policy.count, 2)
    }

    func testCompositionClampsMalformedEdits() {
        let result = CompositionPlan.ranges(heights: [100, 100, 80], top: 10, bottom: 10,
                                            overlaps: [200, -20], endCuts: [500, 0])
        XCTAssertEqual(result, [SegmentRange(start: 10, end: 11), SegmentRange(start: 89, end: 90),
                                SegmentRange(start: 10, end: 70)])
    }
}
