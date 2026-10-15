import ReplayKit
import CoreImage
import StitchCore

final class SampleHandler: RPBroadcastSampleHandler {
    private let context = CIContext(options: [.cacheIntermediates: false])
    private var policy = CapturePolicy(limit: 60)
    private var batch: ImportBatch?
    private var directory: URL?
    private var lastSampleTime = -Double.infinity
    private var initialSize: CGSize?
    private var ending = false

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        guard RecordingAuthorization.isValid else {
            fail("请先在长卷中购买或恢复 Pro，并打开 App 刷新录屏授权。")
            return
        }
        do {
            let (created, folder) = try SharedStorage.create(source: "录屏")
            batch = created
            directory = folder
        } catch { fail(error.localizedDescription) }
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        guard !ending, sampleBufferType == .video, var batch, let directory else { return }
        guard RecordingAuthorization.isValid else { fail("Pro 录屏授权已到期，请回到长卷刷新。"); return }
        let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        guard time.isFinite, time - lastSampleTime >= 0.45 else { return }
        lastSampleTime = time
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        autoreleasepool {
            do {
                var input = CIImage(cvPixelBuffer: buffer)
                if let orientation = CMGetAttachment(sampleBuffer, key: RPVideoSampleOrientationKey as CFString,
                                                      attachmentModeOut: nil) as? NSNumber {
                    input = input.oriented(forExifOrientation: orientation.int32Value)
                }
                let size = input.extent.size
                if let initialSize, initialSize != size {
                    fail("录屏方向发生变化，已保留之前截帧。请保持竖屏重新录制剩余内容。")
                    return
                }
                initialSize = size
                let scale = min(1, 1080 / size.width, 2340 / size.height)
                let scaled = input.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                guard let image = context.createCGImage(scaled, from: scaled.extent) else { return }
                let grid = try ImageFiles.grid(image, width: 32, height: 160)
                guard policy.shouldCapture(grid) else { return }
                let name = "frame-\(batch.files.count).jpg"
                try ImageFiles.write(image, to: directory.appendingPathComponent(name))
                batch.files.append(name)
                self.batch = batch
                try SharedStorage.save(batch, directory: directory)
                if batch.files.count >= policy.limit {
                    fail("已截取 60 张关键帧，结束本次录屏。请回到长卷导入，较长页面可分段录制。")
                }
            } catch { fail("截帧失败：\(error.localizedDescription)") }
        }
    }

    override func broadcastPaused() { lastSampleTime = -Double.infinity }
    override func broadcastResumed() { lastSampleTime = -Double.infinity }
    override func broadcastFinished() { complete() }

    private func complete(note: String? = nil) {
        guard var batch, let directory else { return }
        batch.complete = true
        batch.note = note ?? batch.note
        try? SharedStorage.save(batch, directory: directory)
        self.batch = batch
        if batch.files.isEmpty { try? FileManager.default.removeItem(at: directory) }
    }

    private func fail(_ message: String) {
        guard !ending else { return }
        ending = true
        complete(note: message)
        finishBroadcastWithError(NSError(domain: "LongShot.Broadcast", code: 1, userInfo: [NSLocalizedDescriptionKey: message]))
    }
}
