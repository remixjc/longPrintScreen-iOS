import XCTest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import CoreText
import StitchCore
#if canImport(StitchImaging)
@testable import StitchImaging
#else
@testable import LongShot
#endif

final class ImagingTests: XCTestCase {
    /// Private screenshots stay outside the repository. Set this directory to
    /// run the reported Health-sheet case through the same engine as the app.
    @MainActor
    func testLocalHealthScreenshots() async throws {
        var path = ProcessInfo.processInfo.environment["LONGSHOT_HEALTH_FIXTURES"]
        #if os(iOS)
        if path == nil {
            let candidate = try XCTUnwrap(FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first)
                .appendingPathComponent("HealthRegression")
            if FileManager.default.fileExists(atPath: candidate.appendingPathComponent("IMG_5758.PNG").path) {
                path = candidate.path
            }
        }
        #endif
        guard let path else {
            throw XCTSkip("Set LONGSHOT_HEALTH_FIXTURES to the local screenshot directory")
        }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        let urls = (5758...5762).map { directory.appendingPathComponent("IMG_\($0).PNG") }
        #if canImport(StitchImaging)
        let engine = StitchEngine()
        let analysis = try await engine.analyze(urls: urls.reversed(), automatic: true, trimChrome: true)
        let output = try await engine.render(analysis, overlaps: analysis.overlaps, endCuts: analysis.endCuts,
                                             top: analysis.top, bottom: analysis.bottom, preview: false)
        #else
        // Exercise the actual editor defaults and export, including applying
        // both halves of an automatic seam to WorkspaceModel.
        let model = WorkspaceModel()
        defer { model.closeEditor() }
        let batchDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: batchDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: batchDirectory) }
        let files = Array(urls.reversed()).map(\.lastPathComponent)
        for url in urls {
            try FileManager.default.copyItem(at: url, to: batchDirectory.appendingPathComponent(url.lastPathComponent))
        }
        let batch = ImportBatch(id: UUID(), created: .now, source: "回归测试", files: files, complete: true)
        await model.importBatch(batch, directory: batchDirectory)
        let analysis = try XCTUnwrap(model.analysis, model.message ?? "Import did not create an editor")
        XCTAssertEqual(model.overlaps, analysis.overlaps)
        XCTAssertEqual(model.endCuts, analysis.endCuts)
        let exported = await model.export()
        let output = try XCTUnwrap(exported)
        #endif
        print("Health analysis:", analysis.shots.map(\.label), analysis.overlaps, analysis.endCuts,
              analysis.confidences, analysis.top, analysis.bottom)
        #if canImport(StitchImaging)
        XCTAssertEqual(analysis.shots.map(\.url), urls)
        #endif
        XCTAssertEqual(analysis.shots.map(\.label), ["5", "4", "3", "2", "1"])
        XCTAssertTrue(analysis.confidences.allSatisfy { $0 >= 0.72 })
        for (index, shift) in [2114, 1721, 1741, 541].enumerated() {
            XCTAssertEqual(analysis.heights[index] - analysis.top - analysis.bottom
                           - analysis.overlaps[index] - analysis.endCuts[index], shift)
        }
        defer { try? FileManager.default.removeItem(at: output) }
        XCTAssertEqual(try ImageFiles.size(at: output).height, 8985, accuracy: 5)
        let actual = try ImageFiles.image(at: output, maxDimension: 10000)
        let reference = try ImageFiles.image(at: directory.appendingPathComponent("IMG_5763.JPG"), maxDimension: 10000)
        XCTAssertEqual(actual.width, reference.width)
        XCTAssertEqual(actual.height, reference.height)
        if actual.height == reference.height {
            // JPEG compression is allowed; displaced text or repeated bars are
            // not. Check the full page as well as every seam independently.
            let a = try ImageFiles.grid(actual, width: 256, height: actual.height)
            let b = try ImageFiles.grid(reference, width: 256, height: reference.height)
            XCTAssertLessThan(StitchMatcher.meanDifference(a, b), 0.004)
            let ranges = CompositionPlan.ranges(heights: analysis.heights, top: analysis.top, bottom: analysis.bottom,
                                                overlaps: analysis.overlaps, endCuts: analysis.endCuts)
            var cursor = 0
            for range in ranges.dropLast() {
                cursor += range.height
                let ag = a.cropped(top: cursor - 80, bottom: a.height - cursor - 80)
                let bg = b.cropped(top: cursor - 80, bottom: b.height - cursor - 80)
                // Dark antialiased Chinese text differs by about one gray
                // level after JPEG/color-space conversion.
                XCTAssertLessThan(StitchMatcher.meanDifference(ag, bg), 0.006)
            }
        }
        var artifacts = ProcessInfo.processInfo.environment["LONGSHOT_HEALTH_ARTIFACTS"]
        #if os(iOS)
        artifacts = artifacts ?? directory.appendingPathComponent("Output").path
        #endif
        if let artifacts {
            let target = URL(fileURLWithPath: artifacts).appendingPathComponent("stitched.png")
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: target)
            try FileManager.default.copyItem(at: output, to: target)
        }
    }

    private func textFixture(jpeg: Bool, varyingChrome: Bool = false) throws -> (directory: URL, urls: [URL], expected: CGImage) {
        let width = 1170, height = 2532, header = 324, footer = 252, scroll = 1169
        let pageHeight = height - header - footer + scroll * 2
        func canvas(_ h: Int) throws -> CGContext {
            let context = try XCTUnwrap(CGContext(data: nil, width: width, height: h,
                                                 bitsPerComponent: 8, bytesPerRow: width * 4,
                                                 space: CGColorSpaceCreateDeviceRGB(),
                                                 bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: h))
            return context
        }
        func text(_ string: String, _ context: CGContext, x: Int, y: Int, size: CGFloat = 39) {
            let attributes: [NSAttributedString.Key: Any] = [
                .init(kCTFontAttributeName as String): CTFontCreateWithName("PingFangSC-Regular" as CFString, size, nil),
                .init(kCTForegroundColorAttributeName as String): CGColor(gray: 0.12, alpha: 1)
            ]
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: attributes))
            context.textPosition = CGPoint(x: x, y: y)
            CTLineDraw(line, context)
        }
        let page = try canvas(pageHeight)
        let phrases = ["旅行里值得保存的风景与故事", "今天走过的小路，明天还想再去", "把生活里的片段连接成一幅长卷",
                       "分享给朋友，也留给未来的自己", "轻轻向下滚动，继续阅读新的内容"]
        for index in 0..<(pageHeight / 94) {
            text(String(format: "%02d", index + 1) + "  " + phrases[index % phrases.count],
                 page, x: 60, y: pageHeight - 62 - index * 94)
        }
        let pageImage = try XCTUnwrap(page.makeImage())
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        func chrome(_ context: CGContext, h: Int, index: Int) {
            context.setFillColor(CGColor(gray: varyingChrome ? 0.75 + Double(index) * 0.04 : 0.96, alpha: 1))
            context.fill(CGRect(x: 0, y: h - header, width: width, height: header))
            context.fill(CGRect(x: 0, y: 0, width: width, height: footer))
            text("9:\(41 + index)", context, x: 72, y: h - 100, size: 36)
            text("正在阅读 · 长卷", context, x: 400, y: h - 240, size: 48)
            text("返回        分享        收藏 \(index)", context, x: 150, y: 120, size: 42)
        }
        var urls: [URL] = []
        for index in 0..<3 {
            let context = try canvas(height)
            let crop = try XCTUnwrap(pageImage.cropping(to: CGRect(x: 0, y: index * scroll,
                                                                   width: width, height: height - header - footer)))
            context.draw(crop, in: CGRect(x: 0, y: footer, width: width, height: height - header - footer))
            chrome(context, h: height, index: index)
            // A scroll indicator changes at the outer edge.
            context.setFillColor(CGColor(gray: 0.45, alpha: 1))
            context.fill(CGRect(x: width - 12, y: 800 + index * 180, width: 6, height: 160))
            let image = try XCTUnwrap(context.makeImage())
            let url = directory.appendingPathComponent("\(index).\(jpeg ? "jpg" : "png")")
            if jpeg {
                try ImageFiles.write(image, to: url)
            } else {
                let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
                CGImageDestinationAddImage(destination, image, nil)
                XCTAssertTrue(CGImageDestinationFinalize(destination))
            }
            urls.append(url)
        }
        let expected = try canvas(pageHeight + header + footer)
        chrome(expected, h: pageHeight + header + footer, index: 0)
        expected.draw(pageImage, in: CGRect(x: 0, y: footer, width: width, height: pageHeight))
        return (directory, urls, try XCTUnwrap(expected.makeImage()))
    }

    func testTextScreenshotsBecomeContinuousPageWithOneHeaderAndFooter() async throws {
        try await verifyTextPipeline(jpeg: false, shuffled: false)
    }

    func testJPEGTextScreenshotsCanBeAutomaticallyOrderedAndStitched() async throws {
        try await verifyTextPipeline(jpeg: true, shuffled: true)
    }

    func testChangingHeaderAndFooterUseSafeInternalJoins() async throws {
        try await verifyTextPipeline(jpeg: false, shuffled: true, varyingChrome: true)
    }

    func testSeparatedTextScreenshotsDoNotInventAnOverlap() async throws {
        let fixture = try textFixture(jpeg: false)
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        // First and third frames have no common scrolling content.
        let analysis = try await StitchEngine().analyze(urls: [fixture.urls[0], fixture.urls[2]],
                                                        automatic: true, trimChrome: true)
        XCTAssertEqual(analysis.overlaps, [0])
        XCTAssertLessThan(analysis.confidences[0], 0.72)
    }

    private func verifyTextPipeline(jpeg: Bool, shuffled: Bool, varyingChrome: Bool = false) async throws {
        let fixture = try textFixture(jpeg: jpeg, varyingChrome: varyingChrome)
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let engine = StitchEngine()
        let urls = shuffled ? [fixture.urls[2], fixture.urls[0], fixture.urls[1]] : fixture.urls
        let analysis = try await engine.analyze(urls: urls, automatic: true, trimChrome: true)
        XCTAssertEqual(analysis.shots.map(\.url), fixture.urls)
        XCTAssertTrue(analysis.confidences.allSatisfy { $0 >= 0.72 }, "\(analysis.confidences)")
        if varyingChrome {
            XCTAssertTrue(analysis.endCuts.allSatisfy { $0 > 0 })
        } else {
            XCTAssertGreaterThanOrEqual(analysis.top, 324)
            XCTAssertGreaterThanOrEqual(analysis.bottom, 252)
        }
        for index in analysis.overlaps.indices {
            XCTAssertEqual(analysis.overlaps[index] + analysis.endCuts[index],
                           2532 - analysis.top - analysis.bottom - 1169, accuracy: 1)
        }
        let result = try await engine.render(analysis, overlaps: analysis.overlaps, endCuts: analysis.endCuts,
                                             top: analysis.top, bottom: analysis.bottom, preview: false)
        defer { try? FileManager.default.removeItem(at: result) }
        if !jpeg, let path = ProcessInfo.processInfo.environment["LONGSHOT_STITCH_ARTIFACTS"] {
            let directory = URL(fileURLWithPath: path, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            for (index, url) in (fixture.urls + [result]).enumerated() {
                let target = directory.appendingPathComponent(index == 3 ? "stitched.png" : "input-\(index + 1).png")
                try? FileManager.default.removeItem(at: target)
                try FileManager.default.copyItem(at: url, to: target)
            }
        }
        let image = try ImageFiles.image(at: result, maxDimension: 6000)
        XCTAssertEqual(image.height, fixture.expected.height, accuracy: 2)
        // Compare the entire scrolling body against the original long page.
        // This detects repeated text, missing rows and internal fixed toolbars.
        if image.height == fixture.expected.height {
            let actual = try XCTUnwrap(image.cropping(to: CGRect(x: 40, y: 324, width: 1090, height: image.height - 324 - 252)))
            let expected = try XCTUnwrap(fixture.expected.cropping(to: CGRect(x: 40, y: 324, width: 1090, height: image.height - 324 - 252)))
            let a = try ImageFiles.grid(actual, width: 256, height: actual.height)
            let b = try ImageFiles.grid(expected, width: 256, height: expected.height)
            XCTAssertLessThan(StitchMatcher.meanDifference(a, b), jpeg ? 0.008 : 0.001)
        }
        let first = try ImageFiles.image(at: fixture.urls[0], maxDimension: 6000)
        let last = try ImageFiles.image(at: fixture.urls[2], maxDimension: 6000)
        for (source, sourceY, outputY, h) in [(first, 0, 0, 324), (last, 2280, image.height - 252, 252)] {
            let a = try XCTUnwrap(source.cropping(to: CGRect(x: 0, y: sourceY, width: 1170, height: h)))
            let b = try XCTUnwrap(image.cropping(to: CGRect(x: 0, y: outputY, width: 1170, height: h)))
            XCTAssertTrue(try ImageFiles.grid(a, width: 128, height: h).pixels ==
                          ImageFiles.grid(b, width: 128, height: h).pixels, "Outer header/footer pixels changed")
        }
    }

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
        XCTAssertEqual(try ImageFiles.size(at: output).height, 1720)
        XCTAssertEqual(try ImageFiles.size(at: preview).height, 1720)
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
