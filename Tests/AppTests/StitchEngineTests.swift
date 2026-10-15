import XCTest
import UIKit
import StoreKitTest
import AVFoundation
@testable import LongShot

final class StitchEngineTests: XCTestCase {
    func testShuffledDemoProducesFullPageAndPNG() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let urls = try await MainActor.run { try DemoImages.make(in: directory) }
        let engine = StitchEngine()
        let analysis = try await engine.analyze(urls: urls, automatic: true, trimChrome: false)
        XCTAssertTrue(analysis.reordered)
        XCTAssertEqual(analysis.shots.map(\.label), ["2", "3", "1"])
        XCTAssertEqual(analysis.overlaps.count, 2)
        for overlap in analysis.overlaps { XCTAssertEqual(overlap, 300, accuracy: 2) }
        let result = try await engine.render(analysis, overlaps: analysis.overlaps, endCuts: [0, 0],
                                             top: 0, bottom: 0, preview: false)
        defer { try? FileManager.default.removeItem(at: result) }
        let size = try ImageFiles.size(at: result)
        XCTAssertEqual(size.width, 400)
        XCTAssertEqual(size.height, 1800, accuracy: 4)
        // Verify top and last rows against their source: catches upside-down composition.
        let composed = try ImageFiles.image(at: result, maxDimension: 2200)
        let first = try ImageFiles.image(at: analysis.shots[0].url, maxDimension: 2200)
        let last = try ImageFiles.image(at: analysis.shots[2].url, maxDimension: 2200)
        let composedTop = try XCTUnwrap(composed.cropping(to: CGRect(x: 0, y: 0, width: 400, height: 100)))
        let firstTop = try XCTUnwrap(first.cropping(to: CGRect(x: 0, y: 0, width: 400, height: 100)))
        let composedBottom = try XCTUnwrap(composed.cropping(to: CGRect(x: 0, y: size.height - 100, width: 400, height: 100)))
        let lastBottom = try XCTUnwrap(last.cropping(to: CGRect(x: 0, y: 700, width: 400, height: 100)))
        XCTAssertEqual(try ImageFiles.grid(composedTop, width: 40, height: 50).pixels,
                       try ImageFiles.grid(firstTop, width: 40, height: 50).pixels)
        XCTAssertEqual(try ImageFiles.grid(composedBottom, width: 40, height: 50).pixels,
                       try ImageFiles.grid(lastBottom, width: 40, height: 50).pixels)
    }

    func testManualSeamsChangeExportHeight() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let urls = try await MainActor.run { try DemoImages.make(in: directory) }
        let engine = StitchEngine()
        let analysis = try await engine.analyze(urls: urls, automatic: true, trimChrome: false)
        let result = try await engine.render(analysis, overlaps: [320, 310], endCuts: [10, 20],
                                             top: 5, bottom: 5, preview: false)
        defer { try? FileManager.default.removeItem(at: result) }
        XCTAssertEqual(try ImageFiles.size(at: result).height, 1710)
    }

    func testManifestCannotEscapeBatchDirectory() {
        let batch = ImportBatch(id: UUID(), created: .now, source: "test",
                                files: ["valid.jpg", "../secret", "/private.jpg", "a/b.jpg"], complete: true)
        let urls = SharedStorage.fileURLs(batch, directory: URL(fileURLWithPath: "/tmp/example"))
        XCTAssertEqual(urls.map(\.lastPathComponent), ["valid.jpg"])
    }

    func testSharedInboxPublishesOnlyCompleteBatchesAndKeepsOrder() throws {
        var (batch, folder) = try SharedStorage.create(source: "测试导入")
        defer { try? FileManager.default.removeItem(at: folder) }
        batch.files = ["2.jpg", "0.jpg", "1.jpg"]
        try SharedStorage.save(batch, directory: folder)
        XCTAssertFalse(try SharedStorage.pending().contains { $0.0.id == batch.id })
        batch.complete = true
        try SharedStorage.save(batch, directory: folder)
        let restored = try XCTUnwrap(SharedStorage.pending().first { $0.0.id == batch.id })
        XCTAssertEqual(restored.0.files, ["2.jpg", "0.jpg", "1.jpg"])
        XCTAssertEqual(SharedStorage.fileURLs(restored.0, directory: folder).map(\.lastPathComponent),
                       ["2.jpg", "0.jpg", "1.jpg"])
    }

    func testRecordingAuthorizationExpiresAndRevokes() {
        XCTAssertTrue(RecordingAuthorization.write(validUntil: Date().addingTimeInterval(60)))
        XCTAssertTrue(RecordingAuthorization.isValid)
        XCTAssertTrue(RecordingAuthorization.write(validUntil: Date().addingTimeInterval(-1)))
        XCTAssertFalse(RecordingAuthorization.isValid)
        RecordingAuthorization.write(validUntil: nil)
        XCTAssertFalse(RecordingAuthorization.isValid)
    }

    @MainActor
    func testPreviewRefreshDoesNotDeleteFileBeingShared() async throws {
        let model = WorkspaceModel()
        await model.loadDemo()
        let candidate = await model.export()
        let exported = try XCTUnwrap(candidate)
        await model.updatePreview()
        XCTAssertTrue(FileManager.default.fileExists(atPath: exported.path))
        model.closeEditor()
        XCTAssertFalse(FileManager.default.fileExists(atPath: exported.path))
    }

    @MainActor
    func testRemovingAnUnwantedCaptureKeepsTwoImageMinimum() async throws {
        let model = WorkspaceModel()
        await model.loadDemo()
        XCTAssertEqual(model.analysis?.shots.count, 3)
        await model.removeShot(at: 0)
        XCTAssertEqual(model.analysis?.shots.count, 2)
        XCTAssertEqual(model.overlaps.count, 1)
        await model.removeShot(at: 0)
        XCTAssertEqual(model.analysis?.shots.count, 2)
        model.closeEditor()
    }

    func testVideoImportExtractsChangingFrames() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let video = directory.appendingPathComponent("recording.mov")
        let writer = try AVAssetWriter(outputURL: video, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 160, AVVideoHeightKey: 320
        ])
        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: 160, kCVPixelBufferHeightKey as String: 320,
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: attributes)
        writer.add(input)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        for index in 0..<30 {
            let deadline = Date().addingTimeInterval(10)
            while !input.isReadyForMoreMediaData && Date() < deadline {
                try await Task.sleep(for: .milliseconds(10))
            }
            XCTAssertTrue(input.isReadyForMoreMediaData)
            var buffer: CVPixelBuffer?
            XCTAssertEqual(CVPixelBufferCreate(kCFAllocatorDefault, 160, 320, kCVPixelFormatType_32ARGB,
                                               attributes as CFDictionary, &buffer), kCVReturnSuccess)
            let frame = try XCTUnwrap(buffer)
            CVPixelBufferLockBaseAddress(frame, [])
            let context = try XCTUnwrap(CGContext(data: CVPixelBufferGetBaseAddress(frame), width: 160, height: 320,
                                                 bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(frame),
                                                 space: CGColorSpaceCreateDeviceRGB(),
                                                 bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue))
            context.setFillColor(CGColor(gray: 0.1 + Double(index) * 0.02, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 160, height: 320))
            CVPixelBufferUnlockBaseAddress(frame, [])
            XCTAssertTrue(adaptor.append(frame, withPresentationTime: CMTime(value: Int64(index), timescale: 10)))
        }
        input.markAsFinished()
        await writer.finishWriting()
        XCTAssertEqual(writer.status, .completed)
        let frames = try await VideoFrameExtractor.extract(url: video, directory: directory)
        XCTAssertGreaterThanOrEqual(frames.count, 2)
        XCTAssertLessThanOrEqual(frames.count, 60)
        for frame in frames { XCTAssertEqual(try ImageFiles.size(at: frame).width, 160) }
    }
}

@MainActor
final class PurchaseStoreTests: XCTestCase {
    private func session() throws -> SKTestSession {
        let url = try XCTUnwrap(Bundle(for: PurchaseStoreTests.self).url(forResource: "Products", withExtension: "storekit"))
        let session = try SKTestSession(contentsOf: url)
        session.resetToDefaultState()
        session.disableDialogs = true
        session.timeRate = .realTime
        session.storefront = "CHN"
        session.clearTransactions()
        return session
    }

    func testYearlyPurchaseExpirationAndLifetimeRevocation() async throws {
        let session = try session()
        defer { session.clearTransactions() }
        let store = PurchaseStore(automaticallyLoad: false)
        await store.reload()
        XCTAssertEqual(Set(store.products.map(\.id)), [AppConfiguration.annualProduct, AppConfiguration.lifetimeProduct])
        let annualProduct = try XCTUnwrap(store.products.first { $0.id == AppConfiguration.annualProduct })
        XCTAssertEqual(annualProduct.price, Decimal(1))
        XCTAssertEqual(annualProduct.subscription?.subscriptionPeriod.unit, .year)
        XCTAssertEqual(annualProduct.subscription?.subscriptionPeriod.value, 1)
        let lifetimeProduct = try XCTUnwrap(store.products.first { $0.id == AppConfiguration.lifetimeProduct })
        XCTAssertEqual(lifetimeProduct.price, Decimal(6))
        XCTAssertEqual(lifetimeProduct.type, .nonConsumable)
        XCTAssertFalse(store.hasPro)
        let annual = try await session.buyProduct(identifier: AppConfiguration.annualProduct)
        XCTAssertEqual(annual.productID, AppConfiguration.annualProduct)
        XCTAssertNotNil(annual.expirationDate)
        await waitForEntitlement(store, active: true)
        XCTAssertTrue(store.hasPro)
        XCTAssertFalse(store.isLifetime)
        XCTAssertNotNil(store.expiration)
        try session.expireSubscription(productIdentifier: AppConfiguration.annualProduct)
        await waitForEntitlement(store, active: false)
        XCTAssertFalse(store.hasPro)
        let transaction = try await session.buyProduct(identifier: AppConfiguration.lifetimeProduct)
        await waitForEntitlement(store, active: true)
        XCTAssertTrue(store.hasPro)
        XCTAssertTrue(store.isLifetime)
        // The session already owns verified local transactions. Account-level
        // AppStore.sync is a Sandbox/TestFlight check; it can reset or stall
        // headless StoreKitTest sessions and should not contact a real account here.
        let restored = PurchaseStore(automaticallyLoad: false, synchronize: {})
        await restored.restore()
        await waitForEntitlement(restored, active: true)
        XCTAssertEqual(restored.message, "已恢复你的 Pro 权益。")
        XCTAssertTrue(restored.hasPro)
        XCTAssertTrue(restored.isLifetime)
        try session.refundTransaction(identifier: UInt(transaction.id))
        await waitForEntitlement(store, active: false)
        XCTAssertFalse(store.hasPro)
        XCTAssertFalse(RecordingAuthorization.isValid)
    }

    func testRestoreSyncFailureDoesNotGrantPro() async throws {
        let session = try session()
        defer { session.clearTransactions() }
        let store = PurchaseStore(automaticallyLoad: false, synchronize: {
            throw URLError(.notConnectedToInternet)
        })
        await store.restore()
        XCTAssertFalse(store.hasPro)
        XCTAssertTrue(store.message?.hasPrefix("恢复失败：") == true)
        XCTAssertFalse(store.busy)
    }

    private func waitForEntitlement(_ store: PurchaseStore, active: Bool) async {
        for _ in 0..<50 {
            await store.refreshEntitlements()
            if store.hasPro == active { return }
            try? await Task.sleep(for: .milliseconds(200))
        }
    }
}
