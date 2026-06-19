import Foundation
import PersistenceCore

@MainActor
public final class StopRecordingUseCase {
    private let sessionRepo:  any SessionRepositoryProtocol
    private let audioService: any RecordingServiceProtocol

    public init(
        sessionRepo:  any SessionRepositoryProtocol,
        audioService: any RecordingServiceProtocol
    ) {
        self.sessionRepo  = sessionRepo
        self.audioService = audioService
    }

    /// Stops the audio engine and marks the session as finished.
    /// Calculates total duration from all segments.
    public func execute(sessionID: UUID) async throws {
        try await audioService.stopRecording()

        if let session = try await sessionRepo.fetchSession(id: sessionID) {
            let totalDuration = session.segments.reduce(0) { $0 + $1.duration }
            try await sessionRepo.updateRecordingState(
                id: sessionID,
                update: RecordingSessionStateUpdate(
                    isRecording: false,
                    duration: totalDuration,
                    clearInterruptedAt: true
                )
            )
        }
    }
}
