import Foundation

public protocol FileStoreProtocol: Sendable {
    func sessionDirectory(for sessionID: UUID) throws -> URL
    func segmentFileURL(sessionID: UUID, segmentIndex: Int) -> URL
    func deleteFile(at path: String) throws
    func fileExists(at path: String) -> Bool
}
