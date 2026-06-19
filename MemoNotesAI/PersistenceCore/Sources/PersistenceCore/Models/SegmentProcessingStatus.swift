import Foundation

public enum SegmentProcessingStatus: String, Codable, Sendable, CaseIterable {
    case pending
    case transcribing
    case success
    case silent   // Groq returned an empty transcript — no speech detected in this segment
    case failed
}
