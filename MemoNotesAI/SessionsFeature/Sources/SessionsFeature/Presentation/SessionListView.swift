import SwiftUI

public struct SessionListView: View {
    @State private var viewModel: SessionListViewModel
    public var onSelectSession: (SessionDisplayModel) -> Void

    public init(
        viewModel: SessionListViewModel,
        onSelectSession: @escaping (SessionDisplayModel) -> Void
    ) {
        _viewModel       = State(wrappedValue: viewModel)
        self.onSelectSession = onSelectSession
    }

    public var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.sessions.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.sessions.isEmpty {
                    ContentUnavailableView(
                        "No Recordings",
                        systemImage: "mic.slash",
                        description: Text("Start recording to see your sessions here.")
                    )
                } else {
                    list
                }
            }
            .navigationTitle("My Recordings")
            .toolbar {
                EditButton()
            }
            .refreshable {
                await viewModel.loadSessions()
            }
            .alert("Error", isPresented: .init(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { viewModel.errorMessage = nil }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
        .task { await viewModel.observeAndLoad() }
    }

    private var list: some View {
        List {
            ForEach(viewModel.sessions) { session in
                Button { onSelectSession(session) } label: {
                    SessionRowView(session: session)
                }
                .buttonStyle(.plain)
            }
            .onDelete { offsets in
                Task { await viewModel.deleteSessionsAt(offsets: offsets) }
            }
        }
        .listStyle(.insetGrouped)
    }
}
