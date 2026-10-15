import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var workspace: WorkspaceModel
    @EnvironmentObject private var purchases: PurchaseStore
    @State private var showPicker = false
    @State private var showPro = false
    @State private var showHelp = false
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        header
                        hero
                        HStack(spacing: 12) {
                            metric("arrow.triangle.merge", title: "智能去重", subtitle: "重叠内容，只留一次", color: Theme.cyan)
                            metric("slider.horizontal.3", title: "精准微调", subtitle: "每一处，都能调整", color: Theme.purple)
                        }
                        VStack(spacing: 14) {
                            SectionLabel(title: "开始一张长图", detail: "最多 20 张")
                            Card {
                                VStack(alignment: .leading, spacing: 18) {
                                    HStack(alignment: .top, spacing: 12) {
                                        Image(systemName: "photo.on.rectangle.angled")
                                            .font(.title2).foregroundStyle(Theme.green)
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text("从相册选择截图").font(.headline)
                                            Text("请按从上到下的顺序选择，并保留重叠内容。")
                                                .font(.subheadline).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                                        }
                                    }
                                    Button { showPicker = true } label: {
                                        Label("选择截图", systemImage: "plus")
                                    }.buttonStyle(PrimaryButton()).accessibilityIdentifier("selectPhotos")
                                    HStack {
                                        Toggle("尝试自动排序", isOn: $workspace.automaticOrder)
                                            .font(.subheadline).tint(Theme.green)
                                    }
                                    Text("选乱了也可以：能识别连续内容时自动排序，无法确定时由你调整。")
                                        .font(.caption).foregroundStyle(Theme.muted)
                                }
                            }
                        }
                        if !workspace.pendingBatches.isEmpty { inbox }
                        Button { showPro = true } label: {
                            Card {
                                HStack(spacing: 14) {
                                    Image(systemName: "record.circle").font(.system(size: 29)).foregroundStyle(Theme.purple)
                                    VStack(alignment: .leading, spacing: 5) {
                                        HStack { Text("边滑动，边截屏").font(.headline); ProBadge() }
                                        Text("录屏自动捕捉，轻松拼出整页").font(.caption).foregroundStyle(Theme.muted)
                                    }
                                    Spacer(minLength: 0)
                                    Image(systemName: "chevron.right").foregroundStyle(Theme.muted)
                                }
                            }
                        }.buttonStyle(.plain)
                        HStack {
                            Button { Task { await workspace.loadDemo() } } label: {
                                Label("试试示例", systemImage: "sparkles")
                            }.accessibilityIdentifier("loadDemo")
                            Spacer()
                            Button { showHelp = true } label: { Label("拼接指南", systemImage: "questionmark.circle") }
                        }.font(.subheadline).foregroundStyle(Theme.muted).padding(.horizontal, 4)
                        HStack(spacing: 5) {
                            Image(systemName: "lock.shield")
                            Text("图片仅在本机处理")
                        }.font(.caption).foregroundStyle(Theme.muted.opacity(0.75))
                            .frame(maxWidth: .infinity).padding(.bottom, 16)
                    }.padding(.horizontal, 20).padding(.top, 12).frame(maxWidth: 680)
                        .frame(maxWidth: .infinity)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showPicker) {
                PhotoPicker { results in Task { await workspace.importPhotos(results) } }.ignoresSafeArea()
            }
            .sheet(isPresented: $showPro) { PaywallView() }
            .sheet(isPresented: $showHelp) { GuideView() }
            .task { workspace.scanInbox() }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 7) {
                Text(Date.now.formatted(.dateTime.month(.wide).day().weekday(.wide)))
                    .font(.caption).foregroundStyle(Theme.muted)
                Text("把精彩，连在一起").font(.system(size: 28, weight: .bold))
            }
            Spacer()
            Button { showHelp = true } label: {
                Image(systemName: "rectangle.portrait.on.rectangle.portrait")
                    .font(.system(size: 20, weight: .medium)).foregroundStyle(Theme.purple)
                    .frame(width: 48, height: 48).background(Theme.purple.opacity(0.13), in: Circle())
            }.accessibilityLabel("使用指南")
        }
    }

    private var hero: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 28)
                .fill(LinearGradient(colors: [Color(red: 0.18, green: 0.14, blue: 0.31), Theme.card],
                                     startPoint: .topTrailing, endPoint: .bottomLeading))
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("LONGSHOT / 长卷").font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(2).foregroundStyle(Theme.purple)
                    Text("不止一屏\n一图尽兴").font(.system(size: 32, weight: .bold)).lineSpacing(4)
                    Text("无痕拼接 · 自由分享").font(.caption).foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 0)
                PaperArtwork().frame(width: 130, height: 165).accessibilityHidden(true)
            }.padding(24)
        }.frame(height: 223)
    }

    private func metric(_ icon: String, title: String, subtitle: String, color: Color) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: icon).font(.title3).foregroundStyle(color)
                Text(title).font(.system(size: 16, weight: .semibold))
                Text(subtitle).font(.system(size: 11)).foregroundStyle(Theme.muted).minimumScaleFactor(0.8)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var inbox: some View {
        VStack(spacing: 12) {
            SectionLabel(title: "待导入", detail: "\(workspace.pendingBatches.count) 组")
            ForEach(workspace.pendingBatches, id: \.0.id) { batch, directory in
                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: batch.source == "录屏" ? "record.circle" : "square.and.arrow.down")
                                .foregroundStyle(Theme.cyan)
                            Text("\(batch.source) · \(batch.files.count) 张").font(.headline)
                            Spacer()
                            Button(role: .destructive) { workspace.deleteBatch(directory) } label: {
                                Image(systemName: "trash").foregroundStyle(Theme.muted)
                            }.accessibilityLabel("删除这组图片")
                        }
                        Button("导入并拼接") { Task { await workspace.importBatch(batch, directory: directory) } }
                            .buttonStyle(PrimaryButton(color: Theme.cyan))
                    }
                }
            }
        }
    }
}

struct PaperArtwork: View {
    var body: some View {
        ZStack {
            Circle().fill(Theme.purple.opacity(0.12)).frame(width: 145, height: 145).blur(radius: 8)
            paper(color: Theme.purple, offset: -35).rotationEffect(.degrees(-12)).offset(x: -15, y: -15)
            paper(color: Theme.cyan, offset: 0).rotationEffect(.degrees(8)).offset(x: 16, y: 10)
            Image(systemName: "arrow.down").font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.background).frame(width: 32, height: 32)
                .background(Theme.green, in: Circle()).offset(x: 35, y: 69)
        }
    }
    private func paper(color: Color, offset: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: 5).fill(color.opacity(0.8)).frame(height: 30)
            ForEach(0..<4) { index in
                Capsule().fill(.white.opacity(index == 0 ? 0.6 : 0.18)).frame(width: index == 3 ? 33 : 61, height: 4)
            }
            Spacer(minLength: 0)
            HStack(spacing: 3) {
                ForEach(0..<7) { index in
                    RoundedRectangle(cornerRadius: 2).fill(color.opacity(0.7))
                        .frame(width: 5, height: CGFloat([11, 21, 17, 32, 24, 38, 29][index]))
                }
            }.frame(height: 38, alignment: .bottom)
        }.padding(12).frame(width: 88, height: 157)
            .background(Theme.inset, in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).stroke(.white.opacity(0.12)))
            .shadow(color: .black.opacity(0.3), radius: 12, y: 8)
    }
}
