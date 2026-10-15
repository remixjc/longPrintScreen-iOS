import UIKit

enum DemoImages {
    static func make(in directory: URL) throws -> [URL] {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 1800), format: format)
        let page = renderer.image { context in
            UIColor(red: 0.96, green: 0.95, blue: 0.92, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 400, height: 1800))
            func text(_ string: String, x: CGFloat, y: CGFloat, font: UIFont, color: UIColor) {
                (string as NSString).draw(at: CGPoint(x: x, y: y), withAttributes: [.font: font, .foregroundColor: color])
            }
            text("ON THE WAY", x: 28, y: 30, font: .monospacedSystemFont(ofSize: 12, weight: .medium), color: .darkGray)
            text("把日常，写成风景", x: 28, y: 60, font: .systemFont(ofSize: 27, weight: .bold), color: .black)
            text("长卷拼接示例 / 向下探索", x: 28, y: 106, font: .systemFont(ofSize: 14), color: .darkGray)
            for index in 0..<12 {
                let y = CGFloat(165 + index * 132)
                let hue = CGFloat(index) / 15.0 + 0.15
                UIColor(hue: hue, saturation: 0.35, brightness: 0.76, alpha: 1).setFill()
                UIBezierPath(roundedRect: CGRect(x: 28, y: y, width: 344, height: 56 + CGFloat(index % 3) * 4),
                             cornerRadius: 12).fill()
                text(String(format: "%02d", index + 1) + "  每一段，都值得留下", x: 44, y: y + 15,
                     font: .systemFont(ofSize: 17, weight: .semibold), color: .white)
                text("轻轻滑动，让零散的画面成为完整的故事。", x: 28, y: y + 77,
                     font: .systemFont(ofSize: 14), color: .darkGray)
                text("这是第 \(index + 1) 段独立内容 · 长卷", x: 28, y: y + 102,
                     font: .systemFont(ofSize: 12), color: .gray)
            }
        }
        guard let cg = page.cgImage else { throw StorageError.invalidImage }
        var urls: [URL] = []
        for (index, start) in [0, 500, 1000].enumerated() {
            guard let crop = cg.cropping(to: CGRect(x: 0, y: start, width: 400, height: 800)) else { throw StorageError.invalidImage }
            let url = directory.appendingPathComponent("demo-\(index).jpg")
            try ImageFiles.write(crop, to: url)
            urls.append(url)
        }
        return [urls[2], urls[0], urls[1]]
    }
}
