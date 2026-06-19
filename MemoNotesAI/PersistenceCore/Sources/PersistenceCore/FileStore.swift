import Foundation

public final class FileStore: FileStoreProtocol, @unchecked Sendable {
    private let fileManager: FileManager
    private let documentsDirectory: URL

    public init(
        fileManager: FileManager = .default,
        documentsDirectory: URL? = nil
    ) throws {
        self.fileManager = fileManager
        if let documentsDirectory {
            self.documentsDirectory = documentsDirectory
        } else {
            guard let url = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
                throw PersistenceError.fileOperationFailed("Documents directory unavailable.")
            }
            self.documentsDirectory = url
        }
    }

    public func sessionDirectory(for sessionID: UUID) throws -> URL {
        let directory = documentsDirectory
            .appendingPathComponent("sessions", isDirectory: true)
            .appendingPathComponent(sessionID.uuidString, isDirectory: true)

        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        return directory
    }

    public func segmentFileURL(sessionID: UUID, segmentIndex: Int) -> URL {
        let fileName = String(format: "segment_%03d.wav", segmentIndex)
        return documentsDirectory
            .appendingPathComponent("sessions", isDirectory: true)
            .appendingPathComponent(sessionID.uuidString, isDirectory: true)
            .appendingPathComponent(fileName, isDirectory: false)
    }

    public func deleteFile(at path: String) throws {
        guard fileManager.fileExists(atPath: path) else {
            return
        }

        do {
            try fileManager.removeItem(atPath: path)
        } catch {
            throw PersistenceError.fileOperationFailed(error.localizedDescription)
        }
    }

    public func fileExists(at path: String) -> Bool {
        fileManager.fileExists(atPath: path)
    }
}
