import SwiftUI

public struct RecordButton: View {
    public let phase:  RecordingPhase
    public let action: () -> Void

    public init(phase: RecordingPhase, action: @escaping () -> Void) {
        self.phase  = phase
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(tintColor)
                    .frame(width: 80, height: 80)
                    .shadow(color: tintColor.opacity(0.4), radius: 8, y: 4)

                phaseIcon
                    .foregroundStyle(.white)
                    .font(.system(size: 28, weight: .semibold))
            }
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.2), value: phase)
    }

    private var tintColor: Color {
        switch phase {
        case .idle:      .red
        case .recording: .red
        case .paused:    .orange
        }
    }

    @ViewBuilder
    private var phaseIcon: some View {
        switch phase {
        case .idle:
            Image(systemName: "mic.fill")
        case .recording:
            RoundedRectangle(cornerRadius: 4)
                .fill(.white)
                .frame(width: 26, height: 26)
        case .paused:
            Image(systemName: "play.fill")
        }
    }
}
