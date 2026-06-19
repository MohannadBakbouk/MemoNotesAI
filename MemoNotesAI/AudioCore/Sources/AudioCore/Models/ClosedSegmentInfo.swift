// AudioCore/Models/ClosedSegmentInfo.swift

import Foundation

public struct ClosedSegmentInfo: Sendable, Equatable {
    public let path: String
    public let segmentIndex: Int
    public let startTime: TimeInterval
    public let duration: TimeInterval
    public let frameCount: Int64

    public init(
        path: String,
        segmentIndex: Int,
        startTime: TimeInterval,
        duration: TimeInterval,
        frameCount: Int64
    ) {
        self.path = path
        self.segmentIndex = segmentIndex
        self.startTime = startTime
        self.duration = duration
        self.frameCount = frameCount
    }
}
