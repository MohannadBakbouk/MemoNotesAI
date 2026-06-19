// AudioCore/Domain/UseCases/HandleRouteChangeUseCase.swift

import Foundation
import PersistenceCore

public final class HandleRouteChangeUseCase: @unchecked Sendable {
    private let recordingService: any AudioRecordingServiceProtocol

    public init(recordingService: any AudioRecordingServiceProtocol) {
        self.recordingService = recordingService
    }

    /// rebuildTap(): remove tap → stop engine → close segment → re-read format → install tap → restart.
    @MainActor
    public func execute() async throws -> ClosedSegmentInfo? {
        try await recordingService.rebuildTapAfterRouteChange()
    }
}
