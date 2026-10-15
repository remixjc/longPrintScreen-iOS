import Foundation

/// Small grayscale images keep matching deterministic, bounded and independent of UIKit.
public struct PixelGrid: Sendable {
    public let width: Int
    public let height: Int
    public let pixels: [UInt8]

    public init(width: Int, height: Int, pixels: [UInt8]) {
        precondition(width > 0 && height > 0 && pixels.count == width * height)
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    public func cropped(top: Int, bottom: Int) -> PixelGrid {
        let start = max(0, min(top, height - 1))
        let end = max(start + 1, height - max(0, bottom))
        return PixelGrid(width: width, height: end - start,
                         pixels: Array(pixels[(start * width)..<(end * width)]))
    }
}

public struct OverlapMatch: Sendable, Equatable {
    public let overlap: Int
    public let confidence: Double
    public let error: Double
    public var isReliable: Bool { overlap > 0 && confidence >= 0.72 }
    public static let none = OverlapMatch(overlap: 0, confidence: 0, error: 1)
}

public struct OrderingResult: Sendable {
    public let indices: [Int]
    public let matches: [OverlapMatch]
    public let changed: Bool
    public let reliable: Bool
}

public enum StitchMatcher {
    /// Compares the lower part of a screenshot with the upper part of the next.
    /// Flat or repeated content cannot establish a reliable scrolling offset.
    public static func match(_ upper: PixelGrid, _ lower: PixelGrid) -> OverlapMatch {
        guard upper.width == lower.width, upper.width >= 4,
              min(upper.height, lower.height) >= 24 else { return .none }
        let minOverlap = max(16, min(upper.height, lower.height) / 14)
        let maxOverlap = min(upper.height - 8, lower.height - 8)
        guard maxOverlap >= minOverlap else { return .none }
        var candidates: [(Int, Double)] = []
        let a = rowProfiles(upper), b = rowProfiles(lower)
        // Search every row. Skipping offsets can miss the only alignment of
        // thin text strokes; compact row profiles make this search inexpensive.
        for overlap in minOverlap...maxOverlap {
            var error = 0.0
            for row in stride(from: 0, to: overlap, by: max(1, overlap / 60)) {
                for bin in 0..<16 {
                    error += abs(a[(upper.height - overlap + row) * 16 + bin] - b[row * 16 + bin])
                }
            }
            candidates.append((overlap, error / Double((overlap + max(1, overlap / 60) - 1) / max(1, overlap / 60))))
        }
        var seeds: [Int] = []
        for candidate in candidates.sorted(by: { $0.1 < $1.1 }) {
            if seeds.allSatisfy({ abs($0 - candidate.0) > 3 }) { seeds.append(candidate.0) }
            if seeds.count == 16 { break }
        }
        var refined: [Int: Double] = [:]
        for seed in seeds {
            for overlap in max(minOverlap, seed - 2)...min(maxOverlap, seed + 2) {
                refined[overlap] = difference(upper, lower, overlap: overlap)
            }
        }
        // Recheck the strongest candidates using every row. Periodic text line
        // spacing must not alias against the sampling interval.
        var finalists: [Int] = []
        for candidate in refined.sorted(by: { $0.value < $1.value }) {
            if finalists.allSatisfy({ abs($0 - candidate.key) > 5 }) { finalists.append(candidate.key) }
            if finalists.count == 8 { break }
        }
        finalists = Array(Set(finalists.flatMap {
            Array(max(minOverlap, $0 - 2)...min(maxOverlap, $0 + 2))
        })).sorted()
        for candidate in finalists {
            refined[candidate] = difference(upper, lower, overlap: candidate, everyRow: true)
        }
        let sorted = finalists.map { (key: $0, value: refined[$0]!) }.sorted { $0.value < $1.value }
        guard let best = sorted.first else { return .none }
        guard best.value < 0.38 else { return .none }
        // Adjacent offsets are naturally similar; distant alternatives indicate ambiguity.
        let distant = sorted.filter { abs($0.key - best.key) > 5 }
            .map(\.value).min() ?? 1
        // Measure separation relative to the content's contrast. Sparse dark
        // glyphs on white have tiny absolute errors even at the wrong offset.
        let separation = max(0, min(1, (distant - best.value) / max(0.015, distant)))
        let accuracy = max(0, 1 - best.value)
        let confidence = min(1, accuracy * (0.65 + separation * 0.35))
        return OverlapMatch(overlap: best.key, confidence: confidence, error: best.value)
    }

    private static func rowProfiles(_ grid: PixelGrid) -> [Double] {
        var result = [Double](repeating: 0, count: grid.height * 16)
        let margin = max(1, grid.width / 10)
        for y in 0..<grid.height {
            for bin in 0..<8 {
                let start = margin + (grid.width - 2 * margin) * bin / 8
                let end = max(start + 1, margin + (grid.width - 2 * margin) * (bin + 1) / 8)
                var sum = 0, edges = 0
                for x in start..<end {
                    let value = Int(grid.pixels[y * grid.width + x])
                    sum += value
                    edges += abs(value - Int(grid.pixels[y * grid.width + max(0, x - 1)]))
                }
                result[y * 16 + bin * 2] = Double(sum) / Double(end - start)
                result[y * 16 + bin * 2 + 1] = Double(edges) / Double(end - start)
            }
        }
        return result
    }

    private static func difference(_ a: PixelGrid, _ b: PixelGrid, overlap: Int, everyRow: Bool = false) -> Double {
        var sum = 0.0
        var detail = 0.0
        var count = 0
        let rowStep = everyRow ? 1 : max(1, overlap / 90)
        // Ignore outer margins, where scroll indicators and floating UI often live.
        let margin = max(1, a.width / 10)
        for row in stride(from: 0, to: overlap, by: rowStep) {
            let aStart = (a.height - overlap + row) * a.width
            let bStart = row * b.width
            for column in stride(from: margin, to: a.width - margin, by: max(1, a.width / 64)) {
                let ai = aStart + column, bi = bStart + column
                let av = Int(a.pixels[ai]), bv = Int(b.pixels[bi])
                sum += Double(abs(av - bv))
                let ah = abs(av - Int(a.pixels[ai - 1]))
                let bh = abs(bv - Int(b.pixels[bi - 1]))
                let verticalA = ai >= a.width ? abs(av - Int(a.pixels[ai - a.width])) : 0
                let verticalB = bi >= b.width ? abs(bv - Int(b.pixels[bi - b.width])) : 0
                detail += Double(max(ah, bh) + max(verticalA, verticalB))
                count += 1
            }
        }
        guard count > 0, detail / Double(count) > 0.5 else { return 1 }
        return sum / detail
    }

    /// Resolve the coarse estimate at output-row precision so a downsampled
    /// match does not duplicate or omit a few rows of text at each seam.
    public static func refine(_ upper: PixelGrid, _ lower: PixelGrid,
                              overlap: Int, radius: Int) -> Int {
        guard upper.width == lower.width, upper.width >= 4 else { return overlap }
        let start = max(8, overlap - radius)
        let end = min(min(upper.height, lower.height) - 1, overlap + radius)
        guard start <= end else { return overlap }
        var best = overlap, error = Double.infinity
        for candidate in start...end {
            let value = difference(upper, lower, overlap: candidate, everyRow: true)
            if value < error { best = candidate; error = value }
        }
        return best
    }

    public static func fixedInsets(_ grids: [PixelGrid]) -> (top: Int, bottom: Int) {
        guard let first = grids.first, first.width >= 4, grids.count > 1,
              grids.allSatisfy({ $0.width == first.width && $0.height == first.height }) else { return (0, 0) }
        // A duplicate alone cannot prove a fixed header: skip duplicates.
        let others = grids.dropFirst().filter { meanDifference(first, $0) > 0.001 }
        guard !others.isEmpty else { return (0, 0) }
        func isFixed(_ row: Int) -> Bool {
            others.allSatisfy { other in
                var differences: [Int] = []
                let margin = max(1, first.width / 8)
                for x in margin..<(first.width - margin) {
                    differences.append(abs(Int(first.pixels[row * first.width + x]) - Int(other.pixels[row * first.width + x])))
                }
                // Clocks, battery indicators and badges may change inside fixed
                // UI. Ignore localized differences instead of stopping at them.
                let kept = differences.sorted().prefix(max(1, differences.count * 4 / 5))
                return Double(kept.reduce(0, +)) / Double(kept.count) / 255 < 0.012
            }
        }
        var top = 0
        var bottom = 0
        let limit = first.height / 4
        while top < limit && isFixed(top) { top += 1 }
        while bottom < limit && isFixed(first.height - 1 - bottom) { bottom += 1 }
        // A full quarter may be uniform page background, not UI chrome.
        return (top == limit ? 0 : top, bottom == limit ? 0 : bottom)
    }

    public static func meanDifference(_ a: PixelGrid, _ b: PixelGrid) -> Double {
        guard a.width == b.width, a.height == b.height else { return 1 }
        var error = 0.0
        let step = max(1, a.pixels.count / 4000)
        for index in stride(from: 0, to: a.pixels.count, by: step) {
            error += Double(abs(Int(a.pixels[index]) - Int(b.pixels[index])))
        }
        return error / Double((a.pixels.count + step - 1) / step) / 255
    }

    /// A bounded beam search finds a directed path. Only a fully reliable chain
    /// may reorder user selections; disconnected or ambiguous sets retain input order.
    public static func order(_ grids: [PixelGrid], automatic: Bool) -> OrderingResult {
        let n = grids.count
        guard n > 1 else { return OrderingResult(indices: Array(0..<n), matches: [], changed: false, reliable: true) }
        var matrix = Array(repeating: Array(repeating: OverlapMatch.none, count: n), count: n)
        for i in 0..<(n - 1) {
            matrix[i][i + 1] = match(grids[i], grids[i + 1])
        }
        let original = Array(0..<n)
        let originalMatches = (0..<(n - 1)).map { matrix[$0][$0 + 1] }
        // Merely plausible edges can occur between repeated text layouts.
        // Skip the order search only for near-exact original alignments.
        if originalMatches.allSatisfy({ $0.isReliable && $0.confidence >= 0.98 }) {
            return OrderingResult(indices: original, matches: originalMatches, changed: false, reliable: true)
        }
        guard automatic, n <= 24 else {
            return OrderingResult(indices: original, matches: originalMatches, changed: false,
                                  reliable: originalMatches.allSatisfy(\.isReliable))
        }
        for i in 0..<n {
            for j in 0..<n where i != j && j != i + 1 {
                matrix[i][j] = match(grids[i], grids[j])
            }
        }
        struct Path { var indices: [Int]; var score: Double }
        var paths = (0..<n).map { Path(indices: [$0], score: 0) }
        for _ in 1..<n {
            var next: [Path] = []
            for path in paths {
                let tail = path.indices.last!
                for target in 0..<n where !path.indices.contains(target) {
                    let edge = matrix[tail][target]
                    guard edge.isReliable else { continue }
                    next.append(Path(indices: path.indices + [target], score: path.score + edge.confidence))
                }
            }
            paths = Array(next.sorted {
                if abs($0.score - $1.score) < 0.0001 {
                    return $0.indices.lexicographicallyPrecedes($1.indices)
                }
                return $0.score > $1.score
            }.prefix(64))
            if paths.isEmpty { break }
        }
        guard let best = paths.first, best.indices.count == n else {
            return OrderingResult(indices: original, matches: originalMatches, changed: false,
                                  reliable: originalMatches.allSatisfy(\.isReliable))
        }
        // Equally good full paths cannot establish a unique order.
        if paths.count > 1, best.score - paths[1].score < 0.04 {
            return OrderingResult(indices: original, matches: originalMatches, changed: false,
                                  reliable: originalMatches.allSatisfy(\.isReliable))
        }
        let edges = (0..<(n - 1)).map { matrix[best.indices[$0]][best.indices[$0 + 1]] }
        return OrderingResult(indices: best.indices, matches: edges,
                              changed: best.indices != original, reliable: true)
    }
}
