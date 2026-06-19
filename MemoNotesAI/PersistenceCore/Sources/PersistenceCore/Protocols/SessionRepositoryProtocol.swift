import Foundation

@MainActor
public protocol SessionRepositoryProtocol: Sendable {
    func createSession(name: String, date: Date) async throws -> UUID
    func fetchSessions() async throws -> [UUID]
    func fetchSession(id: UUID) async throws -> RecordingSessionModel?
    func updateRecordingState(id: UUID, update: RecordingSessionStateUpdate) async throws
    func deleteSession(id: UUID) async throws
    func fetchActiveRecordingSession() async throws -> RecordingSessionModel?
}
