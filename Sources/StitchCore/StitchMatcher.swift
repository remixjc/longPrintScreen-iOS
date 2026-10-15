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
        guard upper.width == lower.width, min(upper.height, lower.height) >= 24 else { return .none }
        let minOverlap = max(16, min(upper.height, lower.height) / 14)
        let maxOverlap = min(upper.height - 8, lower.height - 8)
        guard maxOverlap >= minOverlap else { return .none }
        var candidates: [(Int, Double)] = []
        let coarseStep = max(1, min(upper.height, lower.height) / 180)
        for overlap in stride(from: minOverlap, through: maxOverlap, by: coarseStep) {
            candidates.append((overlap, difference(upper, lower, overlap: overlap)))
        }
        let seeds = candidates.sorted { $0.1 < $1.1 }.prefix(8)
        var refined: [Int: Double] = [:]
        for (seed, _) in seeds {
            for overlap in max(minOverlap, seed - coarseStep)...min(maxOverlap, seed + coarseStep) {
                refined[overlap] = difference(upper, lower, overlap: overlap)
            }
        }
        let sorted = refined.sorted { $0.value < $1.value }
        guard let best = sorted.first else { return .none }
        let detail = texture(lower, rows: best.key)
        guard detail > 0.018, best.value < 0.105 else { return .none }
        // Adjacent offsets are naturally similar; distant alternatives indicate ambiguity.
        let distant = candidates.filter { abs($0.0 - best.key) > max(5, coarseStep * 2) }
            .map(\.1).min() ?? 1
        let separation = max(0, min(1, (distant - best.value) / 0.045))
        let accuracy = max(0, 1 - best.value / 0.105)
        let confidence = min(1, accuracy * (0.65 + separation * 0.35))
        return OverlapMatch(overlap: best.key, confidence: confidence, error: best.value)
    }

    private static func difference(_ a: PixelGrid, _ b: PixelGrid, overlap: Int) -> Double {
        var sum = 0.0
        var count = 0
        let rowStep = max(1, overlap / 60)
        // Ignore outer margins, where scroll indicators and floating UI often live.
        let margin = max(1, a.width / 10)
        for row in stride(from: 0, to: overlap, by: rowStep) {
            let aStart = (a.height - overlap + row) * a.width
            let bStart = row * b.width
            for column in margin..<(a.width - margin) {
                sum += Double(abs(Int(a.pixels[aStart + column]) - Int(b.pixels[bStart + column])))
                count += 1
            }
        }
        return count > 0 ? sum / Double(count) / 255 : 1
    }

    private static func texture(_ grid: PixelGrid, rows: Int) -> Double {
        var value = 0.0
        var count = 0
        let step = max(1, rows / 60)
        for row in stride(from: 1, to: rows, by: step) {
            for x in 1..<grid.width {
                let index = row * grid.width + x
                value += Double(abs(Int(grid.pixels[index]) - Int(grid.pixels[index - grid.width])))
                count += 1
            }
        }
        return count > 0 ? value / Double(count) / 255 : 0
    }

    public static func fixedInsets(_ grids: [PixelGrid]) -> (top: Int, bottom: Int) {
        guard let first = grids.first, grids.count > 1,
              grids.allSatisfy({ $0.width == first.width && $0.height == first.height }) else { return (0, 0) }
        // A duplicate alone cannot prove a fixed header: skip duplicates.
        let others = grids.dropFirst().filter { meanDifference(first, $0) > 0.01 }
        guard !others.isEmpty else { return (0, 0) }
        func isFixed(_ row: Int) -> Bool {
            others.allSatisfy { other in
                var error = 0
                let margin = max(1, first.width / 8)
                for x in margin..<(first.width - margin) {
                    error += abs(Int(first.pixels[row * first.width + x]) - Int(other.pixels[row * first.width + x]))
                }
                return Double(error) / Double(first.width - 2 * margin) / 255 < 0.018
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
        for i in 0..<n {
            for j in 0..<n where i != j && (automatic || j == i + 1) {
                matrix[i][j] = match(grids[i], grids[j])
            }
        }
        let original = Array(0..<n)
        let originalMatches = (0..<(n - 1)).map { matrix[$0][$0 + 1] }
        guard automatic, n <= 24 else {
            return OrderingResult(indices: original, matches: originalMatches, changed: false,
                                  reliable: originalMatches.allSatisfy(\.isReliable))
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
