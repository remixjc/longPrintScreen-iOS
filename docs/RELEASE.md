# 上架配置与验收

代码与本地测试不等于 App Store 上架完成。以下依赖开发者账号、真机、商店商品或地区信息，必须在真实发布环境完成。

## 1. 签名

在 Xcode 登录开发者账号，确认正确 Team。当前项目默认 Team `M898TXZKKP`，本机另有 `6NZHLN3MUD` 的分发证书，不能据此假定两者属于同一个发布账号。

在开发者后台注册：

| 类型 | 标识 |
| --- | --- |
| 主 App | `com.remixjc.longPrintScreen` |
| 分享扩展 | `com.remixjc.longPrintScreen.share` |
| 录屏扩展 | `com.remixjc.longPrintScreen.broadcast` |
| App Group | `group.com.remixjc.longPrintScreen` |
| 共享钥匙串后缀 | `com.remixjc.longPrintScreen.shared` |

三个 target 都关联 App Group。主 App 和录屏扩展共享相同 Keychain Group；完整钥匙串前缀以账号实际 AppIdentifierPrefix 为准，不应手写假定 Team ID。

重新生成项目：`xcodegen generate`。在 Signing & Capabilities 确认自动签名可生成所有描述文件；修改 bundle ID 时同步修改 `Shared/AppConfiguration`、entitlements、产品 ID 和广播 picker 标识。

## 2. App Store Connect 商品

先完成开发者协议、付费 App 协议、税务与银行配置，然后在 App Store Connect 创建 App 记录和以下商品：

| 产品 ID | 类型 | 周期 | 中国大陆目标价格 |
| --- | --- | --- | --- |
| `com.remixjc.longPrintScreen.pro.yearly` | 自动续期订阅 | 1 年 | ¥1 |
| `com.remixjc.longPrintScreen.pro.lifetime` | 非消耗型 | 永久 | ¥6 |

年度放在「长卷 Pro」订阅组，添加简体中文名称、说明和审核截图；终身为独立非消耗型商品，不能创建为自动续期订阅。两个商品解锁完全相同功能，不要向已有终身用户再次推荐年订阅。

正式可用价格档必须在后台确认，特别是年订阅 ¥1 档。若商店不提供所需价格，不可用代码绕过或在购买页面显示虚假价格；需先确定可选价格再发布。UI 购买按钮使用 StoreKit 的 `displayPrice`。

`Products.storekit` 只用于 Xcode 本地测试。生产 Archive 不会把本地交易视作正式权益；应在真机 Sandbox / TestFlight 测试真实商品配置。

## 3. 真机验收

- 免费状态：相册多选、自动去重、乱序恢复、无重叠回退提示、逐处微调、裁剪、换序、PNG 分享与相册保存。
- 系统照片权限：拒绝保存有可理解提示；撤销权限后不崩溃；仅选择图片不请求全相册权限。
- 分享：系统相册选 2、3、20 张 → 分享「导入长卷」；顺序应与分享附件一致；取消不残留完整批次；主 App 可发现、导入、删除。首次需在系统分享「更多」启用。
- 年度购买、取消购买、待批准、续订、到期、退款、恢复购买、网络不可用。
- 终身购买、重新安装后的恢复、退款撤销、年度和终身同时存在时避免重复购买引导。
- 免费用户直接从控制中心选择广播扩展应被拒绝；Pro 用户启动系统录屏，竖屏连续滑动，停止后回 App 导入。
- 录屏暂停恢复、旋转方向、60 帧上限、中途授权过期、低内存与系统终止。
- 导入 3 分钟以内录屏，静止帧去重；过长视频给出裁剪说明；DRM 视频、损坏文件有错误反馈。
- iPhone 与 iPad 上的分享弹窗、横屏布局、动态字体、VoiceOver 控件标签。

跨 App ReplayKit、App Group 真机签名、真实商店商品和退款均不能只凭模拟器成功认定通过。

## 4. 元数据

建议名称：长卷 - 无痕长截图

副标题：截图拼接，录屏自动截帧

关键词：长截图,拼图,截图拼接,长图,滚动截图,录屏,图片拼接

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

隐私 URL 可使用公开仓库中 `docs/PRIVACY.md` 的永久链接；支持 URL 可使用仓库 Issues。上线前确认公开页面可访问，且开发者联系信息与账号主体一致。App Privacy 表单基于最终代码填写，不包含广告和第三方分析；本 App 不主动收集数据。

如面向中国大陆发行，在 App Store Connect 确认适用的备案、资质与地区要求，并提供实际主体信息。不可虚构备案号。

## 5. 归档与上传

先在真机通过验收，再使用正确发布 Team：

```sh
xcodebuild -project LongShot.xcodeproj -scheme LongShot \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath /tmp/LongShot.xcarchive archive
```

在 Xcode Organizer 中 Validate App → Distribute App → App Store Connect。提交时补齐 iPhone / iPad 截图、年龄分级、隐私声明、出口合规、审核说明，并关联首批内购商品。没有 App Store Connect 登录或 API 凭据时，不能凭本地开发证书代替上传权限。

审核说明应写清：不需要登录；免费截图功能在首页；Pro 入口在录屏页/我的；录屏使用系统确认，只本地截帧，不传输直播内容。

## 官方参考

- https://developer.apple.com/cn/app-store/review/guidelines/
- https://developer.apple.com/help/app-store-connect/manage-app-pricing/set-a-price/
- https://developer.apple.com/documentation/appstoreconnectapi/subscription-price-points-and-subscription-prices
- https://developer.apple.com/documentation/replaykit/rpsystembroadcastpickerview
