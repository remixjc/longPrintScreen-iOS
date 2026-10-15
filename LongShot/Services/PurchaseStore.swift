import StoreKit
import SwiftUI

@MainActor
final class PurchaseStore: ObservableObject {
    @Published private(set) var products: [Product] = []
    @Published private(set) var hasPro = false
    @Published private(set) var isLifetime = false
    @Published private(set) var expiration: Date?
    @Published private(set) var busy = false
    @Published var message: String?
    private var updates: Task<Void, Never>?

    init() {
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                if case .verified(let transaction) = result {
                    await self.refreshEntitlements()
                    await transaction.finish()
                }
            }
        }
        Task { await reload() }
    }

    deinit { updates?.cancel() }

    func reload() async {
        do {
            products = try await Product.products(for: [AppConfiguration.annualProduct, AppConfiguration.lifetimeProduct])
                .sorted { $0.price < $1.price }
            if products.isEmpty { message = "暂时无法获取商品，请检查网络或稍后重试。未配置 App Store 商品时不能购买。" }
        } catch { message = "无法获取商品：\(error.localizedDescription)" }
        await refreshEntitlements()
    }

    func refreshEntitlements() async {
        var lifetime = false
        var annualExpiration: Date?
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  transaction.revocationDate == nil, !transaction.isUpgraded else { continue }
            if transaction.productID == AppConfiguration.lifetimeProduct {
                lifetime = true
            } else if transaction.productID == AppConfiguration.annualProduct,
                      let expiry = transaction.expirationDate, expiry > Date() {
                annualExpiration = max(annualExpiration ?? .distantPast, expiry)
            }
        }
        isLifetime = lifetime
        expiration = annualExpiration
        hasPro = lifetime || annualExpiration != nil
        let refreshDeadline = Date().addingTimeInterval(24 * 3600)
        let authorizedUntil = hasPro ? min(annualExpiration ?? .distantFuture, refreshDeadline) : nil
        if !RecordingAuthorization.write(validUntil: authorizedUntil), hasPro {
            message = "录屏授权无法同步，请检查共享钥匙串签名配置。"
        }
    }

    func purchase(_ product: Product) async {
        guard !busy else { return }
        busy = true
        message = nil
        defer { busy = false }
        do {
            switch try await product.purchase() {
            case .success(let result):
                guard case .verified(let transaction) = result else {
                    message = "购买凭证验证失败，暂未解锁。请尝试恢复购买。"
                    return
                }
                await refreshEntitlements()
                await transaction.finish()
                message = hasPro ? "已解锁长卷 Pro。" : "购买已完成，正在等待 Apple 同步授权。"
            case .pending: message = "购买等待批准，批准后会自动解锁。"
            case .userCancelled: break
            @unknown default: message = "购买状态未知，请稍后恢复购买。"
            }
        } catch { message = "购买未完成：\(error.localizedDescription)" }
    }

    func restore() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            message = hasPro ? "已恢复你的 Pro 权益。" : "没有找到有效购买，请确认使用了购买时的 Apple 账号。"
        } catch { message = "恢复失败：\(error.localizedDescription)" }
    }
}
