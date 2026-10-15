# App Store 首次发布记录

更新时间：2026 年 10 月 15 日。此文件记录真实后台操作，不表示 Apple 已批准或 App 已上架。

## 应用与地区

| 项目 | 已配置值 |
| --- | --- |
| App 名称 | 长卷 - 无痕长截图 |
| Apple ID | `6823070070` |
| Bundle ID | `com.remixjc.longPrintScreen` |
| SKU | `longPrintScreen-iOS` |
| 主要语言 | 简体中文 |
| 版本 | `1.0.0` |
| 构建 | `4`，已上传并关联商店版本，已提交，当前「等待审核」 |
| 下载价格 | 免费，基础地区中国大陆 |
| 销售范围 | 仅中国大陆；其他 174 个地区未供应，不自动扩展到未来地区 |
| 平台 | iPhone、iPad；关闭兼容 Mac 与 Apple Vision Pro 供应 |
| 类别 | 工具；摄影与录像 |
| 年龄分级 | 4+ |
| 版本发布 | 通过审核后自动发布 |
| 隐私标签 | 不收集数据，已发布 |
| 审核登录 | 不需要 |

应用后台：<https://appstoreconnect.apple.com/apps/6823070070/distribution>

## 订阅与终身购买

| 项目 | 年度订阅 | 终身解锁 |
| --- | --- | --- |
| 产品 ID | `com.remixjc.longPrintScreen.pro.yearly` | `com.remixjc.longPrintScreen.pro.lifetime` |
| Apple ID | `6823072264` | `6823073458` |
| 类型 | 自动续期订阅，1 年预付 | 非消耗型 |
| 中国大陆价格 | ¥1.00 / 年 | ¥6.00，一次购买 |
| 销售范围 | 仅中国大陆 | 仅中国大陆 |
| 中文显示名称 | 长卷 Pro 年度订阅 | 长卷 Pro 终身解锁 |
| 中文说明 | 按年解锁录屏自动截帧与已有录屏导入，自动续订，可随时取消。 | 一次购买，永久解锁录屏自动截帧与已有录屏导入，不自动续费。 |
| 审核截图 | `docs/screenshots/pro.png` | `docs/screenshots/pro.png` |

订阅群组「长卷 Pro」，ID `22479254`，已有简体中文显示名称。应用版本、年度订阅、终身购买及订阅群组共四项已一起正式提交，后台均显示「等待审核」。

¥1 年订阅及 ¥6 非消耗型价格档均在实际后台确认存在，未替换为其他价格。生产商品的购买、恢复与退款仍需真实 Sandbox / TestFlight 验证；配置完成不代表交易验证通过。

## 商店文案

副标题：截图拼接，录屏自动截帧

推广文本：

> 连续截图，一张呈现。自动识别重叠内容，逐处微调拼接点，保留完整头尾；图片处理在设备上完成。

关键词：`长截图,拼图,截图拼接,长图,滚动截图,录屏,图片拼接`

描述：

> 把精彩，连在一起。长卷将连续截图拼成一张自然衔接的长图：识别重叠、尝试修正乱序，也能逐处微调拼接点。处理过程在设备上完成。
>
> 免费使用相册拼接、自动去重与顺序识别、手动编辑、保存和分享。在系统相册多选图片，还能通过分享入口发送到长卷。
>
> 长卷 Pro 提供录屏自动截屏与已有录屏关键帧导入，适合长文章、聊天记录和较长页面。自动匹配需要连续重叠内容，复杂动态页面可手动校准。
>
> 可选年度自动续订或终身一次性解锁。实际价格以 App Store 购买确认页面为准。年度订阅自动续费，可通过 App Store 订阅设置取消。
>
> 使用条款（Apple 标准 EULA）：https://www.apple.com/legal/internet-services/itunes/dev/stdeula/
>
> 隐私政策：https://github.com/remixjc/longPrintScreen-iOS/blob/main/docs/PRIVACY.md

技术支持：<https://github.com/remixjc/longPrintScreen-iOS/issues>。仓库为公开仓库，Issues 已启用。

版权采用当前发布账户的名称：`2026 cheng wang`。审核联系人采用同一 Apple 开发者账户已有的姓名、电话和邮箱，仅保存至 Apple 后台，不提交到仓库。

## 构建与截图证据

首次上传构建 3 被 Apple 拒绝，错误指向广播扩展缺失 `RPBroadcastProcessMode`。原键错误嵌套在 `NSExtensionAttributes` 中；已参照本机 Xcode 的 Broadcast Upload Extension 官方模板移至 `NSExtension` 直属层级，保留 `RPBroadcastProcessModeSampleBuffer`。

构建 4 已通过 Release Archive、分发导出与 Apple 上传校验。主 App 和两个扩展均为 `1.0.0 (4)`。上传日志 `/tmp/longshot-appstore-upload4.log` 显示 `Upload succeeded` / `EXPORT SUCCEEDED`，后台 TestFlight 可见构建 4。

截图使用应用自带公开示例，不使用用户私人健康截图。原生大屏 iPhone 截图为 1320 × 2868；另有 1206 × 2622 的中屏素材和适配中屏的缩放副本。iPad 截图通过远端模拟器实际运行生成，未将 iPhone 截图拉伸成 iPad 截图。

已上传中屏 iPhone 6 张、大屏 iPhone 4 张，以及 2064 × 2752 的 iPad 13 英寸截图 4 张。版本必填项校验通过。首次合并草稿提示自动续期订阅需随订阅群组提交，已将群组加入同一提交并解除该提示。

截图工作流：`.github/workflows/app-store-screenshots.yml`，仅手动触发，使用公开示例 UI 测试。成功运行：

<https://github.com/remixjc/longPrintScreen-iOS/actions/runs/38702289088>

本地素材和操作截图保存在被 Git 忽略的 `artifacts/AppStore/`；正式 IPA 同样不入库。

## 正式提交回执

- 提交时间：2026 年 10 月 15 日 16:14（后台本地时间，GMT+8）。
- 提交 ID：`78465448-563c-45ab-aa0c-829f13c43f5d`。
- 后台回执：「已提交 4 个项目」，审核详情四项均为「等待审核」。
- 审核详情：<https://appstoreconnect.apple.com/apps/6823070070/distribution/reviewsubmissions/details/78465448-563c-45ab-aa0c-829f13c43f5d>。
- 本地截图：`artifacts/AppStore/evidence/submission-success.png`、`artifacts/AppStore/evidence/submitted-waiting-review.png`。

## 账户及资质事项

- 开始准备时，新版《Apple Developer Program License Agreement》待接受。最终提交前刷新账户页面，后台已显示 2026 年 10 月 14 日签发的协议于 2026 年 10 月 15 日接受，待接受提示已消失；本次代理未点击协议「同意」。
- 付费 App 协议当前有效，银行账户可用，现有报税表使用中。另有国务院令第 810 号税务合规信息缺失提醒，涉及个人税务资料，需账户持有人处理。
- 未提供或编造 ICP 备案号。Apple 官方帮助说明部分 App 需备案，并要求适用时填写；当前提交前校验尚未提示本应用缺少备案号。是否要求补充以实际资质与 Apple 后续审核为准。

官方应用信息说明：<https://developer.apple.com/help/app-store-connect/reference/app-information/app-information>

当前已提交最终审核，尚未审核通过或上架。设置为审核通过后自动发布，仅中国大陆供应。
