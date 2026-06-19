import Foundation
import PersistenceCore

@MainActor
public final class FetchSessionsUseCase {
    private let sessionRepo: any SessionRepositoryProtocol

    public init(sessionRepo: any SessionRepositoryProtocol) {
        self.sessionRepo = sessionRepo
    }

    public func execute() async throws -> [SessionDisplayModel] {
        let ids = try await sessionRepo.fetchSessions()
        var result: [SessionDisplayModel] = []
        result.reserveCapacity(ids.count)
        for id in ids {
            if let model = try await sessionRepo.fetchSession(id: id) {
                result.append(SessionDisplayModel(from: model))
            }
        }
        return result.sorted { $0.date > $1.date }
    }
}
