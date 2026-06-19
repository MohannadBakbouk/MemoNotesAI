import SwiftUI

public struct SessionDetailView: View {
    @State private var viewModel: SessionDetailViewModel
    @State private var showCopyConfirmation = false

    public init(viewModel: SessionDetailViewModel) {
        _viewModel = State(wrappedValue: viewModel)
    }

    public var body: some View {
        List {
            // Session info header
            Section("Session Info") {
                LabeledContent("Date",     value: viewModel.session.date.formatted(date: .long, time: .shortened))
                LabeledContent("Duration", value: formatDuration(viewModel.session.duration))
                LabeledContent("Segments", value: segmentSummary)
            }

            // Transcript
            Section("Transcript") {
                if viewModel.isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                } else if viewModel.segments.isEmpty {
                    Text("No segments yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.segments) { segment in
                        SegmentTranscriptRow(
                            segment: segment,
                            onRetryWithGroq: {
                                Task { await viewModel.retryWithGroq(segment) }
                            },
                            onRetryWithWhisperKit: {
                                Task { await viewModel.retryWithWhisperKit(segment) }
                            }
                        )
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(viewModel.session.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !viewModel.fullTranscript.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        UIPasteboard.general.string = viewModel.fullTranscript
                        showCopyConfirmation = true
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                }
            }
        }
        .alert("Copied", isPresented: $showCopyConfirmation) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Full transcript copied to clipboard.")
        }
        .task { await viewModel.observeAndLoad() }
    }

    // MARK: - Helpers

    private var segmentSummary: String {
        "\(viewModel.session.segmentCount) · ✅ \(viewModel.session.transcribedCount) done"
    }

    private func formatDuration(_ interval: TimeInterval) -> String {
        let total   = Int(interval)
        let hours   = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }
}

