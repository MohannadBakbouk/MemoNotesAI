// AudioCore/Domain/UseCases/HandleAudioInterruptionUseCase.swift

import Foundation
import PersistenceCore

public final class HandleAudioInterruptionUseCase: @unchecked Sendable {
    private let recordingService: any AudioRecordingServiceProtocol
    private let sessionRepository: any SessionRepositoryProtocol
    private let sessionID: UUID

    public init(
        recordingService: any AudioRecordingServiceProtocol,
        sessionRepository: any SessionRepositoryProtocol,
        sessionID: UUID
    ) {
        self.recordingService = recordingService
        self.sessionRepository = sessionRepository
        self.sessionID = sessionID
    }

    @MainActor
    public func handleInterruptionBegan() async throws {
        await recordingService.pause()

        try await sessionRepository.updateRecordingState(
            id: sessionID,
            update: RecordingSessionStateUpdate(
                isRecording: true,
                interruptedAt: Date()
            )
        )
    }

    @MainActor
    public func handleInterruptionEnded(shouldResume: Bool) async throws {
        if shouldResume {
            try await resumeAfterInterruption()
            return
        }

        try await sessionRepository.updateRecordingState(
            id: sessionID,
            update: RecordingSessionStateUpdate(
                isRecording: true,
                needsManualResume: true
            )
        )
    }

    @MainActor
    public func resumeAfterInterruption() async throws {
        try AudioSessionConfigurator.configureForRecording()
        _ = try await recordingService.rolloverOnResume()
        try await recordingService.resume()

        try await sessionRepository.updateRecordingState(
            id: sessionID,
            update: RecordingSessionStateUpdate(
                isRecording: true,
                needsManualResume: false,
                clearInterruptedAt: true
            )
        )
    }
}
