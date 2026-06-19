import Foundation
import SwiftData

@Model
public final class AudioSegmentModel {
    @Attribute(.unique) public var id: UUID
    public var segmentIndex: Int
    public var filePath: String?
    public var startTime: TimeInterval
    public var duration: TimeInterval
    public var status: String
    public var audioDeletedAt: Date?

    public var session: RecordingSessionModel?

    @Relationship(deleteRule: .cascade, inverse: \TranscriptionModel.segment)
    public var transcription: TranscriptionModel?

    public var processingStatus: SegmentProcessingStatus {
        get { SegmentProcessingStatus(rawValue: status) ?? .pending }
        set { status = newValue.rawValue }
    }

    public init(
        id: UUID = UUID(),
        segmentIndex: Int,
        filePath: String? = nil,
        startTime: TimeInterval,
        duration: TimeInterval,
        status: SegmentProcessingStatus = .pending,
        audioDeletedAt: Date? = nil,
        session: RecordingSessionModel? = nil,
        transcription: TranscriptionModel? = nil
    ) {
        self.id = id
        self.segmentIndex = segmentIndex
        self.filePath = filePath
        self.startTime = startTime
        self.duration = duration
        self.status = status.rawValue
        self.audioDeletedAt = audioDeletedAt
        self.session = session
        self.transcription = transcription
    }
}
