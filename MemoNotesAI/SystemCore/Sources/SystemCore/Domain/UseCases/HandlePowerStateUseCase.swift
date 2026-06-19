import Foundation

// MARK: - SystemPowerEvent

/// Actions fired by HandlePowerStateUseCase. App wires these to the relevant modules.
public enum SystemPowerEvent: Sendable, Equatable {
    case pauseUploads
    case resumeUploads
    case reduceAudioQuality
    case restoreAudioQuality
    case limitConcurrency(to: Int)
    case stopWaveformPolling
    case resumeWaveformPolling
    case lowBatteryWarning(level: Float)
}

// MARK: - HandlePowerStateUseCase

@MainActor
public final class HandlePowerStateUseCase {
    public typealias EventHandler = @MainActor @Sendable (SystemPowerEvent) -> Void

    private let onEvent: EventHandler
    private var lastThermal: ThermalState = .nominal
    private var lastMemory: MemoryPressureLevel = .normal
    private var uploadsPaused = false
    private var qualityReduced = false
    private var waveformStopped = false

    public init(onEvent: @escaping EventHandler) {
        self.onEvent = onEvent
    }

    // MARK: - Thermal

    public func handleThermalChange(_ state: ThermalState) {
        lastThermal = state
        syncUploadState()

        if state.requiresQualityReduction, !qualityReduced {
            qualityReduced = true
            onEvent(.reduceAudioQuality)
        } else if !state.requiresQualityReduction, qualityReduced {
            qualityReduced = false
            onEvent(.restoreAudioQuality)
        }
    }

    // MARK: - Battery

    public func handleBatteryChange(_ info: BatteryInfo) {
        if info.isLow {
            onEvent(.lowBatteryWarning(level: info.level))
        }
        if info.isCritical, !qualityReduced {
            qualityReduced = true
            onEvent(.reduceAudioQuality)
        }
    }

    // MARK: - Memory Pressure

    public func handleMemoryPressure(_ level: MemoryPressureLevel) {
        lastMemory = level
        syncUploadState()

        if level.shouldLimitConcurrency {
            onEvent(.limitConcurrency(to: 1))
        }

        if level.shouldStopWaveformPolling, !waveformStopped {
            waveformStopped = true
            onEvent(.stopWaveformPolling)
        } else if !level.shouldStopWaveformPolling, waveformStopped {
            waveformStopped = false
            onEvent(.resumeWaveformPolling)
        }
    }

    // MARK: - Low Power Mode

    public func handleLowPowerModeChange(isEnabled: Bool) {
        if isEnabled, !uploadsPaused {
            uploadsPaused = true
            onEvent(.pauseUploads)
        } else if !isEnabled {
            syncUploadState()
        }
    }

    // MARK: - Private

    private func syncUploadState() {
        let shouldPause = lastThermal.requiresUploadPause
            || lastMemory.shouldLimitConcurrency
            || ProcessInfo.processInfo.isLowPowerModeEnabled

        if shouldPause, !uploadsPaused {
            uploadsPaused = true
            onEvent(.pauseUploads)
        } else if !shouldPause, uploadsPaused {
            uploadsPaused = false
            onEvent(.resumeUploads)
        }
    }
}
