import Foundation
import PersistenceCore

public struct TranscriptionResult: Sendable {
    public let text: String

    public init(text: String) {
        self.text = text
    }
}

public protocol TranscriptionService: Sendable {
    var method: TranscriptionMethod { get }
    func transcribe(audioFileURL: URL) async throws -> TranscriptionResult
}
