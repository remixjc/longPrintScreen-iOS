import UIKit
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
    var confidences: [Double]
    var top: Int
    var bottom: Int
    var reordered: Bool
    var duplicates: Int
    var width: Int
    var heights: [Int]
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
        let scale = min(1, 800.0 / Double(maxHeight))
        grids = try shots.enumerated().map { index, shot in
            try ImageFiles.grid(ImageFiles.image(at: shot.url), width: 40, height: max(24, Int(Double(heights[index]) * scale)))
        }
        let insets = trimChrome ? StitchMatcher.fixedInsets(grids) : (top: 0, bottom: 0)
        let cropped = grids.map { $0.cropped(top: insets.top, bottom: insets.bottom) }
        let result = StitchMatcher.order(cropped, automatic: automatic)
        return StitchAnalysis(
            shots: result.indices.map { shots[$0] },
            overlaps: result.matches.map { $0.isReliable ? Int(Double($0.overlap) / scale) : 0 },
            confidences: result.matches.map(\.confidence),
            top: Int(Double(insets.top) / scale), bottom: Int(Double(insets.bottom) / scale),
            reordered: result.changed, duplicates: duplicates, width: width,
            heights: result.indices.map { heights[$0] }
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
        context.setFillColor(UIColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: outputWidth, height: outputHeight))
        context.interpolationQuality = .high
        var cursor = outputHeight
        for (index, shot) in analysis.shots.enumerated() {
            try Task.checkCancellation()
            try autoreleasepool {
                let nativeScale = Double(outputWidth) / Double(shot.width)
                let maxDimension = max(outputWidth, Int(Double(shot.height) * nativeScale))
                let image = try ImageFiles.image(at: shot.url, maxDimension: maxDimension)
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
