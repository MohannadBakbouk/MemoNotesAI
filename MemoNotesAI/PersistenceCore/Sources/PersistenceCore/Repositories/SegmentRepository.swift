import Foundation
import SwiftData

@MainActor
public final class SegmentRepository: SegmentRepositoryProtocol {
    private let container: ModelContainer

    // MARK: - Change broadcasting

    /// Keyed continuations for per-session observers (SessionDetailViewModel).
    private var sessionContinuations: [UUID: (sessionID: UUID, cont: AsyncStream<Void>.Continuation)] = [:]
    /// Keyed continuations for any-segment observers (SessionListViewModel).
    private var anyContinuations: [UUID: AsyncStream<Void>.Continuation] = [:]

    public init(container: ModelContainer) {
        self.container = container
    }

    private var context: ModelContext { container.mainContext }

    // MARK: - Public change streams

    /// Emits whenever any segment belonging to `sessionID` changes.
    public func observeChanges(sessionID: UUID) -> AsyncStream<Void> {
        let key = UUID()
        let (stream, cont) = AsyncStream<Void>.makeStream()
        sessionContinuations[key] = (sessionID: sessionID, cont: cont)
        cont.onTermination = { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.sessionContinuations.removeValue(forKey: key)
            }
        }
        return stream
    }

    /// Emits whenever any segment (in any session) changes.
    public func observeAnyChange() -> AsyncStream<Void> {
        let key = UUID()
        let (stream, cont) = AsyncStream<Void>.makeStream()
        anyContinuations[key] = cont
        cont.onTermination = { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.anyContinuations.removeValue(forKey: key)
            }
        }
        return stream
    }

    // MARK: - SegmentRepositoryProtocol

    public func createSegment(_ record: NewSegmentRecord) async throws -> UUID {
        guard let session = try fetchSessionModel(id: record.sessionID) else {
            throw PersistenceError.sessionNotFound
        }

        let segment = AudioSegmentModel(
            segmentIndex: record.segmentIndex,
            filePath: record.filePath,
            startTime: record.startTime,
            duration: record.duration,
            status: .pending,
            session: session
        )
        session.segments.append(segment)
        context.insert(segment)
        try saveContext()
        broadcast(sessionID: record.sessionID)
        return segment.id
    }

    public func fetchSegments(sessionID: UUID) async throws -> [UUID] {
        guard let session = try fetchSessionModel(id: sessionID) else {
            throw PersistenceError.sessionNotFound
        }
        return session.segments
            .sorted { $0.segmentIndex < $1.segmentIndex }
            .map(\.id)
    }

    public func fetchSegment(id: UUID) async throws -> AudioSegmentModel? {
        try fetchSegmentModel(id: id)
    }

    public func updateStatus(_ status: SegmentProcessingStatus, forSegmentID segmentID: UUID) async throws {
        guard let segment = try fetchSegmentModel(id: segmentID) else {
            throw PersistenceError.segmentNotFound
        }
        let sessionID = segment.session?.id
        segment.processingStatus = status
        try saveContext()
        if let sessionID { broadcast(sessionID: sessionID) }
    }

    public func setAudioDeletedAt(_ date: Date, forSegmentID segmentID: UUID) async throws {
        guard let segment = try fetchSegmentModel(id: segmentID) else {
            throw PersistenceError.segmentNotFound
        }
        guard segment.processingStatus == .success else {
            throw PersistenceError.invalidStateTransition(from: segment.processingStatus, to: .success)
        }
        guard segment.transcription != nil else { throw PersistenceError.transcriptionMissing }

        segment.audioDeletedAt = date
        try saveContext()
    }

    public func setFilePath(_ path: String?, forSegmentID segmentID: UUID) async throws {
        guard let segment = try fetchSegmentModel(id: segmentID) else {
            throw PersistenceError.segmentNotFound
        }
        if path == nil {
            guard segment.processingStatus == .success else {
                throw PersistenceError.invalidStateTransition(from: segment.processingStatus, to: .success)
            }
            guard segment.transcription != nil else { throw PersistenceError.transcriptionMissing }
        }
        segment.filePath = path
        try saveContext()
    }

    public func filePathForDeletionIfEligible(segmentID: UUID) async throws -> String? {
        guard let segment = try fetchSegmentModel(id: segmentID) else {
            throw PersistenceError.segmentNotFound
        }
        guard segment.processingStatus == .success else { return nil }
        guard segment.transcription != nil else { throw PersistenceError.transcriptionMissing }
        guard segment.audioDeletedAt == nil else { return nil }
        return segment.filePath
    }

    public func fetchFailedSegmentIDs() async throws -> [UUID] {
        let failedStatus = SegmentProcessingStatus.failed.rawValue
        let descriptor = FetchDescriptor<AudioSegmentModel>(
            predicate: #Predicate { $0.status == failedStatus },
            sortBy: [SortDescriptor(\.segmentIndex)]
        )
        return try context.fetch(descriptor).map(\.id)
    }

    // MARK: - Private

    private func broadcast(sessionID: UUID) {
        // Notify per-session observers
        var staleSessionKeys: [UUID] = []
        for (key, entry) in sessionContinuations where entry.sessionID == sessionID {
            if case .terminated = entry.cont.yield(()) { staleSessionKeys.append(key) }
        }
        staleSessionKeys.forEach { sessionContinuations.removeValue(forKey: $0) }

        // Notify any-change observers
        var staleAnyKeys: [UUID] = []
        for (key, cont) in anyContinuations {
            if case .terminated = cont.yield(()) { staleAnyKeys.append(key) }
        }
        staleAnyKeys.forEach { anyContinuations.removeValue(forKey: $0) }
    }

    private func fetchSessionModel(id: UUID) throws -> RecordingSessionModel? {
        let descriptor = FetchDescriptor<RecordingSessionModel>(predicate: #Predicate { $0.id == id })
        return try context.fetch(descriptor).first
    }

    private func fetchSegmentModel(id: UUID) throws -> AudioSegmentModel? {
        let descriptor = FetchDescriptor<AudioSegmentModel>(predicate: #Predicate { $0.id == id })
        return try context.fetch(descriptor).first
    }

    private func saveContext() throws {
        do { try context.save() }
        catch { throw PersistenceError.saveFailed(error.localizedDescription) }
    }
}
