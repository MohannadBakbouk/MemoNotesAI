import SwiftUI
import PersistenceCore

public struct SegmentTranscriptRow: View {
    public let segment:               SegmentDisplayModel
    public let onRetryWithGroq:       (() -> Void)?
    public let onRetryWithWhisperKit: (() -> Void)?

    public init(
        segment:               SegmentDisplayModel,
        onRetryWithGroq:       (() -> Void)? = nil,
        onRetryWithWhisperKit: (() -> Void)? = nil
    ) {
        self.segment               = segment
        self.onRetryWithGroq       = onRetryWithGroq
        self.onRetryWithWhisperKit = onRetryWithWhisperKit
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(timeRange)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            content
        }
        .padding(.vertical, 2)
    }

    // MARK: - Private

    private var timeRange: String {
        let start = formatTime(segment.startTime)
        let end   = formatTime(segment.startTime + segment.duration)
        return "[\(start) – \(end)]"
    }

    @ViewBuilder
    private var content: some View {
        switch segment.status {
        case .pending:
            Label("Queued…", systemImage: "clock")
                .font(.subheadline)
                .foregroundStyle(.secondary)

        case .transcribing:
            Label("Transcribing…", systemImage: "ellipsis")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .symbolEffect(.pulse)

        case .success:
            Text(segment.transcriptionText ?? "")
                .font(.body)

        case .silent:
            retryableRow(
                label:      "No speech detected",
                icon:       "waveform.slash",
                labelColor: .secondary
            )

        case .failed:
            retryableRow(
                label:      "Failed",
                icon:       "xmark.circle.fill",
                labelColor: .red
            )
        }
    }

    @ViewBuilder
    private func retryableRow(label: String, icon: String, labelColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Status label — display only, no tap action
            Label(label, systemImage: icon)
                .font(.subheadline)
                .foregroundStyle(labelColor)

            // Retry buttons pinned to the bottom-right
            HStack {
                Spacer()

                Button {
                    onRetryWithGroq?()
                } label: {
                    Label("Cloud", systemImage: "arrow.counterclockwise.icloud.fill")
                        .labelStyle(.iconOnly)
                        .font(.subheadline)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
                .help("Retry with Groq")

                Button {
                    onRetryWithWhisperKit?()
                } label: {
                    Label("On-device", systemImage: "cpu")
                        .labelStyle(.iconOnly)
                        .font(.subheadline)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.indigo)
                .help("Transcribe on-device")
            }
        }
    }

    private func formatTime(_ t: TimeInterval) -> String {
        let total   = Int(t)
        let hours   = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }
}
