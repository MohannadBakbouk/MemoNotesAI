import Foundation
import PersistenceCore

@MainActor
public final class StartRecordingUseCase {
    private let sessionRepo:  any SessionRepositoryProtocol
    private let audioService: any RecordingServiceProtocol

    public init(
        sessionRepo:  any SessionRepositoryProtocol,
        audioService: any RecordingServiceProtocol
    ) {
        self.sessionRepo  = sessionRepo
        self.audioService = audioService
    }

    /// Creates a SwiftData session then starts the audio engine.
    /// Returns the new session ID. Rolls back the session if the engine fails.
    public func execute() async throws -> UUID {
        let id    = UUID()
        let title = "Session-" + id.uuidString.prefix(5).uppercased()
        let sessionID = try await sessionRepo.createSession(name: title, date: Date())
        do {
            try await audioService.startRecording(sessionID: sessionID)
            try await sessionRepo.updateRecordingState(
                id: sessionID,
                update: RecordingSessionStateUpdate(isRecording: true)
            )
            return sessionID
        } catch {
            try? await sessionRepo.deleteSession(id: sessionID)
            throw error
        }
    }
}
