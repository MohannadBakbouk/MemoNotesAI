import Foundation
import PersistenceCore
import AudioCore

/// Public façade composed by AppDependencies.
/// @MainActor so activeSessionID is safely mutated from the main thread.
@MainActor
public final class TranscriptionPipeline {
    private let queue:        TranscriptionQueue
    private let retryUseCase: RetryFailedTranscriptionsUseCase
    private let segmentRepo:  any SegmentRepositoryProtocol

    /// Set by AppDependencies when recording starts; cleared when it stops.
    public var activeSessionID: UUID?

    public init(
        queue:        TranscriptionQueue,
        retryUseCase: RetryFailedTranscriptionsUseCase,
        segmentRepo:  any SegmentRepositoryProtocol
    ) {
        self.queue        = queue
        self.retryUseCase = retryUseCase
        self.segmentRepo  = segmentRepo
    }

    /// Called (via Task @MainActor) from AudioRecordingService's segmentClosedHandler.
    public func segmentClosed(_ info: ClosedSegmentInfo) {
        guard let sessionID = activeSessionID else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            let record = NewSegmentRecord(
                sessionID:    sessionID,
                segmentIndex: info.segmentIndex,
                filePath:     info.path,
                startTime:    info.startTime,
                duration:     info.duration
            )
            guard let segmentID = try? await self.segmentRepo.createSegment(record) else { return }
            self.queue.enqueue(segmentID: segmentID, filePath: info.path)
        }
    }

    /// Re-enqueue all failed segments — call at app launch or on network restore.
    public func retryAllFailed() async throws {
        try await retryUseCase.execute()
    }
}
