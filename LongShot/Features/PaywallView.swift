import SwiftUI
import StoreKit

struct PaywallView: View {
    @EnvironmentObject private var purchases: PurchaseStore
    @Environment(\.dismiss) private var dismiss
    @State private var selected = AppConfiguration.annualProduct
    @State private var legal: LegalPage?
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 25) {
                        ZStack {
                            Circle().fill(Theme.purple.opacity(0.16)).frame(width: 100, height: 100)
                            Image(systemName: "sparkles.rectangle.stack").font(.system(size: 42)).foregroundStyle(Theme.purple)
                        }.padding(.top, 12)
                        VStack(spacing: 10) {
                            Text(purchases.hasPro ? "你的长卷 Pro 已就绪" : "让长图，一气呵成").font(.system(size: 27, weight: .bold))
                            Text("长卷 Pro").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.purple)
                        }
                        Card {
                            VStack(alignment: .leading, spacing: 20) {
                                feature("record.circle", title: "录屏自动截屏", detail: "滑动页面，自动捕捉不同画面")
                                feature("video.badge.waveform", title: "导入已有录屏", detail: "从录屏中提取关键帧并拼接")
                                feature("lock.shield", title: "只在设备上处理", detail: "不上传图片或录屏，不录制麦克风")
                            }
                        }
                        if purchases.hasPro {
                            Label(purchases.isLifetime ? "终身权益已解锁" : "年度权益有效",
                                  systemImage: "checkmark.seal.fill").foregroundStyle(Theme.green)
                            if let expiry = purchases.expiration, !purchases.isLifetime {
                                Text("有效期至 \(expiry.formatted(date: .abbreviated, time: .omitted))")
                                    .font(.caption).foregroundStyle(Theme.muted)
                            }
                        } else {
                            VStack(spacing: 12) {
                                plan(id: AppConfiguration.annualProduct, title: "年度订阅", target: "¥1 / 年", caption: "每年自动续订，可随时取消")
                                plan(id: AppConfiguration.lifetimeProduct, title: "终身解锁", target: "¥6 一次付费", caption: "一次购买，永久使用 Pro")
                            }
                            Button {
                                if let product = purchases.products.first(where: { $0.id == selected }) {
                                    Task { await purchases.purchase(product) }
                                }
                            } label: {
                                if purchases.busy { ProgressView().tint(Theme.background) }
                                else { Text(purchaseTitle) }
                            }.buttonStyle(PrimaryButton(color: Theme.purple))
                                .disabled(purchases.busy || purchases.products.first(where: { $0.id == selected }) == nil)
                                .opacity(purchases.products.isEmpty ? 0.5 : 1).accessibilityIdentifier("purchasePro")
                        }
                        if let message = purchases.message {
                            Text(message).font(.subheadline).foregroundStyle(Theme.muted)
                                .multilineTextAlignment(.center).accessibilityIdentifier("purchaseMessage")
                        }
                        HStack(spacing: 24) {
                            Button("恢复购买") { Task { await purchases.restore() } }.accessibilityIdentifier("restorePurchases")
                            if purchases.products.isEmpty {
                                Button("重新加载") { Task { await purchases.reload() } }
                            }
                        }.font(.subheadline).foregroundStyle(Theme.purple).disabled(purchases.busy)
                        Text("免费功能包含相册拼接、自动去重与排序、手动编辑、保存和分享。年度订阅自确认购买起按年自动续订，费用由 Apple 账号扣取；请在当前周期结束前至少 24 小时通过 App Store 订阅设置取消。终身为非消耗型一次性购买，不自动续费。")
                            .font(.system(size: 11)).foregroundStyle(Theme.muted).lineSpacing(4)
                        HStack(spacing: 24) {
                            Button("隐私政策") { legal = .privacy }
                            Button("使用条款") { legal = .terms }
                            Link("Apple 标准 EULA", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                        }.font(.caption).foregroundStyle(Theme.muted)
                    }.padding(24).frame(maxWidth: 600).frame(maxWidth: .infinity)
                }
            }.navigationTitle("长卷 Pro").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } } }
                .sheet(item: $legal) { LegalView(page: $0) }
                .task { if purchases.products.isEmpty { await purchases.reload() } }
        }.preferredColorScheme(.dark)
    }
    private var purchaseTitle: String {
        guard let product = purchases.products.first(where: { $0.id == selected }) else { return "商品加载中" }
        return selected == AppConfiguration.annualProduct ? "订阅 · \(product.displayPrice) / 年" : "终身解锁 · \(product.displayPrice)"
    }
    private func feature(_ icon: String, title: String, detail: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.title3).foregroundStyle(Theme.purple).frame(width: 28)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(Theme.muted)
            }
        }
    }
    private func plan(id: String, title: String, target: String, caption: String) -> some View {
        let product = purchases.products.first { $0.id == id }
        return Button { selected = id } label: {
            HStack(spacing: 14) {
                Image(systemName: selected == id ? "largecircle.fill.circle" : "circle")
                    .font(.title3).foregroundStyle(selected == id ? Theme.purple : Theme.muted)
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.headline)
                    Text(caption).font(.caption).foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 4) {
                    Text(product.map { $0.displayPrice + (id == AppConfiguration.annualProduct ? " / 年" : "") } ?? target)
                        .font(.headline).foregroundStyle(Theme.purple)
                    if product == nil { Text("目标价格，待商店确认").font(.system(size: 9)).foregroundStyle(Theme.muted) }
                }
            }.padding(18).background(Theme.card, in: RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(selected == id ? Theme.purple : Theme.inset, lineWidth: 1.5))
        }.buttonStyle(.plain).accessibilityIdentifier(id == AppConfiguration.annualProduct ? "annualPlan" : "lifetimePlan")
    }
}
