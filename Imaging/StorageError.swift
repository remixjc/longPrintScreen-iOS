import Foundation

enum StorageError: LocalizedError {
    case unavailable, invalidImage, emptyBatch
    var errorDescription: String? {
        switch self {
        case .unavailable: return "无法访问共享导入空间，请重新打开 App 后重试。"
        case .invalidImage: return "这张图片无法读取，请选择有效的截图或照片。"
        case .emptyBatch: return "没有可导入的图片。"
        }
    }
}
