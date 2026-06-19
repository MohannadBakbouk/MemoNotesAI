import Foundation

@MainActor
public protocol TranscriptionRepositoryProtocol: Sendable {
    func saveTranscription(
        segmentID: UUID,
        text: String,
        method: TranscriptionMethod,
        retryCount: Int
    ) async throws
}
