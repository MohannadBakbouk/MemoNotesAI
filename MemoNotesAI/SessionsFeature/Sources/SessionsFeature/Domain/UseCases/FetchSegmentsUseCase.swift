import Foundation
import PersistenceCore

@MainActor
public final class FetchSegmentsUseCase {
    private let segmentRepo: any SegmentRepositoryProtocol

    public init(segmentRepo: any SegmentRepositoryProtocol) {
        self.segmentRepo = segmentRepo
    }

    public func execute(sessionID: UUID) async throws -> [SegmentDisplayModel] {
        let ids = try await segmentRepo.fetchSegments(sessionID: sessionID)
        var result: [SegmentDisplayModel] = []
        result.reserveCapacity(ids.count)
        for id in ids {
            if let model = try await segmentRepo.fetchSegment(id: id) {
                result.append(SegmentDisplayModel(from: model))
            }
        }
        return result.sorted { $0.segmentIndex < $1.segmentIndex }
    }
}
