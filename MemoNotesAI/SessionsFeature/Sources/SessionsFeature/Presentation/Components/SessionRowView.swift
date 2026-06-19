import SwiftUI

public struct SessionRowView: View {
    public let session: SessionDisplayModel

    public init(session: SessionDisplayModel) {
        self.session = session
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                if session.needsManualResume {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.orange)
                        .imageScale(.small)
                }
                Text(session.name)
                    .font(.headline)
                    .lineLimit(1)
            }

            Text(subtitleText)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            transcriptionStatus
        }
        .padding(.vertical, 4)
    }

    // MARK: - Helpers

    private var subtitleText: String {
        let dateStr     = session.date.formatted(date: .abbreviated, time: .omitted)
        let durationStr = formatDuration(session.duration)
        let segStr      = "\(session.segmentCount) seg"
        return "\(dateStr) · \(durationStr) · \(segStr)"
    }

    @ViewBuilder
    private var transcriptionStatus: some View {
        if session.needsManualResume {
            Text("Interrupted — tap to resume or save")
                .font(.caption)
                .foregroundStyle(.orange)
        } else if session.allTranscribed {
            Label("All transcribed", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        } else if session.transcribedCount > 0 {
            Text("\(session.transcribedCount)/\(session.segmentCount) transcribed")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func formatDuration(_ interval: TimeInterval) -> String {
        let minutes = Int(interval) / 60
        return minutes < 60
            ? "\(minutes) min"
            : "\(minutes / 60) hr \(minutes % 60) min"
    }
}
