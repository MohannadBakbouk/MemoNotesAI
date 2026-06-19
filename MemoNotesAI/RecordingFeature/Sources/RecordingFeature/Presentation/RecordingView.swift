import SwiftUI

public struct RecordingView: View {
    @State private var viewModel: RecordingViewModel

    public init(viewModel: RecordingViewModel) {
        _viewModel = State(wrappedValue: viewModel)
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()

                statusBadge

                if viewModel.phase != .idle {
                    Text(formatElapsed(viewModel.elapsedSeconds))
                        .font(.system(size: 52, weight: .thin, design: .monospaced))
                        .foregroundStyle(.primary)
                        .contentTransition(.numericText())
                        .animation(.easeInOut(duration: 0.2), value: viewModel.elapsedSeconds)
                }

                WaveformView(
                    level:    viewModel.audioLevel,
                    isActive: viewModel.phase == .recording
                )
                .padding(.horizontal, 24)

                RecordButton(phase: viewModel.phase) {
                    handleButtonTap()
                }

                if viewModel.segmentCount > 0 {
                    Text("\(viewModel.segmentCount) segments · \(viewModel.transcribedCount) transcribed")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .transition(.opacity)
                }

                Spacer()
            }
            .navigationTitle("Record")
            .navigationBarTitleDisplayMode(.inline)
            .overlay(alignment: .bottom) {
                if viewModel.showResumePrompt {
                    resumeBanner
                        .padding(.bottom, 24)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.25), value: viewModel.showResumePrompt)
            .animation(.easeInOut,                  value: viewModel.segmentCount)
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

    // MARK: - Subviews

    @ViewBuilder
    private var statusBadge: some View {
        let (label, color): (String, Color) = {
            switch viewModel.phase {
            case .idle:      return ("Ready",      .secondary)
            case .recording: return ("● REC",      .red)
            case .paused:    return ("⏸ Paused",  .orange)
            }
        }()
        Text(label)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(color.opacity(0.1), in: Capsule())
            .animation(.easeInOut, value: viewModel.phase)
    }

    private var resumeBanner: some View {
        VStack(spacing: 10) {
            Text("Recording paused — Call ended")
                .font(.subheadline.weight(.medium))
            HStack(spacing: 16) {
                Button("Resume") {
                    Task { await viewModel.resumeAfterPrompt() }
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)

                Button("Save & Close") {
                    Task { await viewModel.saveAndClose() }
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 20)
    }

    // MARK: - Helpers

    private func formatElapsed(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        } else {
            return String(format: "%02d:%02d", m, s)
        }
    }

    // MARK: - Actions

    private func handleButtonTap() {
        Task {
            switch viewModel.phase {
            case .idle:
                await viewModel.startRecording()
            case .recording, .paused:
                await viewModel.stopRecording()
            }
        }
    }
}
