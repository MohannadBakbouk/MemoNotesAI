import Foundation
import Observation

@MainActor
@Observable
public final class SessionDetailViewModel {
    public var segments:     [SegmentDisplayModel] = []
    public var isLoading:    Bool                  = false
    public var errorMessage: String?

    public let session: SessionDisplayModel

    private let fetchUseCase:   FetchSegmentsUseCase
    private let changeStream:   AsyncStream<Void>

    /// Wired by AppDependencies to re-enqueue a segment forcing Groq.
    public var onRetryWithGroq: (@MainActor (UUID, String) -> Void)?

    /// Wired by AppDependencies to re-enqueue a segment forcing WhisperKit (on-device).
    public var onRetryWithWhisperKit: (@MainActor (UUID, String) -> Void)?

    public init(
        session:      SessionDisplayModel,
        fetchUseCase: FetchSegmentsUseCase,
        changeStream: AsyncStream<Void>
    ) {
        self.session       = session
        self.fetchUseCase  = fetchUseCase
        self.changeStream  = changeStream
    }

    /// Call from `.task { }` in the detail view.
    /// Performs the initial load then keeps the segment list live until cancelled.
    public func observeAndLoad() async {
        await loadSegments()
        for await _ in changeStream {
            await loadSegments()
        }
    }

    public func retryWithGroq(_ segment: SegmentDisplayModel) async {
        guard let path = segment.filePath else { return }
        onRetryWithGroq?(segment.id, path)
        await loadSegments()
    }

    public func retryWithWhisperKit(_ segment: SegmentDisplayModel) async {
        guard let path = segment.filePath else { return }
        onRetryWithWhisperKit?(segment.id, path)
        await loadSegments()
    }

    public func loadSegments() async {
        isLoading    = true
        errorMessage = nil
        defer { isLoading = false }
        do    { segments = try await fetchUseCase.execute(sessionID: session.id) }
        catch { errorMessage = error.localizedDescription }
    }

    public var fullTranscript: String {
        segments
            .compactMap { $0.transcriptionText }
            .joined(separator: " ")
    }
}
