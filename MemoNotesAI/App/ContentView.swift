import SwiftUI
import RecordingFeature
import SessionsFeature

struct ContentView: View {
    let deps: AppDependencies

    @State private var selectedSession:  SessionDisplayModel?
    @State private var recoveryInfo:     RecoveredSessionInfo?

    var body: some View {
        TabView {
            // MARK: Record tab
            RecordingView(viewModel: deps.recordingViewModel)
                .tabItem { Label("Record",   systemImage: "mic.fill") }

            // MARK: Sessions tab
            // SessionListView owns its own NavigationStack + title bar.
            // Detail view is presented as a sheet to avoid nested NavigationStack issues.
            SessionListView(viewModel: deps.sessionListViewModel) { session in
                selectedSession = session
            }
            .tabItem { Label("Sessions", systemImage: "list.bullet") }
            .sheet(item: $selectedSession) { session in
                NavigationStack {
                    SessionDetailView(viewModel: deps.makeDetailViewModel(for: session))
                }
            }
        }
        // MARK: Recovery sheet
        .sheet(item: $recoveryInfo) { info in
            RecoverySheetView(
                info:         info,
                onResume:     { await deps.resumeInterruptedSession(info);   recoveryInfo = nil },
                onSaveClose:  { await deps.finalizeInterruptedSession(info); recoveryInfo = nil }
            )
        }
        // MARK: Launch tasks
        .task {
            // Attempt recovery first, then retry any failed transcriptions.
            recoveryInfo = await deps.checkForInterruptedSession()
            await deps.retryFailedTranscriptions()
        }
    }
}

// MARK: - Recovery sheet

private struct RecoverySheetView: View {
    let info:        RecoveredSessionInfo
    let onResume:    () async -> Void
    let onSaveClose: () async -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "waveform.badge.exclamationmark")
                .font(.system(size: 52))
                .foregroundStyle(.orange)

            VStack(spacing: 8) {
                Text("Recording was interrupted")
                    .font(.title2.weight(.semibold))
                Text(info.name)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text("\(info.segmentCount) segments · \(formatDuration(info.duration))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 16) {
                Button("Save & Close") {
                    Task { await onSaveClose() }
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Button("Resume") {
                    Task { await onResume() }
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.large)
            }

            Spacer()
        }
        .padding()
        .presentationDetents([.medium])
    }

    private func formatDuration(_ t: TimeInterval) -> String {
        let minutes = Int(t) / 60
        return minutes < 60 ? "\(minutes) min" : "\(minutes / 60) hr \(minutes % 60) min"
    }
}
