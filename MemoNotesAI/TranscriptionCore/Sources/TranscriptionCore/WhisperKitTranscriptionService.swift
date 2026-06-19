import Foundation
import WhisperKit
import PersistenceCore

public final class WhisperKitTranscriptionService: TranscriptionService, @unchecked Sendable {
    public let method: TranscriptionMethod = .whisperkit

    private var whisperKit: WhisperKit?
    private let initLock = NSLock()

    public init() {}

    public func transcribe(audioFileURL: URL) async throws -> TranscriptionResult {
        let kit = try await loadWhisperKit()

        // Lower noSpeechThreshold (default 0.6 → 0.3) so the model needs stronger
        // confidence before declaring silence — reduces false "no speech detected" on
        // accented or quiet speech.
        let options = DecodingOptions(noSpeechThreshold: 0.3)
        let results = try await kit.transcribe(audioPath: audioFileURL.path, decodeOptions: options)
        let text = results.map(\.text).joined(separator: " ")
        return TranscriptionResult(text: text)
    }

    // MARK: - Private

    private func loadWhisperKit() async throws -> WhisperKit {
        if let kit = initLock.withLock({ whisperKit }) { return kit }

        guard let modelFolder = Bundle.module.url(
            forResource: "openai_whisper-base.en",
            withExtension: nil
        ) else {
            throw TranscriptionError.modelNotFound
        }

        let config = WhisperKitConfig(modelFolder: modelFolder.path, load: true)
        let kit = try await WhisperKit(config)

        initLock.withLock { whisperKit = kit }
        return kit
    }
}
