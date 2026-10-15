import Foundation
import CoreGraphics
import StitchCore
import UniformTypeIdentifiers
import ImageIO

struct Shot: Identifiable, Sendable {
    let id: UUID
    let url: URL
    let width: Int
    let height: Int
    let label: String
}

struct StitchAnalysis: Sendable {
    var shots: [Shot]
    var overlaps: [Int]
    var endCuts: [Int]
    var confidences: [Double]
    var top: Int
    var bottom: Int
    var reordered: Bool
    var duplicates: Int
    var width: Int
    var heights: [Int]
    var cleanIndicators: Bool
}

enum StitchError: LocalizedError {
    case insufficient, tooTall, cancelled
    var errorDescription: String? {
        switch self {
        case .insufficient: return "请至少选择两张不同的图片。"
        case .tooTall: return "图片过长，请分成两次拼接。"
        case .cancelled: return "处理已取消。"
        }
    }
}

actor StitchEngine {
    func analyze(urls: [URL], automatic: Bool, trimChrome: Bool) throws -> StitchAnalysis {
        var shots: [Shot] = []
        var grids: [PixelGrid] = []
        var duplicates = 0
        for (index, url) in urls.enumerated() {
            try Task.checkCancellation()
            let size = try ImageFiles.size(at: url)
            let image = try ImageFiles.image(at: url)
            let grid = try ImageFiles.grid(image)
            // Compare aspect ratios as well as pixels before dropping duplicates.
            let duplicate = grids.enumerated().contains { offset, prior in
                abs(Double(shots[offset].height) / Double(shots[offset].width) - Double(size.height) / Double(size.width)) < 0.01
                && StitchMatcher.meanDifference(prior, grid) < 0.001
            }
            if duplicate { duplicates += 1; continue }
            shots.append(Shot(id: UUID(), url: url, width: size.width, height: size.height, label: "\(index + 1)"))
            grids.append(grid)
        }
        guard shots.count >= 2 else { throw StitchError.insufficient }
        let width = min(1440, shots.map(\.width).min()!)
        let heights = shots.map { max(1, Int(Double($0.height) * Double(width) / Double($0.width))) }
        // Matching happens on proportionate grids, not stretched images.
        let maxHeight = heights.max()!
        let scale = min(1, 4000.0 / Double(maxHeight))
        grids = try shots.enumerated().map { index, shot in
            let height = max(24, Int(Double(heights[index]) * scale))
            return try ImageFiles.grid(ImageFiles.image(at: shot.url, maxDimension: max(width, height)), height: height)
        }
        let insets = trimChrome ? StitchMatcher.fixedInsets(grids) : (top: 0, bottom: 0)
        let cropped = grids.map { $0.cropped(top: insets.top, bottom: insets.bottom) }
        let result = StitchMatcher.order(cropped, automatic: automatic, allowOcclusion: trimChrome)
        let top = Int((Double(insets.top) / scale).rounded())
        let bottom = Int((Double(insets.bottom) / scale).rounded())
        var overlaps = result.matches.map { $0.isReliable ? Int((Double($0.overlap) / scale).rounded()) : 0 }
        // Only adjacent, already verified matches need full-height refinement.
        // Preserve every output row for phone screenshots; cap exceptionally
        // tall imported images to keep decoding and matching memory bounded.
        let detailScale = min(1, 6000.0 / Double(maxHeight))
        var detailed: [Int: PixelGrid] = [:]
        func detail(_ index: Int) throws -> PixelGrid {
            if scale == 1 { return cropped[index] }
            if let grid = detailed[index] { return grid }
            let height = max(24, Int(Double(heights[index]) * detailScale))
            let image = try ImageFiles.image(at: shots[index].url, maxDimension: max(width, height))
            let grid = try ImageFiles.grid(image, height: height)
                .cropped(top: Int(Double(top) * detailScale), bottom: Int(Double(bottom) * detailScale))
            detailed[index] = grid
            return grid
        }
        for index in overlaps.indices where result.matches[index].isReliable {
            let match = result.matches[index]
            if match.seam != nil && scale == detailScale { continue }
            try Task.checkCancellation()
            let upper = try detail(result.indices[index])
            let lower = try detail(result.indices[index + 1])
            let sampleRows = match.seam.map { seam -> Range<Int> in
                let row = Int(Double(seam) * detailScale / scale)
                return max(0, row - 4)..<min(lower.height, row + max(16, Int(32 * detailScale / scale)))
            }
            let refined = StitchMatcher.refine(upper, lower, overlap: Int(Double(overlaps[index]) * detailScale),
                                               radius: max(3, Int(ceil(3 * detailScale / scale))), sampleRows: sampleRows)
            overlaps[index] = Int((Double(refined) / detailScale).rounded())
        }
        var endCuts = Array(repeating: 0, count: overlaps.count)
        for index in overlaps.indices {
            let match = result.matches[index]
            guard match.isReliable, let seam = match.seam else { continue }
            let start = Int((Double(seam) / scale).rounded())
            endCuts[index] = overlaps[index] - start
            overlaps[index] = start
        }
        return StitchAnalysis(
            shots: result.indices.map { shots[$0] },
            overlaps: overlaps,
            endCuts: endCuts,
            confidences: result.matches.map(\.confidence),
            top: top, bottom: bottom,
            reordered: result.changed, duplicates: duplicates, width: width,
            heights: result.indices.map { heights[$0] },
            cleanIndicators: trimChrome && result.matches.allSatisfy(\.isReliable)
        )
    }

    func render(_ analysis: StitchAnalysis, overlaps: [Int], endCuts: [Int], top: Int, bottom: Int,
                preview: Bool) throws -> URL {
        let ranges = CompositionPlan.ranges(heights: analysis.heights, top: top, bottom: bottom,
                                            overlaps: overlaps, endCuts: endCuts)
        let totalHeight = ranges.map(\.height).reduce(0, +)
        let targetWidth = preview ? min(420, analysis.width) : analysis.width
        let pixelLimit = preview ? 6_000_000.0 : 32_000_000.0
        var scale = Double(targetWidth) / Double(analysis.width)
        scale = min(scale, sqrt(pixelLimit / Double(totalHeight * analysis.width)))
        let outputWidth = max(1, Int(Double(analysis.width) * scale))
        let outputHeight = max(1, ranges.map { max(1, Int(Double($0.height) * scale)) }.reduce(0, +))
        guard outputHeight <= 60_000,
              let context = CGContext(data: nil, width: outputWidth, height: outputHeight,
                                      bitsPerComponent: 8, bytesPerRow: outputWidth * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { throw StitchError.tooTall }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: outputWidth, height: outputHeight))
        context.interpolationQuality = .high
        var cursor = outputHeight
        for (index, shot) in analysis.shots.enumerated() {
            try Task.checkCancellation()
            try autoreleasepool {
                let nativeScale = Double(outputWidth) / Double(shot.width)
                let maxDimension = max(outputWidth, Int(Double(shot.height) * nativeScale))
                var image = try ImageFiles.image(at: shot.url, maxDimension: maxDimension)
                if analysis.cleanIndicators { image = try ImageFiles.removingScrollIndicator(image) }
                let range = ranges[index]
                let imageScale = Double(image.height) / Double(analysis.heights[index])
                let y = Int(Double(range.start) * imageScale)
                let h = max(1, min(image.height - y, Int(Double(range.height) * imageScale)))
                guard let cropped = image.cropping(to: CGRect(x: 0, y: y, width: image.width, height: h)) else {
                    throw StorageError.invalidImage
                }
                let drawHeight = max(1, Int(Double(range.height) * scale))
                cursor -= drawHeight
                context.draw(cropped, in: CGRect(x: 0, y: cursor, width: outputWidth, height: drawHeight))
            }
        }
        guard let image = context.makeImage() else { throw StorageError.invalidImage }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("longshot-\(UUID().uuidString).png")
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw StorageError.invalidImage
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw StorageError.invalidImage }
        return url
    }
}
