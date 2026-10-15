import SwiftUI
import ReplayKit
import PhotosUI
import UniformTypeIdentifiers

struct RecordingView: View {
    @EnvironmentObject private var purchases: PurchaseStore
    @EnvironmentObject private var workspace: WorkspaceModel
    @State private var showPro = false
    @State private var showVideoPicker = false
    @State private var acceptedPrivacy = false
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        HStack {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("轻轻滑动\n长图自然发生").font(.system(size: 30, weight: .bold)).lineSpacing(5)
                                Text("录屏自动截屏").font(.subheadline).foregroundStyle(Theme.muted)
                            }
                            Spacer()
                            Image(systemName: "record.circle").font(.system(size: 57, weight: .ultraLight)).foregroundStyle(Theme.purple)
                        }.padding(.top, 15)
                        Card {
                            VStack(alignment: .leading, spacing: 22) {
                                HStack { Text("三步，记录整页").font(.headline); Spacer(); ProBadge() }
                                step("1", title: "开始录屏", detail: "点下方系统录屏按钮，选择「长卷自动截屏」，再点「开始直播」。")
                                step("2", title: "切换页面，缓慢向下滑", detail: "保持竖屏，每次滑动不超过半屏；开头和结尾各停留一秒，避免来回滑动。")
                                step("3", title: "停止并回到长卷", detail: "点屏幕顶部录屏标记停止，回到「拼接」页导入截帧，检查拼接点后保存。")
                            }
                        }
                        if purchases.hasPro {
                            Card {
                                VStack(alignment: .leading, spacing: 16) {
                                    Toggle(isOn: $acceptedPrivacy) {
                                        Text("我已了解录屏会包含屏幕可见内容").font(.subheadline)
                                    }.tint(Theme.purple)
                                    Text("请先开启勿扰模式，避开密码、支付页和私人通知。仅提取画面，不保存音频、不上传。")
                                        .font(.caption).foregroundStyle(Theme.muted)
                                    if acceptedPrivacy && RecordingAuthorization.isValid {
                                        HStack {
                                            BroadcastPicker().frame(width: 52, height: 52)
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text("点击左侧系统按钮").font(.headline)
                                                Text("录屏由 iOS 确认与控制").font(.caption).foregroundStyle(Theme.muted)
                                            }
                                        }.accessibilityIdentifier("broadcastControls")
                                    } else if acceptedPrivacy {
                                        Button("刷新录屏授权") { Task { await purchases.refreshEntitlements() } }
                                            .foregroundStyle(Theme.purple)
                                        Text("授权同步后将显示录屏按钮。").font(.caption).foregroundStyle(Theme.muted)
                                    }
                                }
                            }
                        } else {
                            Button { showPro = true } label: {
                                Label("解锁 Pro，开始录屏截屏", systemImage: "sparkles")
                            }.buttonStyle(PrimaryButton(color: Theme.purple)).accessibilityIdentifier("unlockRecording")
                        }
                        Button {
                            if purchases.hasPro { showVideoPicker = true } else { showPro = true }
                        } label: {
                            Card {
                                HStack(spacing: 14) {
                                    Image(systemName: "video.badge.plus").font(.title2).foregroundStyle(Theme.cyan)
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text("已有录屏？直接导入").font(.headline)
                                        Text("最多 3 分钟，自动提取关键帧").font(.caption).foregroundStyle(Theme.muted)
                                    }
                                    Spacer(minLength: 0)
                                    Image(systemName: "chevron.right").foregroundStyle(Theme.muted)
                                }
                            }
                        }.buttonStyle(.plain).accessibilityIdentifier("importVideo")
                        Text("每次最多保留 60 张关键帧，达到上限会结束本次截帧。受保护视频、部分系统页面可能无法捕捉；没有连续重叠内容时需手动调整。")
                            .font(.caption).foregroundStyle(Theme.muted).lineSpacing(4)
                        if !workspace.pendingBatches.isEmpty {
                            Label("已有 \(workspace.pendingBatches.count) 组待导入，请前往「拼接」页。", systemImage: "tray.and.arrow.down")
                                .font(.subheadline).foregroundStyle(Theme.green)
                        }
                    }.padding(20).frame(maxWidth: 680).frame(maxWidth: .infinity)
                }
            }.navigationTitle("录屏").navigationBarTitleDisplayMode(.inline)
                .sheet(isPresented: $showPro) { PaywallView() }
                .sheet(isPresented: $showVideoPicker) {
                    VideoPicker { url in
                        Task {
                            defer { try? FileManager.default.removeItem(at: url) }
                            guard purchases.hasPro else { return }
                            await workspace.importVideo(url: url)
                        }
                    }.ignoresSafeArea()
                }
        }
    }
    private func step(_ number: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text(number).font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.purple).frame(width: 27, height: 27)
                .background(Theme.purple.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 7) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(Theme.muted).lineSpacing(4)
            }
        }
    }
}

struct BroadcastPicker: UIViewRepresentable {
    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let picker = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 52, height: 52))
        picker.preferredExtension = AppConfiguration.broadcastID
        picker.showsMicrophoneButton = false
        picker.backgroundColor = UIColor(Theme.purple.opacity(0.15))
        picker.layer.cornerRadius = 16
        picker.accessibilityLabel = "启动长卷系统录屏"
        return picker
    }
    func updateUIView(_ uiView: RPSystemBroadcastPickerView, context: Context) {}
}

struct VideoPicker: UIViewControllerRepresentable {
    let onVideo: (URL) -> Void
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .videos
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onVideo) }
    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let completion: (URL) -> Void
        init(_ completion: @escaping (URL) -> Void) { self.completion = completion }
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard let provider = results.first?.itemProvider else { return }
            provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { url, error in
                guard error == nil, let url else { return }
                let copy = FileManager.default.temporaryDirectory.appendingPathComponent("recording-\(UUID().uuidString).mov")
                do {
                    try FileManager.default.copyItem(at: url, to: copy)
                    DispatchQueue.main.async { self.completion(copy) }
                } catch { /* The source remains in Photos if copying fails. */ }
            }
        }
    }
}
