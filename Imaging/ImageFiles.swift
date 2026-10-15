import Foundation
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers
import StitchCore

enum ImageFiles {
    static func image(at url: URL, maxDimension: Int = 2048) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxDimension,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { throw StorageError.invalidImage }
        return image
    }

    static func write(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw StorageError.invalidImage
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.93] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw StorageError.invalidImage }
    }

    static func size(at url: URL) throws -> (width: Int, height: Int) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = properties[kCGImagePropertyPixelWidth] as? Int,
              let h = properties[kCGImagePropertyPixelHeight] as? Int, w > 0, h > 0 else { throw StorageError.invalidImage }
        let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
        return [5, 6, 7, 8].contains(orientation) ? (h, w) : (w, h)
    }

    static func grid(_ image: CGImage, width: Int = 128, height: Int = 1000) throws -> PixelGrid {
        var pixels = Array(repeating: UInt8(0), count: width * height)
        let success = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width,
                                          space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0) else { return false }
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard success else { throw StorageError.invalidImage }
        return PixelGrid(width: width, height: height, pixels: pixels)
    }
}
