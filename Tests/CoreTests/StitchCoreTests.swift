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
        XCTAssertEqual(result.indices, [1, 2, 0], "\(result.matches)")
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
        XCTAssertEqual(result, [SegmentRange(start: 0, end: 1), SegmentRange(start: 89, end: 90),
                                SegmentRange(start: 10, end: 80)])
    }

    func testCompositionKeepsOnlyOuterHeaderAndFooter() {
        let ranges = CompositionPlan.ranges(heights: [800, 800, 800], top: 100, bottom: 80,
                                             overlaps: [220, 220], endCuts: [0, 0])
        XCTAssertEqual(ranges, [SegmentRange(start: 0, end: 720),
                                SegmentRange(start: 320, end: 720),
                                SegmentRange(start: 320, end: 800)])
        XCTAssertEqual(ranges.map(\.height).reduce(0, +), 1600)
    }

    /// Sparse text strokes on white used to fail the absolute texture/separation thresholds.
    private func textPage(start: Int, changingClock: Int = 0) -> PixelGrid {
        let width = 128, height = 800, header = 90, footer = 70
        var pixels = [UInt8](repeating: 255, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                if y < header || y >= height - footer {
                    if y == header - 1 || y == height - footer { pixels[y * width + x] = 190 }
                    if (20..<26).contains(y), (18 + changingClock..<25 + changingClock).contains(x) {
                        pixels[y * width + x] = 20
                    }
                } else {
                    let row = y - header + start
                    let line = row / 31, localY = row % 31
                    if localY >= 4 && localY < 10 && x > 12 && x < 100 - line % 29 {
                        let glyph = (x - 13) / 4
                        if (x + localY + (line * 17 + glyph * 7) % 11) % 4 == 0 {
                            pixels[y * width + x] = 70
                        }
                    }
                }
            }
        }
        return PixelGrid(width: width, height: height, pixels: pixels)
    }

    func testSparseTextWithChangingClockRemovesOverlap() {
        let grids = [textPage(start: 0), textPage(start: 387, changingClock: 2),
                     textPage(start: 774, changingClock: 4)]
        let insets = StitchMatcher.fixedInsets(grids)
        XCTAssertGreaterThanOrEqual(insets.top, 90)
        XCTAssertGreaterThanOrEqual(insets.bottom, 70)
        let cropped = grids.map { $0.cropped(top: insets.top, bottom: insets.bottom) }
        let result = StitchMatcher.order([cropped[2], cropped[0], cropped[1]], automatic: true)
        XCTAssertEqual(result.indices, [1, 2, 0])
        XCTAssertTrue(result.reliable)
        for match in result.matches {
            XCTAssertEqual(match.overlap, 800 - insets.top - insets.bottom - 387)
        }
    }

    func testRepeatedRowsCannotEstablishUniqueScrollPosition() {
        let pixels = (0..<(128 * 800)).map { index -> UInt8 in
            let y = index / 128, x = index % 128
            return (y % 30 < 6 && x > 20 && x < 100 && x % 3 == 0) ? 20 : 255
        }
        let repeated = PixelGrid(width: 128, height: 800, pixels: pixels)
        XCTAssertFalse(StitchMatcher.match(repeated, repeated).isReliable)
    }
}
