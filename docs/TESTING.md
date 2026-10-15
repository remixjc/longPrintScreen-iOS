# 验证记录

验证日期：2026 年 10 月 15 日。测试截图见 [screenshots](screenshots)。

## 已通过的检查

| 环境 / 检查 | 结果 |
| --- | --- |
| Swift Package 核心与原生图片流水线 | 11 项通过 |
| iOS 集成测试 | 9 项通过 |
| iOS 界面自动化 | 3 项通过 |
| 主 App、相册分享扩展、ReplayKit 广播扩展 | Debug / Release 编译通过 |
| iPhone 真机架构归档 | 已成功生成签名 `.xcarchive` |
| App Store 分发导出 | 已成功生成 Apple Distribution 签名 IPA |
| 签名、App Group 与共享钥匙串 | 主 App 与两个扩展已逐个校验 |

完整 CI 通过记录：https://github.com/remixjc/longPrintScreen-iOS/actions/runs/38671740270

## 自动化覆盖

- 精确重叠、乱序恢复、无重叠保序、手动顺序、固定栏识别、纯色拒绝匹配。
- 截帧去重与上限、非法裁剪值边界。
- 实际图片解码、去重、重排、PNG 导出、像素方向与成品尺寸、损坏图片错误。
- 手动拼接点改变导出高度。
- 共享收件箱仅发布完整批次、保持附件顺序、拒绝路径越界。
- 共享钥匙串授权有效期与撤销。
- 预览刷新不删除仍在分享或保存的导出文件。
- 移除多余截帧并保留两张图片下限。
- 编码真实测试视频，再通过 AVAssetImageGenerator 提取变化帧。
- StoreKit 商品价格和类型：年付 1、周期一年、终身 6、非消耗型。
- 年度购买、到期失效、终身解锁、从已验证本地交易恢复权益、退款撤销。
- 首页示例导入、长图工作台、拼接点微调、排序裁剪入口、相册权限与真实保存。
- 照片选择器取消、录屏使用说明、Pro 页面、隐私政策和页面返回。

## 本地与 CI 的差异

本机使用 Xcode 27。Swift Package 的 11 项测试全部通过，iOS 27 模拟器的 8 项图片 / 导入集成测试全部通过。

本机 iOS 27 测试宿主曾出现启动缓慢、运行器通道断开，以及 StoreKit 本地模拟商品未返回的情况。未将这些运行标记为成功。完整商品与界面流程已在独立 GitHub macOS / iOS 模拟器环境通过。正式 StoreKit 商品仍需真机 Sandbox 或 TestFlight 验证。

另一次 CI 中，`AppStore.sync()` 的真实账号同步使无界面 StoreKitTest 会话等待约十分钟并丢失模拟权益。测试已将账号同步边界注入为可控操作，仍使用 StoreKit 实际验证的本地交易测试恢复权益，并增加同步失败不得解锁的检查。生产环境默认执行 Apple 的 `AppStore.sync()`；真实账号同步明确留待 Sandbox / TestFlight 验收，不把本地模拟通过等同于生产恢复购买通过。

StoreKit 模拟文件位于 `Tests/AppTests/Resources/Products.storekit`，用于测试包和 Xcode 运行配置，不应包含在正式主 App 分发包中。

## 尚未完成的真实环境验收

1. 可连接 iPhone 关闭了开发者模式，Xcode 报 `Developer Mode disabled`。需在设备「设置 → 隐私与安全性 → 开发者模式」开启并按系统提示重启 / 确认，才能运行开发包测试。
2. ReplayKit 跨 App 实际录屏、旋转、暂停恢复、控制中心入口，以及系统相册分享扩展的完整真机交互，必须在设备上验收。自动化已覆盖其共享数据与处理逻辑，但不能替代真实系统流程。
3. App Store Connect 当前没有可用的网页登录会话。尚未完成 App 商店记录、真实订阅 / 终身商品和中国区价格档配置，也未上传 TestFlight 或提交审核。
4. 正式商品价格、退款、购买恢复与到期需在实际 Sandbox / TestFlight 环境复验；本地 StoreKit 测试不会创建商店商品。

发布配置、元数据和逐项验收流程见 [RELEASE.md](RELEASE.md)。
