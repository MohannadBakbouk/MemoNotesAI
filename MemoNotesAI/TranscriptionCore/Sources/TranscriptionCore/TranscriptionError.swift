import Foundation

public enum TranscriptionError: Error, Sendable {
    case rateLimited(retryAfter: TimeInterval?)
    case httpError(statusCode: Int)
    case noAudioFile
    case decodingFailed
    case modelNotFound
}
