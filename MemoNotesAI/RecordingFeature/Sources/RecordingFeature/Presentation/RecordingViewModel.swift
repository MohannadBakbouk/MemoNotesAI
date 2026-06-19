import Foundation
import Observation

@MainActor
@Observable
public final class RecordingViewModel {
    // MARK: - State
    public var phase:            RecordingPhase = .idle
    public var audioLevel:       Float          = 0
    public var segmentCount:     Int            = 0
    public var transcribedCount: Int            = 0
    public var showResumePrompt: Bool           = false
    public var errorMessage:     String?
    public var elapsedSeconds:   Int            = 0
    public private(set) var activeSessionID: UUID?

    private var timerTask: Task<Void, Never>?
    private var elapsedAtPause: Int = 0

    // MARK: - Lifecycle callbacks (wired by AppDependencies)
    /// Called after a recording session is successfully created.
    public var onSessionStarted: (@MainActor (UUID) -> Void)?
    /// Called after a recording session fully stops (including error reset).
    public var onSessionStopped: (@MainActor () -> Void)?

    // MARK: - Dependencies
    private let startUseCase: StartRecordingUseCase
    private let stopUseCase:  StopRecordingUseCase
    private let audioService: any RecordingServiceProtocol

    // MARK: - Private
    private var waveformTask: Task<Void, Never>?

    public init(
        startUseCase: StartRecordingUseCase,
        stopUseCase:  StopRecordingUseCase,
        audioService: any RecordingServiceProtocol
    ) {
        self.startUseCase = startUseCase
        self.stopUseCase  = stopUseCase
        self.audioService = audioService
    }

    // MARK: - Recording actions

    public func startRecording() async {
        errorMessage = nil
        do {
            let id = try await startUseCase.execute()
            activeSessionID = id
            onSessionStarted?(id)
            phase = .recording
            startWaveformPolling()
            startTimer()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func stopRecording() async {
        guard let id = activeSessionID else { return }
        stopWaveformPolling()
        do {
            try await stopUseCase.execute(sessionID: id)
            resetState()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Resume after a phone-call interruption via the banner.
    public func resumeAfterPrompt() async {
        showResumePrompt = false
        do {
            try await audioService.resumeRecording()
            phase = .recording
            startWaveformPolling()
            resumeTimer()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// User chooses to save the partial session and close.
    public func saveAndClose() async {
        showResumePrompt = false
        await stopRecording()
    }

    /// Restore an existing session (recovery at app launch).
    public func setActiveSession(sessionID: UUID) {
        activeSessionID = sessionID
        onSessionStarted?(sessionID)
        phase = .recording
        startWaveformPolling()
        startTimer()
    }

    // MARK: - External updates from App layer

    public func updateSegmentCounts(total: Int, transcribed: Int) {
        segmentCount     = total
        transcribedCount = transcribed
    }

    public func handleInterruptionBegan() {
        stopWaveformPolling()
        pauseTimer()
        phase = .paused
        showResumePrompt = true
    }

    public func handleInterruptionResumed() {
        showResumePrompt = false
        phase = .recording
        startWaveformPolling()
        resumeTimer()
    }

    // MARK: - Waveform polling

    private func startWaveformPolling() {
        waveformTask?.cancel()
        waveformTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.audioLevel = await self.audioService.currentAudioLevel
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    private func stopWaveformPolling() {
        waveformTask?.cancel()
        waveformTask = nil
        audioLevel = 0
    }

    private func startTimer() {
        elapsedAtPause = 0
        elapsedSeconds = 0
        timerTask?.cancel()
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, !Task.isCancelled else { return }
                self.elapsedSeconds += 1
            }
        }
    }

    private func pauseTimer() {
        elapsedAtPause = elapsedSeconds
        timerTask?.cancel()
        timerTask = nil
    }

    private func resumeTimer() {
        timerTask?.cancel()
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, !Task.isCancelled else { return }
                self.elapsedSeconds += 1
            }
        }
    }

    private func stopTimer() {
        timerTask?.cancel()
        timerTask = nil
        elapsedSeconds = 0
        elapsedAtPause = 0
    }

    private func resetState() {
        onSessionStopped?()
        stopTimer()
        phase            = .idle
        audioLevel       = 0
        segmentCount     = 0
        transcribedCount = 0
        showResumePrompt = false
        activeSessionID  = nil
    }
}
