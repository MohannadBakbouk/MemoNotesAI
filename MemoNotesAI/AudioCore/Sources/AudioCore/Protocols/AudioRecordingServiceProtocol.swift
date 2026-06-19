// AudioCore/Protocols/AudioRecordingServiceProtocol.swift

import Foundation

public typealias SegmentClosedHandler = @Sendable (ClosedSegmentInfo) -> Void

public protocol AudioRecordingServiceProtocol: Sendable {
    var isRecording: Bool { get async }
    var isPaused: Bool { get async }
    var recordingState: RecordingState { get async }
    var currentAudioLevel: Float { get async }

    func start(sessionID: UUID) async throws
    func stop() async throws -> [ClosedSegmentInfo]
    func pause() async
    func resume() async throws
    func rolloverOnResume() async throws -> ClosedSegmentInfo?
    func rebuildTapAfterRouteChange() async throws -> ClosedSegmentInfo?
}
