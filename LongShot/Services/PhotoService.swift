import Photos
import Foundation

enum PhotoService {
    static func save(url: URL) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw NSError(domain: "LongShot", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "未获得保存权限。请在系统设置 → 长卷 → 照片中允许添加照片。"
            ])
        }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: url)
        }
    }
}
