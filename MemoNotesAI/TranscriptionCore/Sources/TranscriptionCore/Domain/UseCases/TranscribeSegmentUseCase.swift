import Foundation
import PersistenceCore

@MainActor
public final class TranscribeSegmentUseCase {
    private let groqService:        any TranscriptionService
    private let whisperKitService:  any TranscriptionService
    private let segmentRepo:        any SegmentRepositoryProtocol
    private let transcriptionRepo:  any TranscriptionRepositoryProtocol
    private let deleteAudioUseCase: DeleteSegmentAudioUseCase
    private let fileStore:          any FileStoreProtocol

    public init(
        groqService:        any TranscriptionService,
        whisperKitService:  any TranscriptionService,
        segmentRepo:        any SegmentRepositoryProtocol,
        transcriptionRepo:  any TranscriptionRepositoryProtocol,
        deleteAudioUseCase: DeleteSegmentAudioUseCase,
        fileStore:          any FileStoreProtocol
    ) {
        self.groqService       = groqService
        self.whisperKitService = whisperKitService
        self.segmentRepo       = segmentRepo
        self.transcriptionRepo = transcriptionRepo
        self.deleteAudioUseCase = deleteAudioUseCase
        self.fileStore         = fileStore
    }

    /// - Parameter forcedProvider: When set from a manual retry button, only that provider
    ///   is used with no fallback. When nil (auto), Groq runs first; on failure WhisperKit
    ///   takes over automatically.
    public func execute(
        segmentID:       UUID,
        filePath:        String,
        retryCount:      Int,
        forcedProvider:  TranscriptionMethod? = nil
    ) async throws {
        guard fileStore.fileExists(at: filePath) else {
            try await segmentRepo.updateStatus(.failed, forSegmentID: segmentID)
            throw TranscriptionError.noAudioFile
        }

        try await segmentRepo.updateStatus(.transcribing, forSegmentID: segmentID)

        if let forced = forcedProvider {
            // Manual retry: honour the user's explicit choice, no fallback.
            let service: any TranscriptionService = (forced == .groq) ? groqService : whisperKitService
            try await run(
                service:         service,
                segmentID:       segmentID,
                filePath:        filePath,
                retryCount:      retryCount,
                deleteOnSuccess: forced == .groq
            )
        } else {
            // Auto flow: Groq primary → WhisperKit fallback.
            do {
                try await run(
                    service:         groqService,
                    segmentID:       segmentID,
                    filePath:        filePath,
                    retryCount:      retryCount,
                    deleteOnSuccess: true
                )
            } catch {
                // Groq exhausted all internal retries — try on-device silently.
                try await run(
                    service:         whisperKitService,
                    segmentID:       segmentID,
                    filePath:        filePath,
                    retryCount:      retryCount,
                    deleteOnSuccess: false
                )
            }
        }
    }

    // MARK: - Private

    private func run(
        service:         any TranscriptionService,
        segmentID:       UUID,
        filePath:        String,
        retryCount:      Int,
        deleteOnSuccess: Bool
    ) async throws {
        do {
            let result = try await service.transcribe(audioFileURL: URL(fileURLWithPath: filePath))

            guard !result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                try await segmentRepo.updateStatus(.silent, forSegmentID: segmentID)
                return
            }

            try await transcriptionRepo.saveTranscription(
                segmentID: segmentID,
                text:      result.text,
                method:    service.method,
                retryCount: retryCount
            )
            try await segmentRepo.updateStatus(.success, forSegmentID: segmentID)

            // Audio is only deleted after a successful Groq transcription.
            // WhisperKit segments keep their audio so the user can retry with Groq later.
            if deleteOnSuccess {
                try await deleteAudioUseCase.execute(segmentID: segmentID)
            }

        } catch {
            try? await segmentRepo.updateStatus(.failed, forSegmentID: segmentID)
            throw error
        }
    }
}
