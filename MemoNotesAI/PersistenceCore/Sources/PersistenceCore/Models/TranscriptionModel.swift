import Foundation
import SwiftData

@Model
public final class TranscriptionModel {
    @Attribute(.unique) public var id: UUID
    public var text: String
    public var method: String
    public var retryCount: Int
    public var createdAt: Date

    public var segment: AudioSegmentModel?

    public var transcriptionMethod: TranscriptionMethod {
        get { TranscriptionMethod(rawValue: method) ?? .groq }
        set { method = newValue.rawValue }
    }

    public init(
        id: UUID = UUID(),
        text: String,
        method: TranscriptionMethod,
        retryCount: Int = 0,
        createdAt: Date = Date(),
        segment: AudioSegmentModel? = nil
    ) {
        self.id = id
        self.text = text
        self.method = method.rawValue
        self.retryCount = retryCount
        self.createdAt = createdAt
        self.segment = segment
    }
}
