# 验证记录

验证日期：2026 年 10 月 15 日。测试截图见 [screenshots](screenshots)。

## Build 3：实际健康截图的半透明栏与圆角遮挡

Build 2 的生成式回归没有覆盖用户提供的健康 App 截图：半透明悬浮栏会随正文改变，底部圆角与主屏幕指示条还会遮住重叠正文。这五张图在旧算法中四处均未匹配，输出高度为 14340，实际应为 8985。

现在从截图内部的文字与边缘特征寻找滚动位移，再验证连续共享正文；同时保留左侧行号等区分重复段落的细节，避免仅凭相同句子误匹配。每处连接分别保存上图底部裁剪和下图顶部去重，预览、导出及“恢复此处自动值”均应用两侧裁剪。窄滚动条只在外侧背景一致、形状符合指示条时清除。

用户素材按反序导入后自动恢复顺序，识别位移为 2114、1721、1741、541 像素，生成 1320 × 8985 的长图。测试检查四次位移、整图尺寸、整页和每处接缝与用户 JPEG 参考图的像素差异；只允许 JPEG 压缩和色彩转换误差。原始截图与成品只保存在本机，不包含在仓库或 CI 附件中。

本地 Release 配置的 Swift Package 测试共 21 项全部通过，包含实际素材对照、新增的变化顶底栏、短重叠及滚动条形状检查。原有无重叠、重复排版、PNG / JPEG、首尾保留与手动编辑回归仍通过。

复现私有素材对照（目录中放置 `IMG_5758.PNG` 至 `IMG_5762.PNG` 和参考 `IMG_5763.JPG`）：

```sh
LONGSHOT_HEALTH_FIXTURES=/path/to/local/screenshots \
LONGSHOT_HEALTH_ARTIFACTS="$PWD/artifacts/HealthRegression" \
  swift test -c release --scratch-path /tmp/longshot-health-release --jobs 2
```

未提供素材目录时，该私有用例会明确跳过，其他回归继续执行。iOS 测试也可从测试宿主的 `Documents/HealthRegression` 读取同一组素材，并经过 `WorkspaceModel.importBatch`、默认编辑参数、预览和高清导出验证。

## Build 2：连续长截图修复

修复真机反馈的整张堆叠问题：匹配图保留手机截图的纵向像素，使用分区亮度 / 边缘特征逐行搜索，再用像素细节校验和精修拼接点。匹配误差按内容对比度归一化，避免白底文字被低纹理阈值拒绝。固定栏允许时间 / 数字局部变化；合成保留首张顶部与末张底部，仅去除中间固定栏及重复正文。

新增回归使用 CoreText 绘制的 1170 × 2532 中文阅读截图，包含固定顶栏、底栏、变化的时间 / 收藏数和滚动条。测试对照完整原文，检查中间没有缺行、重复正文或固定栏，并对首尾区域逐像素校验。覆盖 PNG、JPEG、乱序、无重叠、稀疏文字及重复排版歧义。

本地 Swift Package 的 17 项测试全部通过。iPhone 18 Pro Max（iOS 27.0.1）上的 14 项图片 / 导入集成测试全部通过，其中包含 6 项图片流水线回归。真机另外通过编辑 / 拼接点 / 排序流程、照片选择器取消、录屏 / 订阅 / 法律页面共 3 项界面检查。

真机保存检查在 `PHPhotoLibrary.requestAuthorization` 阶段遇到系统 Face ID 验证，未返回保存成功；此项没有记为通过。测试录像和系统辅助功能层级均显示 `LocalAuthenticationUIService`。已把保存检查分为独立用例，其余编辑流程单独在真机重跑通过；未尝试绕过生物识别。

主 App 与两个扩展已成功 Release 编译、归档并导出 1.0.0 (2) 分发 IPA，三个 bundle 的 Apple Distribution 签名与 build 2 版本已校验，包内不含 StoreKit 模拟文件。手机已安装 build 2 开发包。

更新后的[预览](screenshots/editor.png)、[拼接点](screenshots/seam.png)、[裁剪与排序](screenshots/arrangement.png)来自本次真机自动化。[连续长图样本](screenshots/continuous-stitch.png)来自原文逐像素对照的回归用例。

CI 将 StoreKit 回归放在独立任务，避免本地交易服务卡住时阻塞图片 / 界面验收。每条测试设置 120 秒默认、180 秒最大执行时间；购买失败最多重启测试进程重试一次，失败仍使 CI 报错。

本次修复的 [CI 验收任务](https://github.com/remixjc/longPrintScreen-iOS/actions/runs/38691018754/job/116276698058)全部通过：17 项 Swift Package 测试、14 项 iOS 图片 / 导入集成测试、4 项界面测试，共 35 项。模拟器中的 `testSaveDemoToPhotos` 实际保存到相册并收到成功提示。独立 StoreKit 任务的结果不包含在这 35 项中。

同一轮的[独立购买回归](https://github.com/remixjc/longPrintScreen-iOS/actions/runs/38691018754/job/116276698325)未通过：恢复同步失败用例通过，年度 / 终身交易用例在两次独立进程中均超过 120 秒执行上限。该 CI 轮次整体为失败，不能称作全量通过。本次没有更改生产购买逻辑；购买测试仍需单独诊断并在 Sandbox / TestFlight 验证。

可复现测试并保留输入 / 成品：

```sh
LONGSHOT_STITCH_ARTIFACTS="$PWD/artifacts/StitchRegression" \
  swift test --scratch-path /tmp/longshot-core-build --jobs 2
```

不重叠、纯色或高度重复而不能可靠定位的图片仍提示手动调整；不能凭空补回没有拍到的正文。固定栏样式大幅变化时可在「顺序与裁剪」调整中间固定栏范围。

## Build 1 的既有验证记录

| 环境 / 检查 | 结果 |
| --- | --- |
| Swift Package 核心与原生图片流水线 | 11 项通过 |
| iOS 集成测试 | 10 项通过 |
| iOS 界面自动化 | 3 项通过 |
| 主 App、相册分享扩展、ReplayKit 广播扩展 | Debug / Release 编译通过 |
| iPhone 真机架构归档 | 已成功生成签名 `.xcarchive` |
| App Store 分发导出 | 已成功生成 Apple Distribution 签名 IPA |
| 签名、App Group 与共享钥匙串 | 主 App 与两个扩展已逐个校验 |

此前代码的完整 CI 通过记录：https://github.com/remixjc/longPrintScreen-iOS/actions/runs/38674254858

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
- 账号同步失败时不授予 Pro，显示错误并结束忙碌状态。
- 首页示例导入、长图工作台、拼接点微调、排序裁剪入口、相册权限与真实保存。
- 照片选择器取消、录屏使用说明、Pro 页面、隐私政策和页面返回。

## 本地与 CI 的差异

本机使用 Xcode 27。Swift Package 的 11 项测试全部通过，iOS 27 模拟器的 8 项图片 / 导入集成测试全部通过。

本机 iOS 27 测试宿主曾出现启动缓慢、运行器通道断开，以及 StoreKit 本地模拟商品未返回的情况。未将这些运行标记为成功。完整商品与界面流程已在独立 GitHub macOS / iOS 模拟器环境通过。正式 StoreKit 商品仍需真机 Sandbox 或 TestFlight 验证。

另一次 CI 中，`AppStore.sync()` 的真实账号同步使无界面 StoreKitTest 会话等待约十分钟并丢失模拟权益。测试已将账号同步边界注入为可控操作，仍使用 StoreKit 实际验证的本地交易测试恢复权益，并增加同步失败不得解锁的检查。生产环境默认执行 Apple 的 `AppStore.sync()`；真实账号同步明确留待 Sandbox / TestFlight 验收，不把本地模拟通过等同于生产恢复购买通过。

StoreKit 模拟文件位于 `Tests/AppTests/Resources/Products.storekit`，用于测试包和 Xcode 运行配置，不应包含在正式主 App 分发包中。

## 尚未完成的真实环境验收

1. iPhone 开发者模式已开启，解锁后集成测试已通过。相册保存触发的系统 Face ID 验证需要机主配合，自动化未完成此步。
2. ReplayKit 跨 App 实际录屏、旋转、暂停恢复、控制中心入口，以及系统相册分享扩展的完整真机交互，必须在设备上验收。自动化已覆盖其共享数据与处理逻辑，但不能替代真实系统流程。
3. App Store Connect 当前没有可用的网页登录会话。尚未完成 App 商店记录、真实订阅 / 终身商品和中国区价格档配置，也未上传 TestFlight 或提交审核。
4. 正式商品价格、退款、购买恢复与到期需在实际 Sandbox / TestFlight 环境复验；本地 StoreKit 测试不会创建商店商品。

发布配置、元数据和逐项验收流程见 [RELEASE.md](RELEASE.md)。
