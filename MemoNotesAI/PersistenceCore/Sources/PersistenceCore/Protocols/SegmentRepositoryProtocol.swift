import Foundation

@MainActor
public protocol SegmentRepositoryProtocol: Sendable {
    func createSegment(_ record: NewSegmentRecord) async throws -> UUID
    func fetchSegments(sessionID: UUID) async throws -> [UUID]
    func fetchSegment(id: UUID) async throws -> AudioSegmentModel?
    func updateStatus(_ status: SegmentProcessingStatus, forSegmentID segmentID: UUID) async throws
    func setAudioDeletedAt(_ date: Date, forSegmentID segmentID: UUID) async throws
    func setFilePath(_ path: String?, forSegmentID segmentID: UUID) async throws
    func filePathForDeletionIfEligible(segmentID: UUID) async throws -> String?
    func fetchFailedSegmentIDs() async throws -> [UUID]
}
