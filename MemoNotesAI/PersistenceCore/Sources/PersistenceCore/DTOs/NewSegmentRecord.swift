import Foundation

public struct NewSegmentRecord: Sendable {
    public let sessionID: UUID
    public let segmentIndex: Int
    public let filePath: String
    public let startTime: TimeInterval
    public let duration: TimeInterval

    public init(
        sessionID: UUID,
        segmentIndex: Int,
        filePath: String,
        startTime: TimeInterval,
        duration: TimeInterval
    ) {
        self.sessionID = sessionID
        self.segmentIndex = segmentIndex
        self.filePath = filePath
        self.startTime = startTime
        self.duration = duration
    }
}
