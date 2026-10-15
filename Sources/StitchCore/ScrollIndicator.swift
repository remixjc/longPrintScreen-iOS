import Foundation

/// A narrow system scroll indicator over an otherwise uniform outer margin.
public struct ScrollIndicator: Sendable {
    public let left: Int
    public let right: Int
    public let top: Int
    public let bottom: Int

    public static func find(in grid: PixelGrid) -> ScrollIndicator? {
        guard grid.width >= 100, grid.height >= 200 else { return nil }
        let search = max(4, grid.width / 40)
        let reference = grid.width - max(10, grid.width / 25)
        var start = 0, left = grid.width, right = 0, previousLeft = 0, previousRight = 0
        var best: ScrollIndicator?
        func finish(_ end: Int) {
            guard end - start >= max(24, grid.height / 20), right > left else { return }
            if end - start > (best.map { $0.bottom - $0.top } ?? 0) {
                let padding = max(3, grid.width / 50)
                best = ScrollIndicator(left: max(0, left - 1), right: min(grid.width, right + 1),
                                       top: max(0, start - padding), bottom: min(grid.height, end + padding))
            }
        }
        for y in 0..<grid.height {
            let offset = y * grid.width, background = Int(grid.pixels[offset + reference])
            let columns = ((grid.width - search)..<(grid.width - 1)).filter {
                abs(Int(grid.pixels[offset + $0]) - background) > 24
            }
            let lo = columns.first ?? 0, hi = (columns.last ?? -1) + 1
            let valid = !columns.isEmpty && columns.count == hi - lo && hi - lo <= max(2, grid.width / 80)
                && lo > grid.width - search && hi < grid.width - 1
                && abs(Int(grid.pixels[offset + lo - 1]) - background) < 8
                && abs(Int(grid.pixels[offset + hi]) - background) < 8
            if valid && (right == 0 || (abs(lo - previousLeft) <= 1 && abs(hi - previousRight) <= 1)) {
                left = min(left, lo); right = max(right, hi)
                previousLeft = lo; previousRight = hi
            } else {
                finish(y)
                start = valid ? y : y + 1
                left = valid ? lo : grid.width; right = valid ? hi : 0
                previousLeft = lo; previousRight = hi
            }
        }
        finish(grid.height)
        return best
    }
}
