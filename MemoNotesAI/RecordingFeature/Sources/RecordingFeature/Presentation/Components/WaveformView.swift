import SwiftUI

public struct WaveformView: View {
    public let level:    Float   // 0.0 – 1.0
    public let isActive: Bool

    private static let barCount:   Int     = 30
    private static let minHeight:  CGFloat = 4
    private static let maxHeight:  CGFloat = 48

    public init(level: Float, isActive: Bool) {
        self.level    = level
        self.isActive = isActive
    }

    public var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<Self.barCount, id: \.self) { index in
                Capsule()
                    .fill(barColor)
                    .frame(width: 3, height: barHeight(for: index))
                    .animation(
                        isActive
                            ? .easeInOut(duration: 0.15).delay(Double(index) * 0.008)
                            : .default,
                        value: level
                    )
            }
        }
        .frame(height: Self.maxHeight)
    }

    // Centre bars taller, edges taper — mirrors a real voice waveform envelope.
    private func barHeight(for index: Int) -> CGFloat {
        guard isActive else { return Self.minHeight }
        let centre   = Double(Self.barCount) / 2
        let distance = abs(Double(index) - centre) / centre
        let envelope = 1.0 - distance * 0.45
        let scaled   = Double(level) * envelope
        return Self.minHeight + CGFloat(scaled) * (Self.maxHeight - Self.minHeight)
    }

    private var barColor: Color {
        isActive ? .red.opacity(0.85) : .secondary.opacity(0.25)
    }
}
