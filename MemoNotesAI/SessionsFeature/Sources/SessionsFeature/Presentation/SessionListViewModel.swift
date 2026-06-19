import Foundation
import Observation

@MainActor
@Observable
public final class SessionListViewModel {
    public var sessions:     [SessionDisplayModel] = []
    public var isLoading:    Bool                  = false
    public var errorMessage: String?

    private let fetchUseCase:  FetchSessionsUseCase
    private let deleteUseCase: DeleteSessionUseCase
    private let sessionStream: AsyncStream<Void>
    private let segmentStream: AsyncStream<Void>

    public init(
        fetchUseCase:  FetchSessionsUseCase,
        deleteUseCase: DeleteSessionUseCase,
        sessionStream: AsyncStream<Void>,
        segmentStream: AsyncStream<Void>
    ) {
        self.fetchUseCase  = fetchUseCase
        self.deleteUseCase = deleteUseCase
        self.sessionStream = sessionStream
        self.segmentStream = segmentStream
    }

    /// Call from `.task { }` in the list view.
    /// Performs the initial fetch then keeps the list live as long as the Task runs.
    public func observeAndLoad() async {
        await loadSessions()
        // Observe both streams concurrently; each reload re-fetches the full list.
        async let sessionWatch: Void = {
            for await _ in sessionStream { await loadSessions() }
        }()
        async let segmentWatch: Void = {
            for await _ in segmentStream { await loadSessions() }
        }()
        _ = await (sessionWatch, segmentWatch)
    }

    public func loadSessions() async {
        isLoading    = true
        errorMessage = nil
        defer { isLoading = false }
        do    { sessions = try await fetchUseCase.execute() }
        catch { errorMessage = error.localizedDescription }
    }

    public func deleteSession(id: UUID) async {
        do {
            try await deleteUseCase.execute(sessionID: id)
            sessions.removeAll { $0.id == id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func deleteSessionsAt(offsets: IndexSet) async {
        let targets = offsets.map { sessions[$0].id }
        for id in targets { await deleteSession(id: id) }
    }
}
