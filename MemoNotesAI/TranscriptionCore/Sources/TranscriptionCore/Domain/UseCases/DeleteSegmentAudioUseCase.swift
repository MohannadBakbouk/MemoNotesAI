import Foundation
import PersistenceCore

@MainActor
public final class DeleteSegmentAudioUseCase {
    private let segmentRepo: any SegmentRepositoryProtocol
    private let fileStore: any FileStoreProtocol

    public init(segmentRepo: any SegmentRepositoryProtocol, fileStore: any FileStoreProtocol) {
        self.segmentRepo = segmentRepo
        self.fileStore   = fileStore
    }

    public func execute(segmentID: UUID) async throws {
        guard let path = try await segmentRepo.filePathForDeletionIfEligible(segmentID: segmentID) else {
            return
        }
        try fileStore.deleteFile(at: path)
        try await segmentRepo.setAudioDeletedAt(Date(), forSegmentID: segmentID)
        try await segmentRepo.setFilePath(nil, forSegmentID: segmentID)
    }
}
