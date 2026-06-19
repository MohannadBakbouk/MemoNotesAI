import Foundation
import PersistenceCore

/// View-facing snapshot of a RecordingSession — safe to pass across isolation boundaries.
public struct SessionDisplayModel: Identifiable, Sendable, Equatable {
    public let id:               UUID
    public let name:             String
    public let date:             Date
    public let duration:         TimeInterval
    public let segmentCount:     Int
    public let transcribedCount: Int
    public let isRecording:      Bool
    public let needsManualResume: Bool

    public var allTranscribed: Bool { segmentCount > 0 && transcribedCount == segmentCount }

    init(from model: RecordingSessionModel) {
        id               = model.id
        name             = model.name
        date             = model.date
        duration         = model.duration
        isRecording      = model.isRecording
        needsManualResume = model.needsManualResume
        let segs         = model.segments
        segmentCount     = segs.count
        transcribedCount = segs.filter { $0.processingStatus == .success || $0.processingStatus == .silent }.count
    }
}
