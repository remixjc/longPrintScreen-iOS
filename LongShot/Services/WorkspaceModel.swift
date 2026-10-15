import SwiftUI
import StitchCore
import PhotosUI

@MainActor
final class WorkspaceModel: ObservableObject {
    @Published var analysis: StitchAnalysis?
    @Published var overlaps: [Int] = []
    @Published var endCuts: [Int] = []
    @Published var top = 0
    @Published var bottom = 0
    @Published var automaticOrder = true
    @Published var trimChrome = true
    @Published var busy = false
    @Published var progress = ""
    @Published var message: String?
    @Published var preview: UIImage?
    @Published var previewURL: URL?
    @Published var pendingBatches: [(ImportBatch, URL)] = []
    @Published var showEditor = false
    private let engine = StitchEngine()
    private var workingDirectory: URL?
    private var renderTask: Task<Void, Never>?
    private var renderGeneration = 0
    private var exportURL: URL?

    func scanInbox() {
        SharedStorage.cleanExpired()
        pendingBatches = (try? SharedStorage.pending()) ?? []
    }

    func importPhotos(_ results: [PHPickerResult]) async {
        guard !results.isEmpty, !busy else { return }
        busy = true
        progress = "正在读取图片"
        defer { busy = false }
        do {
            let directory = try newWorkspace()
            var urls: [URL] = []
            for (index, result) in results.prefix(AppConfiguration.maxPhotos).enumerated() {
                progress = "正在读取 \(index + 1) / \(results.count)"
                let target = directory.appendingPathComponent("\(index).image")
                try await copyImage(result.itemProvider, to: target)
                urls.append(target)
            }
            try await analyze(urls)
        } catch { message = error.localizedDescription }
    }

    func importBatch(_ batch: ImportBatch, directory: URL) async {
        guard !busy else { return }
        busy = true
        progress = "正在导入\(batch.source)"
        defer { busy = false }
        do {
            let workspace = try newWorkspace()
            var urls: [URL] = []
            for (index, source) in SharedStorage.fileURLs(batch, directory: directory).enumerated() {
                let target = workspace.appendingPathComponent("\(index).image")
                try FileManager.default.copyItem(at: source, to: target)
                urls.append(target)
            }
            try await analyze(urls, autoOrder: batch.source == "录屏" ? false : nil)
            try FileManager.default.removeItem(at: directory)
            scanInbox()
            if let note = batch.note { message = note }
        } catch { message = error.localizedDescription }
    }

    func deleteBatch(_ directory: URL) {
        do { try FileManager.default.removeItem(at: directory); scanInbox() }
        catch { message = "删除失败：\(error.localizedDescription)" }
    }

    func importVideo(url: URL) async {
        guard !busy else { return }
        busy = true
        progress = "正在提取录屏关键帧"
        defer { busy = false }
        do {
            let directory = try newWorkspace()
            let urls = try await VideoFrameExtractor.extract(url: url, directory: directory)
            try await analyze(urls, autoOrder: false)
        } catch { message = error.localizedDescription }
    }

    func reanalyze() async {
        guard let analysis, !busy else { return }
        busy = true
        progress = "重新识别重叠内容"
        defer { busy = false }
        do { try await analyze(analysis.shots.map(\.url)) }
        catch { message = error.localizedDescription }
    }

    func move(from: Int, to: Int) async {
        guard let analysis, !busy, from >= 0, from < analysis.shots.count,
              to >= 0, to < analysis.shots.count else { return }
        var urls = analysis.shots.map(\.url)
        let moved = urls.remove(at: from)
        urls.insert(moved, at: to)
        busy = true
        progress = "按新顺序识别拼接点"
        defer { busy = false }
        do { try await analyze(urls, autoOrder: false) }
        catch { message = error.localizedDescription }
    }

    func removeShot(at index: Int) async {
        guard let analysis, !busy, analysis.shots.count > 2,
              analysis.shots.indices.contains(index) else { return }
        var urls = analysis.shots.map(\.url)
        urls.remove(at: index)
        busy = true
        progress = "移除图片并更新拼接点"
        defer { busy = false }
        do { try await analyze(urls, autoOrder: false) }
        catch { message = error.localizedDescription }
    }

    private func analyze(_ urls: [URL], autoOrder: Bool? = nil) async throws {
        progress = "识别重叠与顺序"
        let result = try await engine.analyze(urls: urls, automatic: autoOrder ?? automaticOrder, trimChrome: trimChrome)
        analysis = result
        overlaps = result.overlaps
        endCuts = result.endCuts
        top = result.top
        bottom = result.bottom
        showEditor = true
        await updatePreview()
    }

    func schedulePreview() {
        renderTask?.cancel()
        renderGeneration += 1
        let generation = renderGeneration
        renderTask = Task {
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            await updatePreview(generation: generation)
        }
    }

    func updatePreview(generation: Int? = nil) async {
        guard let analysis else { return }
        do {
            let url = try await engine.render(analysis, overlaps: overlaps, endCuts: endCuts, top: top, bottom: bottom, preview: true)
            if let generation, generation != renderGeneration {
                try? FileManager.default.removeItem(at: url)
                return
            }
            if let previous = previewURL { try? FileManager.default.removeItem(at: previous) }
            // A debounced preview may finish while Photos or the share sheet
            // is still consuming an export. Keep that file until the next export
            // or until editing ends; exports always render current settings.
            previewURL = url
            preview = UIImage(contentsOfFile: url.path)
        } catch is CancellationError {
        } catch { message = error.localizedDescription }
    }

    func export() async -> URL? {
        guard let analysis, !busy else { return nil }
        busy = true
        progress = "正在生成高清长图"
        defer { busy = false }
        do {
            let url = try await engine.render(analysis, overlaps: overlaps, endCuts: endCuts, top: top, bottom: bottom, preview: false)
            if let exportURL { try? FileManager.default.removeItem(at: exportURL) }
            exportURL = url
            return url
        } catch { message = error.localizedDescription; return nil }
    }

    func save() async {
        guard let url = await export() else { return }
        busy = true
        progress = "正在保存到相册"
        defer { busy = false }
        do { try await PhotoService.save(url: url); message = "长图已保存到相册。" }
        catch { message = error.localizedDescription }
    }

    func closeEditor() {
        renderGeneration += 1
        renderTask?.cancel()
        showEditor = false
        analysis = nil
        preview = nil
        if let previewURL { try? FileManager.default.removeItem(at: previewURL) }
        if let exportURL { try? FileManager.default.removeItem(at: exportURL) }
        previewURL = nil
        exportURL = nil
        if let workingDirectory { try? FileManager.default.removeItem(at: workingDirectory) }
        workingDirectory = nil
    }

    private func newWorkspace() throws -> URL {
        closeEditor()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("workspace-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        workingDirectory = directory
        return directory
    }

    private func copyImage(_ provider: NSItemProvider, to target: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            provider.loadFileRepresentation(forTypeIdentifier: "public.image") { url, error in
                do {
                    if let error { throw error }
                    guard let url else { throw StorageError.invalidImage }
                    try FileManager.default.copyItem(at: url, to: target)
                    continuation.resume()
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    func loadDemo() async {
        guard !busy else { return }
        busy = true
        progress = "准备示例截图"
        defer { busy = false }
        do {
            let directory = try newWorkspace()
            let urls = try DemoImages.make(in: directory)
            try await analyze(urls)
        } catch { message = error.localizedDescription }
    }
}
