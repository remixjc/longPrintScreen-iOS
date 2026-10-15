import Foundation

enum StorageError: LocalizedError {
    case unavailable, invalidImage, emptyBatch
    var errorDescription: String? {
        switch self {
        case .unavailable: return "共享空间不可用，请检查 App Group 签名配置。"
        case .invalidImage: return "这张图片无法读取，请选择有效的截图或照片。"
        case .emptyBatch: return "没有可导入的图片。"
        }
    }
}
