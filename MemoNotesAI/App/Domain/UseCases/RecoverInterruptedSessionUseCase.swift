import Foundation
import PersistenceCore

/// Value returned when an interrupted session is found at launch.
public struct RecoveredSessionInfo: Identifiable, Sendable {
    public var id: UUID { sessionID }
    public let sessionID:    UUID
    public let name:         String
    public let segmentCount: Int
    public let duration:     TimeInterval
}

/// Checks SwiftData on launch for a session that was recording when the app was killed.
@MainActor
final class RecoverInterruptedSessionUseCase {
    private let sessionRepo: any SessionRepositoryProtocol

    init(sessionRepo: any SessionRepositoryProtocol) {
        self.sessionRepo = sessionRepo
    }

    func execute() async throws -> RecoveredSessionInfo? {
        guard let session = try await sessionRepo.fetchActiveRecordingSession() else { return nil }
        return RecoveredSessionInfo(
            sessionID:    session.id,
            name:         session.name,
            segmentCount: session.segments.count,
            duration:     session.duration
        )
    }
}
