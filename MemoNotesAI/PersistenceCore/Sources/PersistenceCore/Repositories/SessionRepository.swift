import Foundation
import SwiftData

@MainActor
public final class SessionRepository: SessionRepositoryProtocol {
    private let container: ModelContainer

    // MARK: - Change broadcasting

    private var continuations: [UUID: AsyncStream<Void>.Continuation] = [:]

    public init(container: ModelContainer) {
        self.container = container
    }

    private var context: ModelContext { container.mainContext }

    // MARK: - Public change stream

    /// Emits whenever any session is created, updated, or deleted.
    public func observeChanges() -> AsyncStream<Void> {
        let key = UUID()
        let (stream, cont) = AsyncStream<Void>.makeStream()
        continuations[key] = cont
        cont.onTermination = { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.continuations.removeValue(forKey: key)
            }
        }
        return stream
    }

    // MARK: - SessionRepositoryProtocol

    public func createSession(name: String, date: Date) async throws -> UUID {
        let session = RecordingSessionModel(name: name, date: date, isRecording: true)
        context.insert(session)
        try saveContext()
        broadcast()
        return session.id
    }

    public func fetchSessions() async throws -> [UUID] {
        let descriptor = FetchDescriptor<RecordingSessionModel>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        return try context.fetch(descriptor).map(\.id)
    }

    public func fetchSession(id: UUID) async throws -> RecordingSessionModel? {
        try fetchSessionModel(id: id)
    }

    public func updateRecordingState(id: UUID, update: RecordingSessionStateUpdate) async throws {
        guard let session = try fetchSessionModel(id: id) else {
            throw PersistenceError.sessionNotFound
        }
        session.isRecording = update.isRecording
        if let duration       = update.duration          { session.duration = duration }
        if let interruptedAt  = update.interruptedAt     { session.interruptedAt = interruptedAt }
        if update.clearInterruptedAt                     { session.interruptedAt = nil }
        if let needsManual    = update.needsManualResume { session.needsManualResume = needsManual }
        try saveContext()
        broadcast()
    }

    public func deleteSession(id: UUID) async throws {
        guard let session = try fetchSessionModel(id: id) else {
            throw PersistenceError.sessionNotFound
        }
        context.delete(session)
        try saveContext()
        broadcast()
    }

    public func fetchActiveRecordingSession() async throws -> RecordingSessionModel? {
        let descriptor = FetchDescriptor<RecordingSessionModel>(
            predicate: #Predicate { $0.isRecording == true },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        return try context.fetch(descriptor).first
    }

    // MARK: - Private

    private func broadcast() {
        var stale: [UUID] = []
        for (key, cont) in continuations {
            if case .terminated = cont.yield(()) { stale.append(key) }
        }
        stale.forEach { continuations.removeValue(forKey: $0) }
    }

    private func fetchSessionModel(id: UUID) throws -> RecordingSessionModel? {
        let descriptor = FetchDescriptor<RecordingSessionModel>(predicate: #Predicate { $0.id == id })
        return try context.fetch(descriptor).first
    }

    private func saveContext() throws {
        do { try context.save() }
        catch { throw PersistenceError.saveFailed(error.localizedDescription) }
    }
}
