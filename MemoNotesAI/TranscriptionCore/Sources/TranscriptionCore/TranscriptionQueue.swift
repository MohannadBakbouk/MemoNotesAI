import Foundation
import PersistenceCore

/// Serial transcription runner backed by AsyncStream + a single MainActor Task.
///
/// Replaces the GCD-based queue with native Swift Concurrency:
/// - Serial ordering: the consumer Task awaits each job to completion before pulling the next.
/// - Pause/resume: a simple Bool checked between jobs; Task.sleep yields the actor during waits.
/// - Cancellation: falls out naturally when the consuming Task is cancelled.
/// - No polling: AsyncStream suspends the consumer when the queue is empty.
@MainActor
public final class TranscriptionQueue: @unchecked Sendable {

    private struct Job: Sendable {
        let segmentID:      UUID
        let filePath:       String
        let retryCount:     Int
        /// When set, bypasses the auto Groq→WhisperKit fallback and uses this provider only.
        let forcedProvider: TranscriptionMethod?
    }

    private let continuation: AsyncStream<Job>.Continuation
    private var isPaused = false
    private var scheduledResumeTask: Task<Void, Never>?

    public init(transcribeUseCase: TranscribeSegmentUseCase) {
        let (stream, continuation) = AsyncStream<Job>.makeStream(bufferingPolicy: .unbounded)
        self.continuation = continuation

        Task { @MainActor in
            for await job in stream {
                while self.isPaused {
                    try? await Task.sleep(for: .seconds(2))
                }
                try? await transcribeUseCase.execute(
                    segmentID:      job.segmentID,
                    filePath:       job.filePath,
                    retryCount:     job.retryCount,
                    forcedProvider: job.forcedProvider
                )
            }
        }
    }

    // MARK: - Public API

    public func enqueue(
        segmentID:      UUID,
        filePath:       String,
        retryCount:     Int = 0,
        forcedProvider: TranscriptionMethod? = nil
    ) {
        continuation.yield(Job(
            segmentID:      segmentID,
            filePath:       filePath,
            retryCount:     retryCount,
            forcedProvider: forcedProvider
        ))
    }

    /// Pause processing. Pass a `resumeDate` to auto-resume (e.g. after Retry-After).
    public func pause(until resumeDate: Date? = nil) {
        isPaused = true
        scheduledResumeTask?.cancel()
        guard let date = resumeDate else { return }
        let delay = max(0, date.timeIntervalSinceNow)
        scheduledResumeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            self?.resume()
        }
    }

    public func resume() {
        isPaused = false
        scheduledResumeTask?.cancel()
        scheduledResumeTask = nil
    }
}
