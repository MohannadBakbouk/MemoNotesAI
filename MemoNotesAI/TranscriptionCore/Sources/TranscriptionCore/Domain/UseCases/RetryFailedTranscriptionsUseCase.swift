import Foundation
import PersistenceCore

@MainActor
public final class RetryFailedTranscriptionsUseCase {
    private let segmentRepo: any SegmentRepositoryProtocol
    private let queue: TranscriptionQueue

    public init(segmentRepo: any SegmentRepositoryProtocol, queue: TranscriptionQueue) {
        self.segmentRepo = segmentRepo
        self.queue       = queue
    }

    public func execute() async throws {
        let failedIDs = try await segmentRepo.fetchFailedSegmentIDs()
        for segmentID in failedIDs {
            guard let segment = try await segmentRepo.fetchSegment(id: segmentID) else { continue }
            guard let filePath = segment.filePath else { continue }
            let retryCount = segment.transcription?.retryCount ?? 0
            queue.enqueue(segmentID: segmentID, filePath: filePath, retryCount: retryCount + 1)
        }
    }
}
