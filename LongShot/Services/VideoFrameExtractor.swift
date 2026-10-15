import AVFoundation
import StitchCore

enum VideoFrameExtractor {
    static func extract(url: URL, directory: URL) async throws -> [URL] {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > 0 else { throw StorageError.invalidImage }
        guard duration <= 180 else {
            throw NSError(domain: "LongShot", code: 2, userInfo: [NSLocalizedDescriptionKey: "请选择 3 分钟以内的录屏，较长视频请先裁剪。"])
        }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1080, height: 2340)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.08, preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.08, preferredTimescale: 600)
        var policy = CapturePolicy(limit: 60)
        var urls: [URL] = []
        let step = max(0.45, duration / 180)
        for time in stride(from: 0.0, to: duration, by: step) {
            try Task.checkCancellation()
            let (image, _) = try await generator.image(at: CMTime(seconds: time, preferredTimescale: 600))
            let grid = try ImageFiles.grid(image, width: 32, height: 160)
            guard policy.shouldCapture(grid) else { continue }
            let file = directory.appendingPathComponent("frame-\(urls.count).jpg")
            try ImageFiles.write(image, to: file)
            urls.append(file)
            if urls.count == 60 { break }
        }
        guard urls.count >= 2 else { throw StitchError.insufficient }
        return urls
    }
}
