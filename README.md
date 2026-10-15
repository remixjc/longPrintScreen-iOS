# 长卷 · LongShot

以深色卡片、紫色渐变与荧绿色强调为视觉语言的 iPhone / iPad 长截图工具。SwiftUI、StoreKit 2、PhotosUI、ReplayKit 原生实现，无第三方运行时 SDK。

## 功能

- 按选择顺序导入最多 20 张图片，自动识别重叠、移除完全重复图片、识别固定顶部/底部区域。
- 根据连续重叠内容尝试纠正乱序。只在能形成可靠连续链时重排，模糊或无重叠时保留原顺序并提示。
- 每个拼接点单独调节下图顶部去重和上图底部裁剪，支持逐像素微调、图片换序、全局裁剪。
- 长图预览、双指/双击缩放、PNG 导出、保存相册、系统分享。超大图最多约 3200 万像素，自动缩小控制内存。
- Photos 分享扩展：相册多选 → 分享 →「导入长卷」→ 回到长卷首页导入。
- Pro：ReplayKit 跨 App 录屏自动截帧、已有录屏关键帧导入。每组最多 60 帧，已有视频最多 3 分钟。
- StoreKit 2：年度自动续订（目标中国区 ¥1/年）和终身非消耗型购买（目标 ¥6）。价格以商店返回值为准；支持验证、恢复、到期与撤销处理。

## 开发

需要 Xcode 16 或更新版本、iOS 17+；本项目在 Xcode 27 / iOS 27 模拟器验证。

```sh
brew install xcodegen
xcodegen generate
open LongShot.xcodeproj
swift test --scratch-path /tmp/longshot-core-build
```

选择 `LongShot` Scheme。Debug 运行关联 `Products.storekit`，可本地模拟购买；该文件**不会创建真实 App Store 商品**。终身和年度解锁同一套 Pro 功能，基础拼接保持免费。

```sh
xcodebuild -project LongShot.xcodeproj -scheme LongShot \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
  -derivedDataPath /tmp/LongShotDerived \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO test
```

为避免 macOS Documents 的扩展属性影响测试签名，建议将构建目录放在 `/tmp` 或 Xcode 默认 DerivedData。

## 项目结构

| 目录 | 作用 |
| --- | --- |
| `LongShot` | 主 App、工作台、支付与本地文件处理 |
| `Sources/StitchCore` | 可独立测试的灰度重叠匹配、排序、裁剪和截帧策略 |
| `Shared` | 图片读写、App Group 收件箱、共享钥匙串授权、隐私清单 |
| `ShareExtension` | 相册分享扩展，按附件顺序保存图片 |
| `BroadcastExtension` | ReplayKit 视频帧处理，不采集或保存音频 |
| `Tests` | 核心算法、实际图片合成、StoreKit、UI 自动化 |
| `docs` | 上架配置、隐私、条款、测试记录 |

## 真机与上架

App ID 为 `com.remixjc.longPrintScreen`，两个扩展后缀为 `.share` 和 `.broadcast`。App Group 为 `group.com.remixjc.longPrintScreen`。主 App 和录屏扩展需共享钥匙串访问组。默认开发 Team 取本机已有开发证书的 `M898TXZKKP`，请在上架前确认所属账号正确。

完整配置和必须在真机 / App Store Connect 完成的验收见 [上架说明](docs/RELEASE.md)。ReplayKit 跨 App 录屏不能用模拟器测试代替；模拟器购买使用 StoreKit 本地环境，不能代替沙盒或 TestFlight 验证。

图片不上传、不修改原图；待导入内容在设备本地保留最多七天，并可主动删除。见 [隐私政策](docs/PRIVACY.md) 与 [使用条款](docs/TERMS.md)。
