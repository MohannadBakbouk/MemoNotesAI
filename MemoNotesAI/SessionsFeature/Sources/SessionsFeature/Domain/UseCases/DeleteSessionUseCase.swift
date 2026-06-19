import Foundation
import PersistenceCore

@MainActor
public final class DeleteSessionUseCase {
    private let sessionRepo: any SessionRepositoryProtocol
    private let fileStore:   any FileStoreProtocol

    public init(sessionRepo: any SessionRepositoryProtocol, fileStore: any FileStoreProtocol) {
        self.sessionRepo = sessionRepo
        self.fileStore   = fileStore
    }

    public func execute(sessionID: UUID) async throws {
        // Cascade delete of segments and transcriptions is handled by SwiftData.
        // Remove the session audio directory from disk before the DB record is gone.
        if let dir = try? fileStore.sessionDirectory(for: sessionID) {
            try? FileManager.default.removeItem(at: dir)
        }
        try await sessionRepo.deleteSession(id: sessionID)
    }
}
