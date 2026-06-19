import Foundation
import SwiftData

@Model
public final class RecordingSessionModel {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var date: Date
    public var duration: TimeInterval
    public var isRecording: Bool
    public var interruptedAt: Date?
    public var needsManualResume: Bool

    @Relationship(deleteRule: .cascade, inverse: \AudioSegmentModel.session)
    public var segments: [AudioSegmentModel]

    public init(
        id: UUID = UUID(),
        name: String,
        date: Date = Date(),
        duration: TimeInterval = 0,
        isRecording: Bool = false,
        interruptedAt: Date? = nil,
        needsManualResume: Bool = false,
        segments: [AudioSegmentModel] = []
    ) {
        self.id = id
        self.name = name
        self.date = date
        self.duration = duration
        self.isRecording = isRecording
        self.interruptedAt = interruptedAt
        self.needsManualResume = needsManualResume
        self.segments = segments
    }
}
