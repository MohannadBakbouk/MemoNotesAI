import Foundation

// Discrete phases the recording screen cares about.
public enum RecordingPhase: Sendable, Equatable {
    case idle
    case recording
    case paused
}

/// Minimal recording contract that RecordingFeature depends on.
/// App adapts AudioRecordingService to this protocol so the feature never imports AudioCore.
public protocol RecordingServiceProtocol: Sendable {
    var currentAudioLevel: Float { get async }
    var isRecording: Bool        { get async }
    var isPaused: Bool           { get async }

    func startRecording(sessionID: UUID) async throws
    func stopRecording()         async throws
    func pauseRecording()        async
    func resumeRecording()       async throws
}
