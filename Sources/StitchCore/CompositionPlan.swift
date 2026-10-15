import Foundation

public struct SegmentRange: Sendable, Equatable {
    public let start: Int
    public let end: Int
    public var height: Int { end - start }
}

public enum CompositionPlan {
    /// Insets describe fixed UI inside the sequence. Keep the first header and
    /// last footer; every internal seam joins only the scrolling content.
    /// Clamp all edits so a segment always contributes at least one row.
    public static func ranges(heights: [Int], top: Int, bottom: Int,
                              overlaps: [Int], endCuts: [Int]) -> [SegmentRange] {
        heights.enumerated().map { index, height in
            let lowerBound = index == 0 ? 0 : max(0, min(top, height - 1))
            let upperBound = max(lowerBound + 1, height - (index == heights.count - 1 ? 0 : max(0, bottom)))
            let overlap = index > 0 && index - 1 < overlaps.count ? max(0, overlaps[index - 1]) : 0
            let endCut = index < endCuts.count ? max(0, endCuts[index]) : 0
            let start = min(upperBound - 1, lowerBound + overlap)
            let end = max(start + 1, upperBound - endCut)
            return SegmentRange(start: start, end: end)
        }
    }
}
