import Foundation
import PersistenceCore

/// View-facing snapshot of an AudioSegment — safe to pass across isolation boundaries.
public struct SegmentDisplayModel: Identifiable, Sendable, Equatable {
    public let id:                  UUID
    public let segmentIndex:        Int
    public let startTime:           TimeInterval
    public let duration:            TimeInterval
    public let status:              SegmentProcessingStatus
    public let transcriptionText:   String?
    public let transcriptionMethod: TranscriptionMethod?
    public let filePath:            String?

    init(from model: AudioSegmentModel) {
        id                  = model.id
        segmentIndex        = model.segmentIndex
        startTime           = model.startTime
        duration            = model.duration
        status              = model.processingStatus
        transcriptionText   = model.transcription?.text
        transcriptionMethod = model.transcription.map { TranscriptionMethod(rawValue: $0.method) ?? .groq }
        filePath            = model.filePath
    }
}
