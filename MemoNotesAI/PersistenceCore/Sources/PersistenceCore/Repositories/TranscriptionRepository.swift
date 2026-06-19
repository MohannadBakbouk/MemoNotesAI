import Foundation
import SwiftData

@MainActor
public final class TranscriptionRepository: TranscriptionRepositoryProtocol {
    private let container: ModelContainer

    public init(container: ModelContainer) {
        self.container = container
    }

    private var context: ModelContext {
        container.mainContext
    }

    /// Delete-on-success step 1–2: persist transcript and commit before any audio deletion.
    public func saveTranscription(
        segmentID: UUID,
        text: String,
        method: TranscriptionMethod,
        retryCount: Int = 0
    ) async throws {
        guard let segment = try fetchSegmentModel(id: segmentID) else {
            throw PersistenceError.segmentNotFound
        }

        if let existing = segment.transcription {
            context.delete(existing)
        }

        let transcription = TranscriptionModel(
            text: text,
            method: method,
            retryCount: retryCount,
            segment: segment
        )
        segment.transcription = transcription
        context.insert(transcription)

        try saveContext()
    }

    private func fetchSegmentModel(id: UUID) throws -> AudioSegmentModel? {
        let descriptor = FetchDescriptor<AudioSegmentModel>(
            predicate: #Predicate { $0.id == id }
        )
        return try context.fetch(descriptor).first
    }

    private func saveContext() throws {
        do {
            try context.save()
        } catch {
            throw PersistenceError.saveFailed(error.localizedDescription)
        }
    }
}
