import XCTest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import StitchCore
@testable import StitchImaging

final class ImagingTests: XCTestCase {
    private func fixture() throws -> (directory: URL, urls: [URL]) {
        let width = 160
        let height = 1800
        var data = [UInt8](repeating: 255, count: width * height * 4)
        for row in 0..<height {
            for column in 0..<width {
                var seed = UInt64(row / 3 * 37 + column / 3 + 1)
                seed = (seed ^ (seed >> 30)) &* 0xbf58476d1ce4e5b9
                seed = (seed ^ (seed >> 27)) &* 0x94d049bb133111eb
                let intensity = UInt8(truncatingIfNeeded: seed ^ (seed >> 31))
                let index = (row * width + column) * 4
                data[index] = intensity
                data[index + 1] = intensity
                data[index + 2] = intensity
            }
        }
        let image = try data.withUnsafeMutableBytes { bytes -> CGImage in
            let context = try XCTUnwrap(CGContext(data: bytes.baseAddress, width: width, height: height,
                                                 bitsPerComponent: 8, bytesPerRow: width * 4,
                                                 space: CGColorSpaceCreateDeviceRGB(),
                                                 bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
            return try XCTUnwrap(context.makeImage())
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var urls: [URL] = []
        for (index, start) in [0, 500, 1000].enumerated() {
            let crop = try XCTUnwrap(image.cropping(to: CGRect(x: 0, y: start, width: width, height: 800)))
            let url = directory.appendingPathComponent("\(index).png")
            let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
            CGImageDestinationAddImage(destination, crop, nil)
            XCTAssertTrue(CGImageDestinationFinalize(destination))
            urls.append(url)
        }
        return (directory, urls)
    }

    func testImagePipelineReordersDeduplicatesAndKeepsPixelOrientation() async throws {
        let fixture = try fixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let engine = StitchEngine()
        let analysis = try await engine.analyze(urls: [fixture.urls[2], fixture.urls[0], fixture.urls[1], fixture.urls[0]],
                                                automatic: true, trimChrome: false)
        XCTAssertTrue(analysis.reordered)
        XCTAssertEqual(analysis.duplicates, 1)
        XCTAssertEqual(analysis.shots.map(\.url), fixture.urls)
        XCTAssertEqual(analysis.overlaps, [300, 300])
        let result = try await engine.render(analysis, overlaps: analysis.overlaps, endCuts: [0, 0],
                                             top: 0, bottom: 0, preview: false)
        defer { try? FileManager.default.removeItem(at: result) }
        let image = try ImageFiles.image(at: result, maxDimension: 2000)
        XCTAssertEqual(image.width, 160)
        XCTAssertEqual(image.height, 1800)
        let first = try ImageFiles.image(at: fixture.urls[0])
        let last = try ImageFiles.image(at: fixture.urls[2])
        let outputTop = try XCTUnwrap(image.cropping(to: CGRect(x: 0, y: 0, width: 160, height: 100)))
        let sourceTop = try XCTUnwrap(first.cropping(to: CGRect(x: 0, y: 0, width: 160, height: 100)))
        let outputBottom = try XCTUnwrap(image.cropping(to: CGRect(x: 0, y: 1700, width: 160, height: 100)))
        let sourceBottom = try XCTUnwrap(last.cropping(to: CGRect(x: 0, y: 700, width: 160, height: 100)))
        XCTAssertEqual(try ImageFiles.grid(outputTop, width: 40, height: 100).pixels,
                       try ImageFiles.grid(sourceTop, width: 40, height: 100).pixels)
        XCTAssertEqual(try ImageFiles.grid(outputBottom, width: 40, height: 100).pixels,
                       try ImageFiles.grid(sourceBottom, width: 40, height: 100).pixels)
    }

    func testManualCutsAndPreviewProduceValidFiles() async throws {
        let fixture = try fixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let engine = StitchEngine()
        let analysis = try await engine.analyze(urls: fixture.urls, automatic: false, trimChrome: false)
        let output = try await engine.render(analysis, overlaps: [320, 310], endCuts: [10, 20], top: 5, bottom: 5, preview: false)
        let preview = try await engine.render(analysis, overlaps: [320, 310], endCuts: [10, 20], top: 5, bottom: 5, preview: true)
        defer {
            try? FileManager.default.removeItem(at: output)
            try? FileManager.default.removeItem(at: preview)
        }
        XCTAssertEqual(try ImageFiles.size(at: output).height, 1710)
        XCTAssertEqual(try ImageFiles.size(at: preview).height, 1710)
    }

    func testInvalidImageDoesNotCrash() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let invalid = directory.appendingPathComponent("invalid.jpg")
        try Data("not an image".utf8).write(to: invalid)
        do {
            _ = try await StitchEngine().analyze(urls: [invalid, invalid], automatic: true, trimChrome: false)
            XCTFail("Invalid image should throw")
        } catch { XCTAssertTrue(error is StorageError) }
    }
}
