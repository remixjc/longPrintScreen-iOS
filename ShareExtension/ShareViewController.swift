import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    private let titleLabel = UILabel()
    private let detailLabel = UILabel()
    private let action = UIButton(type: .system)
    private let spinner = UIActivityIndicatorView(style: .large)
    private var completedDirectory: URL?
    private var finished = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.04, green: 0.04, blue: 0.07, alpha: 1)
        let symbol = UIImageView(image: UIImage(systemName: "rectangle.stack.badge.plus"))
        symbol.tintColor = UIColor(red: 0.65, green: 0.94, blue: 0.44, alpha: 1)
        symbol.contentMode = .scaleAspectFit
        symbol.heightAnchor.constraint(equalToConstant: 64).isActive = true
        titleLabel.text = "导入长卷"
        titleLabel.font = .systemFont(ofSize: 26, weight: .bold)
        titleLabel.textColor = .white
        titleLabel.textAlignment = .center
        detailLabel.text = "按分享顺序读取图片…"
        detailLabel.font = .systemFont(ofSize: 16)
        detailLabel.numberOfLines = 0
        detailLabel.textAlignment = .center
        detailLabel.textColor = .lightGray
        action.setTitle("读取中", for: .normal)
        action.setTitleColor(.black, for: .normal)
        action.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        action.backgroundColor = symbol.tintColor
        action.layer.cornerRadius = 16
        action.heightAnchor.constraint(equalToConstant: 54).isActive = true
        action.isEnabled = false
        action.addTarget(self, action: #selector(done), for: .touchUpInside)
        spinner.color = symbol.tintColor
        spinner.startAnimating()
        let cancel = UIButton(type: .system)
        cancel.setTitle("取消", for: .normal)
        cancel.tintColor = .lightGray
        cancel.addTarget(self, action: #selector(cancelImport), for: .touchUpInside)
        let stack = UIStackView(arrangedSubviews: [symbol, titleLabel, detailLabel, spinner, action, cancel])
        stack.axis = .vertical
        stack.spacing = 24
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -28)
        ])
        Task { await receiveImages() }
    }

    private func receiveImages() async {
        let items = extensionContext?.inputItems as? [NSExtensionItem] ?? []
        let providers = items.flatMap { $0.attachments ?? [] }
            .filter { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }
        var directory: URL?
        do {
            guard providers.count >= 2 else { throw StitchShareError.tooFew }
            guard providers.count <= AppConfiguration.maxPhotos else { throw StitchShareError.tooMany }
            var (batch, folder) = try SharedStorage.create(source: "相册分享")
            directory = folder
            for (index, provider) in providers.enumerated() {
                guard !finished else { try? FileManager.default.removeItem(at: folder); return }
                detailLabel.text = "正在导入 \(index + 1) / \(providers.count) 张"
                let name = "\(index).image"
                let target = folder.appendingPathComponent(name)
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    provider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { url, error in
                        do {
                            if let error { throw error }
                            guard let url else { throw StorageError.invalidImage }
                            try FileManager.default.copyItem(at: url, to: target)
                            _ = try ImageFiles.size(at: target)
                            continuation.resume()
                        } catch { continuation.resume(throwing: error) }
                    }
                }
                batch.files.append(name)
            }
            guard !finished else { try? FileManager.default.removeItem(at: folder); return }
            batch.complete = true
            try SharedStorage.save(batch, directory: folder)
            completedDirectory = folder
            titleLabel.text = "已发送 \(batch.files.count) 张图片"
            detailLabel.text = "点完成后打开长卷，在首页点「导入并拼接」。\n顺序不连续也可尝试自动排序。"
            action.setTitle("完成", for: .normal)
            action.isEnabled = true
        } catch {
            if let directory { try? FileManager.default.removeItem(at: directory) }
            titleLabel.text = "暂时无法导入"
            detailLabel.text = error.localizedDescription
            action.setTitle("关闭", for: .normal)
            action.isEnabled = true
        }
        spinner.stopAnimating()
    }

    @objc private func done() {
        finished = true
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }
    @objc private func cancelImport() {
        finished = true
        if let completedDirectory { try? FileManager.default.removeItem(at: completedDirectory) }
        extensionContext?.cancelRequest(withError: NSError(domain: "LongShot.Share", code: NSUserCancelledError))
    }
}

enum StitchShareError: LocalizedError {
    case tooFew, tooMany
    var errorDescription: String? {
        switch self {
        case .tooFew: return "请在相册中选择至少两张图片再分享。"
        case .tooMany: return "一次最多导入 20 张图片，请分批分享。"
        }
    }
}
