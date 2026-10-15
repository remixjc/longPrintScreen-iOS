import XCTest
import UIKit
import StoreKitTest
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

    func testRecordingAuthorizationExpiresAndRevokes() {
        XCTAssertTrue(RecordingAuthorization.write(validUntil: Date().addingTimeInterval(60)))
        XCTAssertTrue(RecordingAuthorization.isValid)
        XCTAssertTrue(RecordingAuthorization.write(validUntil: Date().addingTimeInterval(-1)))
        XCTAssertFalse(RecordingAuthorization.isValid)
        RecordingAuthorization.write(validUntil: nil)
        XCTAssertFalse(RecordingAuthorization.isValid)
    }
}

@MainActor
final class PurchaseStoreTests: XCTestCase {
    private func session() throws -> SKTestSession {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "Products", withExtension: "storekit"))
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
        try session.refundTransaction(identifier: UInt(transaction.id))
        await waitForEntitlement(store, active: false)
        XCTAssertFalse(store.hasPro)
        XCTAssertFalse(RecordingAuthorization.isValid)
    }

    private func waitForEntitlement(_ store: PurchaseStore, active: Bool) async {
        for _ in 0..<50 {
            await store.refreshEntitlements()
            if store.hasPro == active { return }
            try? await Task.sleep(for: .milliseconds(200))
        }
    }
}
