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
    /// A safe join row in the lower image, when an overlay obscures the edges.
    public let seam: Int?
    public init(overlap: Int, confidence: Double, error: Double, seam: Int? = nil) {
        self.overlap = overlap
        self.confidence = confidence
        self.error = error
        self.seam = seam
    }
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
    public static func match(_ upper: PixelGrid, _ lower: PixelGrid, allowOcclusion: Bool = true) -> OverlapMatch {
        let edge = edgeMatch(upper, lower)
        if edge.isReliable || !allowOcclusion { return edge }
        return contentMatch(upper, lower)
    }

    private static func edgeMatch(_ upper: PixelGrid, _ lower: PixelGrid) -> OverlapMatch {
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

    /// Vote for a translation using textured rows inside the images. Unlike
    /// suffix/prefix comparison, this tolerates translucent bars and rounded
    /// sheets covering both ends of the otherwise shared scrolling content.
    private static func contentMatch(_ upper: PixelGrid, _ lower: PixelGrid) -> OverlapMatch {
        guard upper.width == lower.width, upper.width >= 16,
              min(upper.height, lower.height) >= 80 else { return .none }
        let a = rowProfiles(upper), b = rowProfiles(lower)
        let minimum = max(24, min(upper.height, lower.height) / 50)
        var texturedRows: [Int] = []
        for row in 0..<lower.height {
            var texture = 0.0
            for bin in 0..<8 { texture += b[row * 16 + bin * 2 + 1] }
            if texture > 4 { texturedRows.append(row) }
        }
        guard !texturedRows.isEmpty else { return .none }
        let anchorCount = min(160, texturedRows.count)
        let anchors: [Int] = (0..<anchorCount).map { index in
            texturedRows[index * texturedRows.count / anchorCount]
        }
        var candidates: [(shift: Int, votes: Double)] = []
        for shift in 8...(upper.height - minimum) {
            let height = min(upper.height - shift, lower.height)
            var votes = 0.0
            for row in anchors {
                if row >= height { break }
                var error = 0.0, texture = 0.0
                for bin in 0..<8 {
                    let ai = (row + shift) * 16 + bin * 2, bi = row * 16 + bin * 2
                    error += abs(a[ai] - b[bi]) + abs(a[ai + 1] - b[bi + 1])
                    if error >= 10 { break }
                    texture += max(a[ai + 1], b[bi + 1])
                }
                if texture > 4, error < 10 {
                    votes += min(4, texture / 8) * max(0, 1 - error / 10)
                }
            }
            candidates.append((shift, votes))
        }
        var seeds: [Int] = []
        for candidate in candidates.sorted(by: { $0.votes > $1.votes }) {
            if seeds.allSatisfy({ abs($0 - candidate.shift) > 5 }) { seeds.append(candidate.shift) }
            if seeds.count == 12 { break }
        }
        struct Band {
            var shift: Int
            var start: Int
            var end: Int
            var support: Int
            var error: Double
            var score: Double { Double(support) * max(0, 1 - error) }
        }
        var bands: [Band] = []
        // Retain leading list numbers and timestamps: they often distinguish
        // repeated paragraphs. Only the narrow scroll-indicator edge is ignored.
        let margin = max(1, upper.width / 40)
        for shift in Set(seeds.flatMap { Array(max(8, $0 - 1)...min(upper.height - minimum, $0 + 1)) }) {
            let height = min(upper.height - shift, lower.height)
            var start = 0, support = 0, errorSum = 0.0, detailSum = 0.0
            func finish(_ end: Int) {
                guard support >= minimum, end - start >= minimum else { return }
                // Occlusions belong to screen edges. A repeated sentence in
                // the middle is not evidence that the rest of the overlap
                // matches. Require the band to cover the unobscured interval.
                guard start <= lower.height / 3,
                      end >= height - upper.height / 6 else { return }
                bands.append(Band(shift: shift, start: start, end: end, support: support,
                                  error: errorSum / max(1, detailSum)))
            }
            for row in 0..<height {
                var error = 0.0, detail = 0.0, largestError = 0
                let ai = (row + shift) * upper.width, bi = row * lower.width
                for x in margin..<(upper.width - margin) {
                    let av = Int(upper.pixels[ai + x]), bv = Int(lower.pixels[bi + x])
                    error += Double(abs(av - bv))
                    largestError = max(largestError, abs(av - bv))
                    if largestError >= 16 { break }
                    detail += Double(max(abs(av - Int(upper.pixels[ai + x - 1])),
                                         abs(bv - Int(lower.pixels[bi + x - 1]))))
                }
                let count = Double(upper.width - 2 * margin)
                // Flat matching rows may connect a band, but cannot prove it.
                if largestError < 16, error / count < max(1.5, detail / count * 0.22) {
                    if detail / count > 0.6 { support += 1 }
                    errorSum += error
                    detailSum += detail
                } else {
                    finish(row)
                    start = row + 1; support = 0; errorSum = 0; detailSum = 0
                }
            }
            finish(height)
        }
        let sorted = bands.sorted { $0.score > $1.score }
        guard let best = sorted.first, best.error < 0.22 else { return .none }
        let alternative = sorted.first { abs($0.shift - best.shift) > 5 }?.score ?? 0
        let separation = max(0, 1 - alternative / best.score)
        let confidence = (1 - best.error) * (0.65 + 0.35 * separation)
        guard confidence >= 0.72 else { return .none }

        // Match the wide image too when choosing the join. Its outer columns
        // reveal rounded corners that were deliberately ignored for alignment.
        let padding = min(8, (best.end - best.start) / 8)
        var seam = best.start + padding, seamError = Double.infinity
        let middle = Double(best.start + best.end) / 2
        for row in (best.start + padding)..<max(best.start + padding + 1, best.end - padding) {
            var error = 0.0
            for y in max(best.start, row - padding)...min(best.end - 1, row + padding) {
                for x in 0..<upper.width {
                    error += Double(abs(Int(upper.pixels[(y + best.shift) * upper.width + x])
                                        - Int(lower.pixels[y * lower.width + x])))
                }
            }
            error /= Double((min(best.end - 1, row + padding) - max(best.start, row - padding) + 1) * upper.width)
            // Prefer the center of an equally clean band.
            error += abs(Double(row) - middle) / Double(best.end - best.start) * 0.01
            if error < seamError { seam = row; seamError = error }
        }
        return OverlapMatch(overlap: upper.height - best.shift, confidence: confidence,
                            error: best.error, seam: seam)
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

    private static func difference(_ a: PixelGrid, _ b: PixelGrid, overlap: Int, everyRow: Bool = false,
                                   sampleRows: Range<Int>? = nil) -> Double {
        var sum = 0.0
        var detail = 0.0
        var count = 0
        let rowStep = everyRow ? 1 : max(1, overlap / 90)
        // Ignore outer margins, where scroll indicators and floating UI often live.
        let margin = max(1, a.width / (sampleRows == nil ? 10 : 40))
        let start = max(0, sampleRows?.lowerBound ?? 0)
        let end = min(overlap, sampleRows?.upperBound ?? overlap)
        guard start < end else { return 1 }
        for row in stride(from: start, to: end, by: rowStep) {
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
                              overlap: Int, radius: Int, sampleRows: Range<Int>? = nil) -> Int {
        guard upper.width == lower.width, upper.width >= 4 else { return overlap }
        let start = max(8, overlap - radius)
        let end = min(min(upper.height, lower.height) - 1, overlap + radius)
        guard start <= end else { return overlap }
        var best = overlap, error = Double.infinity
        for candidate in start...end {
            let value = difference(upper, lower, overlap: candidate, everyRow: true, sampleRows: sampleRows)
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
    public static func order(_ grids: [PixelGrid], automatic: Bool, allowOcclusion: Bool = true) -> OrderingResult {
        let n = grids.count
        guard n > 1 else { return OrderingResult(indices: Array(0..<n), matches: [], changed: false, reliable: true) }
        var matrix = Array(repeating: Array(repeating: OverlapMatch.none, count: n), count: n)
        for i in 0..<(n - 1) {
            matrix[i][i + 1] = match(grids[i], grids[i + 1], allowOcclusion: allowOcclusion)
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
                    matrix[i][j] = match(grids[i], grids[j], allowOcclusion: allowOcclusion)
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
