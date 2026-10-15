import SwiftUI
import StitchCore

struct EditorView: View {
    @EnvironmentObject private var workspace: WorkspaceModel
    @State private var section = 0
    @State private var selectedSeam = 0
    @State private var shareURL: ShareFile?
    @State private var confirmClose = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                VStack(spacing: 14) {
                    Picker("编辑模式", selection: $section) {
                        Text("长图预览").tag(0)
                        Text("拼接点").tag(1)
                        Text("顺序与裁剪").tag(2)
                    }.pickerStyle(.segmented).padding(.horizontal, 20).accessibilityIdentifier("editorMode")
                    if let analysis = workspace.analysis {
                        if section == 0 {
                            status(analysis).padding(.horizontal, 20)
                            if let image = workspace.preview {
                                ZoomImage(image: image).clipShape(RoundedRectangle(cornerRadius: 18))
                                    .padding(.horizontal, 20).accessibilityIdentifier("longImagePreview")
                                Text("上下滑动查看 · 双指缩放细节").font(.caption).foregroundStyle(Theme.muted)
                            } else { Spacer(); ProgressView(); Spacer() }
                        } else if section == 1 {
                            seams(analysis)
                        } else {
                            arrangement(analysis)
                        }
                    } else { Spacer() }
                }.padding(.top, 10).padding(.bottom, 8)
            }
            .navigationTitle("拼接工作台").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { confirmClose = true } label: { Image(systemName: "xmark").foregroundStyle(Theme.muted) }
                        .accessibilityLabel("关闭编辑")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Text("\(workspace.analysis?.shots.count ?? 0) 张").font(.caption).foregroundStyle(Theme.green)
                }
            }
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 12) {
                    Button { Task { await workspace.save() } } label: {
                        Label("保存到相册", systemImage: "square.and.arrow.down")
                    }.buttonStyle(PrimaryButton()).accessibilityIdentifier("saveImage")
                    Button {
                        Task { if let url = await workspace.export() { shareURL = ShareFile(url: url) } }
                    } label: {
                        Image(systemName: "square.and.arrow.up").font(.title3).frame(width: 56, height: 55)
                            .foregroundStyle(Theme.green).background(Theme.inset, in: RoundedRectangle(cornerRadius: 18))
                    }.accessibilityLabel("分享长图").accessibilityIdentifier("shareImage")
                }.disabled(workspace.busy).padding(.horizontal, 20).padding(.vertical, 12)
                    .background(Theme.background)
            }
            .overlay {
                if workspace.busy {
                    ZStack {
                        Color.black.opacity(0.5).ignoresSafeArea()
                        VStack(spacing: 15) {
                            ProgressView().tint(Theme.green)
                            Text(workspace.progress).font(.subheadline)
                        }.padding(28).background(Theme.card, in: RoundedRectangle(cornerRadius: 22))
                    }
                }
            }
            .sheet(item: $shareURL) { file in ActivitySheet(url: file.url) }
            .alert("长卷", isPresented: Binding(get: { workspace.message != nil },
                                              set: { if !$0 { workspace.message = nil } })) {
                Button("好的") { workspace.message = nil }
            } message: { Text(workspace.message ?? "") }
            .confirmationDialog("关闭后将清除本次编辑，原始相册图片不会改变。", isPresented: $confirmClose, titleVisibility: .visible) {
                Button("结束编辑", role: .destructive) { workspace.closeEditor() }
            }
        }.preferredColorScheme(.dark)
    }

    private func status(_ analysis: StitchAnalysis) -> some View {
        HStack(alignment: .top, spacing: 8) {
            let uncertain = analysis.confidences.filter { $0 < 0.72 }.count
            Image(systemName: uncertain == 0 ? "checkmark.seal.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(uncertain == 0 ? Theme.green : .orange)
            VStack(alignment: .leading, spacing: 4) {
                Text(uncertain == 0 ? "重叠内容已自动去除" : "\(uncertain) 处未确定重叠，请检查拼接点")
                    .font(.subheadline)
                Text(uncertain == 0 ? "保留首张顶部和末张底部，中间连续拼接" : "未匹配处尚未去重，请到「拼接点」调节去重范围")
                    .font(.caption).foregroundStyle(Theme.muted)
                if analysis.reordered {
                    Text("已按连续内容调整顺序").font(.caption).foregroundStyle(Theme.purple)
                }
                if analysis.duplicates > 0 {
                    Text("已移除 \(analysis.duplicates) 张重复图片").font(.caption).foregroundStyle(Theme.muted)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func seams(_ analysis: StitchAnalysis) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("逐处检查，让画面自然衔接。").font(.subheadline).foregroundStyle(Theme.muted)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(0..<analysis.overlaps.count, id: \.self) { index in
                            Button { selectedSeam = index } label: {
                                Text("\(index + 1) → \(index + 2)").font(.subheadline.weight(.semibold))
                                    .padding(.horizontal, 17).padding(.vertical, 11)
                                    .background(selectedSeam == index ? Theme.purple : Theme.inset, in: Capsule())
                                    .foregroundStyle(selectedSeam == index ? .white : Theme.muted)
                            }.accessibilityIdentifier("seam-\(index)")
                        }
                    }
                }
                if selectedSeam < workspace.overlaps.count {
                    let index = selectedSeam
                    Card {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Text("拼接点 \(index + 1)").font(.headline)
                                Spacer()
                                Text(analysis.confidences[index] >= 0.72 ? "自动匹配" : "请手动检查")
                                    .font(.caption).foregroundStyle(analysis.confidences[index] >= 0.72 ? Theme.green : .orange)
                            }
                            SeamPreview(analysis: analysis, index: index, overlaps: workspace.overlaps,
                                        endCuts: workspace.endCuts, top: workspace.top, bottom: workspace.bottom)
                                .frame(height: 220).clipShape(RoundedRectangle(cornerRadius: 12))
                                .accessibilityIdentifier("seamPreview")
                            pixelSlider("下张顶部去重", value: $workspace.overlaps[index],
                                        max: max(0, analysis.heights[index + 1] - workspace.top - workspace.bottom - 1))
                                .accessibilityIdentifier("overlapSlider")
                            pixelSlider("上张底部裁掉", value: $workspace.endCuts[index],
                                        max: max(0, analysis.heights[index] - workspace.top - workspace.bottom - 1))
                            HStack {
                                Button("恢复此处自动值") {
                                    workspace.overlaps[index] = analysis.overlaps[index]
                                    workspace.endCuts[index] = 0
                                    workspace.schedulePreview()
                                }.font(.subheadline).foregroundStyle(Theme.purple)
                                Spacer()
                                Button("不去重") {
                                    workspace.overlaps[index] = 0
                                    workspace.endCuts[index] = 0
                                    workspace.schedulePreview()
                                }.font(.subheadline).foregroundStyle(Theme.muted)
                            }
                        }
                    }
                    Text("紫线表示连接位置。向右增加下张去重范围；若上张包含固定底栏，可单独裁掉。像素值以拼接宽度为基准。")
                        .font(.caption).foregroundStyle(Theme.muted)
                }
            }.padding(20).frame(maxWidth: 680).frame(maxWidth: .infinity)
        }
    }

    private func arrangement(_ analysis: StitchAnalysis) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Card {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("中间固定栏去除").font(.headline)
                        Toggle("自动识别顶部 / 底部固定栏", isOn: $workspace.trimChrome)
                            .font(.subheadline).tint(Theme.green)
                        Text("首张顶部和末张底部会保留，只去除中间重复的固定栏。修改开关后点重新识别。").font(.caption).foregroundStyle(Theme.muted)
                        let maxCrop = max(0, (analysis.heights.min() ?? 100) / 3)
                        pixelSlider("中间顶部固定栏", value: $workspace.top, max: maxCrop)
                        pixelSlider("中间底部固定栏", value: $workspace.bottom, max: maxCrop)
                        Button("重新识别拼接点") { Task { await workspace.reanalyze() } }
                            .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.purple)
                    }
                }
                SectionLabel(title: "图片顺序", detail: "箭头调整")
                Text("录屏里的切换画面、通知或多余截图，可在这里移除。至少保留两张。")
                    .font(.caption).foregroundStyle(Theme.muted)
                ForEach(Array(analysis.shots.enumerated()), id: \.element.id) { index, shot in
                    Card {
                        HStack(spacing: 14) {
                            ShotThumbnail(url: shot.url).frame(width: 42, height: 66).clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            VStack(alignment: .leading, spacing: 6) {
                                Text("第 \(index + 1) 张").font(.headline)
                                Text("原选择 \(shot.label) · \(shot.width) × \(shot.height)").font(.caption).foregroundStyle(Theme.muted)
                            }
                            Spacer(minLength: 2)
                            Button { Task { await workspace.move(from: index, to: index - 1) } } label: {
                                Image(systemName: "arrow.up").frame(width: 32, height: 40)
                            }.disabled(index == 0).accessibilityLabel("第\(index + 1)张上移")
                            Button { Task { await workspace.move(from: index, to: index + 1) } } label: {
                                Image(systemName: "arrow.down").frame(width: 32, height: 40)
                            }.disabled(index == analysis.shots.count - 1).accessibilityLabel("第\(index + 1)张下移")
                            Button { Task { await workspace.removeShot(at: index); selectedSeam = 0 } } label: {
                                Image(systemName: "trash").frame(width: 28, height: 40).foregroundStyle(Theme.muted)
                            }.disabled(analysis.shots.count <= 2).accessibilityLabel("移除第\(index + 1)张")
                        }
                    }
                }
            }.padding(20).frame(maxWidth: 680).frame(maxWidth: .infinity)
        }
    }

    private func pixelSlider(_ title: String, value: Binding<Int>, max maximum: Int) -> some View {
        VStack(spacing: 8) {
            HStack {
                Text(title).font(.subheadline)
                Spacer()
                Button {
                    value.wrappedValue = max(0, value.wrappedValue - 1); workspace.schedulePreview()
                } label: { Image(systemName: "minus.circle").frame(width: 30, height: 30) }
                    .accessibilityLabel("\(title)减少一个像素")
                Text("\(value.wrappedValue) px").font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Theme.purple).frame(minWidth: 56)
                Button {
                    value.wrappedValue = min(maximum, value.wrappedValue + 1); workspace.schedulePreview()
                } label: { Image(systemName: "plus.circle").frame(width: 30, height: 30) }
                    .accessibilityLabel("\(title)增加一个像素")
            }
            Slider(value: Binding(get: { Double(min(maximum, value.wrappedValue)) },
                                  set: { value.wrappedValue = Int($0); workspace.schedulePreview() }),
                   in: 0...Double(max(1, maximum)), step: 1).tint(Theme.purple)
        }
    }
}

struct ShareFile: Identifiable { let id = UUID(); let url: URL }
struct ActivitySheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct ShotThumbnail: View {
    let url: URL
    @State private var image: UIImage?
    var body: some View {
        Group {
            if let image { Image(uiImage: image).resizable().scaledToFill() }
            else { Theme.inset.overlay { ProgressView() } }
        }.task(id: url) {
            let thumbnail = await Task.detached(priority: .utility) {
                (try? ImageFiles.image(at: url, maxDimension: 200)).map { UIImage(cgImage: $0) }
            }.value
            image = thumbnail
        }
    }
}

struct SeamPreview: View {
    let analysis: StitchAnalysis
    let index: Int
    let overlaps: [Int]
    let endCuts: [Int]
    let top: Int
    let bottom: Int
    var body: some View {
        VStack(spacing: 0) {
            strip(index: index, upper: true)
            Rectangle().fill(Theme.purple).frame(height: 3)
            strip(index: index + 1, upper: false)
        }.background(Theme.inset)
    }
    private func strip(index: Int, upper: Bool) -> some View {
        let ranges = CompositionPlan.ranges(heights: analysis.heights, top: top, bottom: bottom,
                                            overlaps: overlaps, endCuts: endCuts)
        let range = ranges[index]
        let amount = min(180, range.height)
        let start = upper ? range.end - amount : range.start
        let shot = analysis.shots[index]
        var result: UIImage?
        if let image = try? ImageFiles.image(at: shot.url, maxDimension: 1400) {
            let scale = Double(image.height) / Double(analysis.heights[index])
            if let crop = image.cropping(to: CGRect(x: 0, y: Double(start) * scale, width: Double(image.width),
                                                   height: max(1, Double(amount) * scale))) {
                result = UIImage(cgImage: crop)
            }
        }
        return Group {
            if let result { Image(uiImage: result).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: .infinity) }
            else { Color.gray.opacity(0.1) }
        }
    }
}

struct ZoomImage: UIViewRepresentable {
    let image: UIImage
    func makeUIView(context: Context) -> ZoomCanvas {
        let view = ZoomCanvas()
        view.setImage(image)
        return view
    }
    func updateUIView(_ uiView: ZoomCanvas, context: Context) { uiView.setImage(image) }
}

final class ZoomCanvas: UIScrollView, UIScrollViewDelegate {
    private let imageView = UIImageView()
    private var needsFit = true
    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(imageView)
        delegate = self
        backgroundColor = UIColor(Theme.card)
        showsHorizontalScrollIndicator = false
        let tap = UITapGestureRecognizer(target: self, action: #selector(doubleTap(_:)))
        tap.numberOfTapsRequired = 2
        addGestureRecognizer(tap)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func setImage(_ image: UIImage) {
        guard imageView.image !== image else { return }
        imageView.image = image
        zoomScale = 1
        imageView.frame = CGRect(origin: .zero, size: image.size)
        contentSize = image.size
        needsFit = true
        setNeedsLayout()
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        guard needsFit, bounds.width > 0, let image = imageView.image else { return }
        needsFit = false
        let fit = bounds.width / image.size.width
        minimumZoomScale = fit
        maximumZoomScale = fit * 4
        zoomScale = fit
    }
    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }
    @objc private func doubleTap(_ tap: UITapGestureRecognizer) {
        if zoomScale > minimumZoomScale * 1.1 { setZoomScale(minimumZoomScale, animated: true) }
        else {
            let point = tap.location(in: imageView)
            let scale = minimumZoomScale * 2.5
            zoom(to: CGRect(x: point.x - bounds.width / scale / 2, y: point.y - bounds.height / scale / 2,
                            width: bounds.width / scale, height: bounds.height / scale), animated: true)
        }
    }
}
