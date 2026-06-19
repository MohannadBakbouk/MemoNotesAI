import Foundation

public struct RecordingSessionStateUpdate: Sendable {
    public let isRecording: Bool
    public let duration: TimeInterval?
    public let interruptedAt: Date?
    public let needsManualResume: Bool?
    public let clearInterruptedAt: Bool

    public init(
        isRecording: Bool,
        duration: TimeInterval? = nil,
        interruptedAt: Date? = nil,
        needsManualResume: Bool? = nil,
        clearInterruptedAt: Bool = false
    ) {
        self.isRecording = isRecording
        self.duration = duration
        self.interruptedAt = interruptedAt
        self.needsManualResume = needsManualResume
        self.clearInterruptedAt = clearInterruptedAt
    }
}
