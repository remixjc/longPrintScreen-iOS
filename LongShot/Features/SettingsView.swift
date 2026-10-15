import SwiftUI
import StoreKit

enum LegalPage: String, Identifiable { case privacy, terms; var id: String { rawValue } }

struct SettingsView: View {
    @EnvironmentObject private var purchases: PurchaseStore
    @State private var showPro = false
    @State private var showGuide = false
    @State private var legal: LegalPage?
    @State private var showManageSubscriptions = false
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 22) {
                        Card {
                            HStack(spacing: 18) {
                                Image(systemName: "rectangle.portrait.on.rectangle.portrait")
                                    .font(.system(size: 30)).foregroundStyle(Theme.purple)
                                    .frame(width: 65, height: 65).background(Theme.purple.opacity(0.12), in: RoundedRectangle(cornerRadius: 20))
                                VStack(alignment: .leading, spacing: 7) {
                                    Text("长卷").font(.title2.bold())
                                    Text("留住每一屏的精彩").font(.caption).foregroundStyle(Theme.muted)
                                }
                                Spacer()
                                if purchases.hasPro { ProBadge() }
                            }
                        }
                        Button { showPro = true } label: {
                            Card {
                                HStack {
                                    VStack(alignment: .leading, spacing: 7) {
                                        Text(purchases.hasPro ? "管理 Pro 权益" : "解锁长卷 Pro").font(.headline).foregroundStyle(Theme.purple)
                                        Text("录屏自动截屏 · 录屏关键帧导入").font(.caption).foregroundStyle(Theme.muted)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").foregroundStyle(Theme.muted)
                                }
                            }
                        }.buttonStyle(.plain).accessibilityIdentifier("openPro")
                        Card {
                            VStack(spacing: 0) {
                                row("使用指南", icon: "questionmark.circle") { showGuide = true }
                                Divider().overlay(.white.opacity(0.04))
                                row("管理 Apple 订阅", icon: "creditcard") { showManageSubscriptions = true }
                                Divider().overlay(.white.opacity(0.04))
                                row("隐私政策", icon: "hand.raised") { legal = .privacy }
                                Divider().overlay(.white.opacity(0.04))
                                row("使用条款", icon: "doc.text") { legal = .terms }
                            }
                        }
                        Text("长卷 1.0.0\n无广告 · 无需账号 · 本机处理").font(.caption).foregroundStyle(Theme.muted)
                            .multilineTextAlignment(.center).lineSpacing(7).padding(.vertical, 15)
                    }.padding(20).frame(maxWidth: 680).frame(maxWidth: .infinity)
                }
            }.navigationTitle("我的").navigationBarTitleDisplayMode(.inline)
                .sheet(isPresented: $showPro) { PaywallView() }
                .sheet(isPresented: $showGuide) { GuideView() }
                .sheet(item: $legal) { LegalView(page: $0) }
                .manageSubscriptionsSheet(isPresented: $showManageSubscriptions)
        }
    }
    private func row(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 13) {
                Image(systemName: icon).foregroundStyle(Theme.muted).frame(width: 25)
                Text(title).font(.subheadline)
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.muted)
            }.padding(.vertical, 18)
        }.buttonStyle(.plain)
    }
}

struct GuideView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    guide("1. 选连续截图", "按从上到下的顺序选择，每两张保留约三分之一重叠内容。最多选择 20 张。")
                    guide("2. 检查自动拼接", "自动去除重复区域、尝试识别固定栏。乱序图片有足够重叠时会自动排列；无法确定则保留选择顺序，并提示检查。")
                    guide("3. 微调每个拼接点", "在「拼接点」中调节下张顶部去重与上张底部裁剪，紫线处就是连接位置；可用加减按钮逐像素微调。")
                    guide("4. 保存或分享", "在长图预览里双指缩放检查，点「保存到相册」，或点右侧分享按钮。超大长图会适当缩小以稳定导出。")
                    guide("从相册分享导入", "在系统相册多选图片 → 分享 →「导入长卷」。如未显示，在「更多」里启用。发送后回到长卷首页，点待导入卡片即可拼接。")
                    guide("录屏自动截屏 · Pro", "在「录屏」页阅读说明并启动系统录屏，切换到目标页面，竖屏缓慢向下滑。结束录屏后回到长卷导入。录屏时请避开敏感内容。")
                    guide("哪些场景需要手动处理？", "无重叠、横向滚动、复杂动画、固定悬浮弹窗、页面大面积相似或方向变化，都可能影响匹配。此时调整顺序和裁剪，或重新截取连续图片。")
                }.padding(24).frame(maxWidth: 640).frame(maxWidth: .infinity)
            }.background(Theme.background).navigationTitle("拼接指南").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } } }
        }.preferredColorScheme(.dark)
    }
    private func guide(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline).foregroundStyle(Theme.green)
            Text(detail).font(.subheadline).foregroundStyle(Theme.muted).lineSpacing(5)
        }
    }
}

struct LegalView: View {
    let page: LegalPage
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                Text(page == .privacy ? Self.privacy : Self.terms)
                    .font(.subheadline).foregroundStyle(Theme.muted).lineSpacing(7).padding(24)
                    .frame(maxWidth: 640, alignment: .leading).frame(maxWidth: .infinity)
            }.background(Theme.background)
                .navigationTitle(page == .privacy ? "隐私政策" : "使用条款").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } } }
        }.preferredColorScheme(.dark)
    }
    static let privacy = """
    长卷隐私政策
    生效日期：2026 年 10 月 15 日

    长卷由 remixjc 开发，是一款在设备上处理图片的长截图工具，无需注册账号。

    图片与录屏
    你通过系统选择器或分享扩展选取的图片，仅用于本次拼接。使用 Pro 录屏时，iOS 会要求你主动确认，系统也会显示录屏指示。长卷只提取屏幕画面，不采集麦克风或保存音频，不把图片或录屏上传到服务器。

    权限与保存
    选图使用系统照片选择器，不读取整个相册。只有你点保存时，才请求添加照片权限。原图不会被修改或删除。

    本地数据
    分享导入和录屏截帧暂存于 App 的共享空间，供主 App 导入。导入成功后删除原暂存组；待导入组会在下次打开 App 时清理超过七天的数据，也可在首页手动删除。工作台临时文件在结束编辑时清除。卸载 App 会清理 App 自身的数据，已保存到相册的长图不受影响。

    购买
    购买与付款由 Apple 处理。长卷使用 Apple 验证的交易状态判断权益，并在本机钥匙串短期保存录屏授权，不获取你的银行卡信息。

    数据收集与第三方
    不使用广告、统计追踪或第三方分析 SDK，不收集用于身份识别的个人信息。Apple 可能依据其政策处理交易或系统诊断数据。

    控制与联系
    你可在 iOS 设置中撤回照片添加权限，在系统录屏指示处停止录屏，在 App Store 管理订阅。隐私相关问题可通过项目支持页面联系：
    https://github.com/remixjc/longPrintScreen-iOS/issues
    """
    static let terms = """
    长卷使用条款
    生效日期：2026 年 10 月 15 日

    服务内容
    长卷提供图片拼接、重叠检测、顺序识别与手动编辑。自动识别结果取决于图片内容，请在保存前检查。无重叠、动态页面或大面积重复内容可能需要手动调整。

    免费与 Pro
    相册拼接、分享导入、手动编辑、保存与分享免费。录屏自动截屏与已有录屏导入需有效 Pro 权益。年度订阅计划目标为人民币 1 元/年，终身解锁目标为人民币 6 元一次性购买；实际交易以 Apple 购买页面显示的当地货币价格为准。

    订阅与取消
    年度订阅按年自动续订，由 Apple 账号付款。请至少在当前周期结束前 24 小时前往 App Store 订阅设置取消，取消后可继续使用至当前有效期结束。终身解锁为非消耗型购买，不自动续费。可使用相同 Apple 账号恢复购买。退款由 Apple 按其适用政策处理。

    合理使用
    请仅处理你有权使用的内容，并在录屏前确认屏幕不会暴露你或他人的敏感信息。不得利用长卷侵犯隐私、知识产权或其他合法权益。

    可用性与支持
    受系统限制和被录制 App 的保护机制影响，部分页面无法捕捉。过大的长图会缩小导出。应用内没有云端内容备份。请及时保存需要的成品。

    Apple 标准最终用户许可协议同时适用：
    https://www.apple.com/legal/internet-services/itunes/dev/stdeula/

    支持：
    https://github.com/remixjc/longPrintScreen-iOS/issues
    """
}
