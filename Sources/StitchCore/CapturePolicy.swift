import Foundation

/// Shared policy for the ReplayKit extension and imported screen-recording videos.
public struct CapturePolicy: Sendable {
    public private(set) var lastAccepted: PixelGrid?
    public private(set) var count = 0
    public let limit: Int
    public init(limit: Int = 60) { self.limit = limit }

    public mutating func shouldCapture(_ grid: PixelGrid) -> Bool {
        guard count < limit else { return false }
        if let previous = lastAccepted {
            guard StitchMatcher.meanDifference(previous, grid) > 0.025 else { return false }
        }
        lastAccepted = grid
        count += 1
        return true
    }
}
