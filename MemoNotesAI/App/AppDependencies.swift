import Foundation
import SwiftData
import SwiftUI
import PersistenceCore
import AudioCore
import TranscriptionCore
import NetworkCore
import SystemCore
import RecordingFeature
import SessionsFeature

// MARK: - AudioRecordingService → RecordingServiceProtocol adapter

extension AudioRecordingService: @retroactive RecordingServiceProtocol {
    public func startRecording(sessionID: UUID) async throws { try await start(sessionID: sessionID) }
    public func stopRecording()               async throws   { _ = try await stop() }
    public func pauseRecording()              async          { await pause() }
    public func resumeRecording()             async throws   { try await resume() }
}

// MARK: - Segment handler box (breaks circular dep: audioService ↔ pipeline)

private final class SegmentHandlerBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _handler: (@Sendable (ClosedSegmentInfo) -> Void)?

    func set(_ handler: @escaping @Sendable (ClosedSegmentInfo) -> Void) {
        lock.withLock { _handler = handler }
    }
    func call(with info: ClosedSegmentInfo) {
        lock.withLock { _handler }?(info)
    }
}

// MARK: - AppDependencies

@MainActor
final class AppDependencies {
    // MARK: Infrastructure
    let modelContainer:    ModelContainer
    private let fileStore:        FileStore
    private let sessionRepo:      SessionRepository
    private let segmentRepo:      SegmentRepository
    private let transcriptionRepo: TranscriptionRepository

    // MARK: Transcription
    private let groqService:        GroqTranscriptionService
    private let whisperKitService:  WhisperKitTranscriptionService
    private let deleteAudioUseCase: DeleteSegmentAudioUseCase
    private let transcribeUseCase:  TranscribeSegmentUseCase
    private let transcriptionQueue: TranscriptionQueue
    private let retryUseCase:       RetryFailedTranscriptionsUseCase
    let pipeline: TranscriptionPipeline

    // MARK: Audio
    let audioService: AudioRecordingService

    // MARK: System
    private let thermalMonitor: ThermalMonitor
    private let batteryMonitor: BatteryMonitor
    private let memoryMonitor:  MemoryPressureMonitor
    let bgTaskManager:          BackgroundTaskManager
    private let powerUseCase:   HandlePowerStateUseCase

    // MARK: Audio event handlers
    private let interruptionHandler:   AudioInterruptionHandler
    private let routeChangeHandler:    AudioRouteChangeHandler
    private let routeChangeUseCase:    HandleRouteChangeUseCase
    private var activeInterruptionUseCase: HandleAudioInterruptionUseCase?

    // MARK: Feature
    let recordingViewModel:   RecordingViewModel
    let sessionListViewModel: SessionListViewModel
    private let fetchSegmentsUseCase: FetchSegmentsUseCase

    // MARK: App-level use cases
    private let recoverUseCase: RecoverInterruptedSessionUseCase

    // MARK: - Init

    init() throws {
        // 1. Infrastructure
        modelContainer    = try SwiftDataStack.makeModelContainer()
        fileStore         = try FileStore()
        sessionRepo       = SessionRepository(container: modelContainer)
        segmentRepo       = SegmentRepository(container: modelContainer)
        transcriptionRepo = TranscriptionRepository(container: modelContainer)

        // 2. System monitors (needed by resolver below)
        thermalMonitor = ThermalMonitor()
        batteryMonitor = BatteryMonitor()
        memoryMonitor  = MemoryPressureMonitor()
        bgTaskManager  = BackgroundTaskManager()

        // 3. Transcription pipeline
        groqService       = GroqTranscriptionService()
        whisperKitService = WhisperKitTranscriptionService()
        deleteAudioUseCase = DeleteSegmentAudioUseCase(
            segmentRepo: segmentRepo,
            fileStore:   fileStore
        )
        transcribeUseCase = TranscribeSegmentUseCase(
            groqService:        groqService,
            whisperKitService:  whisperKitService,
            segmentRepo:        segmentRepo,
            transcriptionRepo:  transcriptionRepo,
            deleteAudioUseCase: deleteAudioUseCase,
            fileStore:          fileStore
        )
        transcriptionQueue = TranscriptionQueue(transcribeUseCase: transcribeUseCase)
        retryUseCase       = RetryFailedTranscriptionsUseCase(
            segmentRepo: segmentRepo,
            queue:       transcriptionQueue
        )
        pipeline = TranscriptionPipeline(
            queue:        transcriptionQueue,
            retryUseCase: retryUseCase,
            segmentRepo:  segmentRepo
        )

        // 4. AudioRecordingService — use a handler box to resolve the circular dep:
        //    audioService's segmentClosedHandler needs pipeline, but audioService
        //    must exist before pipeline can be fully wired.
        let handlerBox = SegmentHandlerBox()
        audioService = AudioRecordingService(
            fileStore:            fileStore,
            segmentClosedHandler: { info in Task { @MainActor in handlerBox.call(with: info) } }
        )
        // Now wire the box to the pipeline (both are alive at this point)
        let capturedPipeline = pipeline
        handlerBox.set { info in
            Task { @MainActor in capturedPipeline.segmentClosed(info) }
        }

        // 5. Power use case
        let capturedQueue = transcriptionQueue
        powerUseCase = HandlePowerStateUseCase { @MainActor event in
            switch event {
            case .pauseUploads:  capturedQueue.pause(until: nil)
            case .resumeUploads: capturedQueue.resume()
            default:             break
            }
        }

        // 6. Audio event handlers (wired below after self is fully initialised)
        interruptionHandler = AudioInterruptionHandler()
        routeChangeHandler  = AudioRouteChangeHandler()
        routeChangeUseCase  = HandleRouteChangeUseCase(recordingService: audioService)

        // 7. Feature ViewModels
        let startUC = StartRecordingUseCase(sessionRepo: sessionRepo, audioService: audioService)
        let stopUC  = StopRecordingUseCase(sessionRepo: sessionRepo,  audioService: audioService)
        recordingViewModel = RecordingViewModel(
            startUseCase: startUC,
            stopUseCase:  stopUC,
            audioService: audioService
        )

        let fetchSessionsUC  = FetchSessionsUseCase(sessionRepo: sessionRepo)
        let deleteSessionUC  = DeleteSessionUseCase(sessionRepo: sessionRepo, fileStore: fileStore)
        fetchSegmentsUseCase = FetchSegmentsUseCase(segmentRepo: segmentRepo)
        sessionListViewModel = SessionListViewModel(
            fetchUseCase:  fetchSessionsUC,
            deleteUseCase: deleteSessionUC,
            sessionStream: sessionRepo.observeChanges(),
            segmentStream: segmentRepo.observeAnyChange()
        )

        recoverUseCase = RecoverInterruptedSessionUseCase(sessionRepo: sessionRepo)

        // 7. Wire all callbacks (self is now fully initialised)
        setupCallbacks()
    }

    // MARK: - Callback wiring

    private func setupCallbacks() {
        // RecordingViewModel lifecycle → pipeline + per-session interruption handler
        recordingViewModel.onSessionStarted = { [weak self] sessionID in
            guard let self else { return }
            self.pipeline.activeSessionID = sessionID
            self.activeInterruptionUseCase = HandleAudioInterruptionUseCase(
                recordingService:  self.audioService,
                sessionRepository: self.sessionRepo,
                sessionID:         sessionID
            )
        }
        recordingViewModel.onSessionStopped = { [weak self] in
            self?.pipeline.activeSessionID     = nil
            self?.activeInterruptionUseCase    = nil
        }

        // Interruption began → pause audio + show banner
        interruptionHandler.onInterruptionBegan = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                try? await self.activeInterruptionUseCase?.handleInterruptionBegan()
                self.recordingViewModel.handleInterruptionBegan()
            }
        }

        // Interruption ended → auto-resume or leave banner visible
        interruptionHandler.onInterruptionEnded = { [weak self] shouldResume in
            Task { @MainActor [weak self] in
                guard let self else { return }
                try? await self.activeInterruptionUseCase?.handleInterruptionEnded(shouldResume: shouldResume)
                if shouldResume { self.recordingViewModel.handleInterruptionResumed() }
            }
        }

        // Route change → rebuild audio tap (segment boundary handled inside AudioRecordingService)
        routeChangeHandler.onRouteChanged = { [weak self] in
            Task { @MainActor [weak self] in
                try? await self?.routeChangeUseCase.execute()
            }
        }

        // Subscribe to monitor streams then start delivery.
        // Each Task runs on MainActor so HandlePowerStateUseCase (@MainActor) is
        // called without any extra wrapping.
        let capturedPower = powerUseCase
        let capturedThermal = thermalMonitor
        let capturedBattery = batteryMonitor
        let capturedMemory  = memoryMonitor

        Task { @MainActor in
            let stream = await capturedThermal.observeChanges()
            await capturedThermal.start()
            for await state in stream {
                capturedPower.handleThermalChange(state)
            }
        }

        Task { @MainActor in
            let stream = await capturedBattery.observeChanges()
            await capturedBattery.start()
            for await info in stream {
                capturedPower.handleBatteryChange(info)
            }
        }

        Task { @MainActor in
            let stream = await capturedMemory.observeChanges()
            await capturedMemory.start()
            for await level in stream {
                capturedPower.handleMemoryPressure(level)
            }
        }

        // Low Power Mode
        NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange,
            object:  nil,
            queue:   nil
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.powerUseCase.handleLowPowerModeChange(
                    isEnabled: ProcessInfo.processInfo.isLowPowerModeEnabled
                )
            }
        }

        interruptionHandler.startObserving()
        routeChangeHandler.startObserving()
    }

    // MARK: - Public helpers called by ContentView

    /// Resume a session that was interrupted when the app was killed.
    func resumeInterruptedSession(_ info: RecoveredSessionInfo) async {
        do {
            try await audioService.start(sessionID: info.sessionID)
            try await sessionRepo.updateRecordingState(
                id: info.sessionID,
                update: RecordingSessionStateUpdate(isRecording: true, clearInterruptedAt: true)
            )
            recordingViewModel.setActiveSession(sessionID: info.sessionID)
        } catch {
            recordingViewModel.errorMessage = error.localizedDescription
        }
    }

    /// Mark an interrupted session as finished without resuming audio.
    func finalizeInterruptedSession(_ info: RecoveredSessionInfo) async {
        try? await sessionRepo.updateRecordingState(
            id: info.sessionID,
            update: RecordingSessionStateUpdate(isRecording: false, clearInterruptedAt: true)
        )
    }

    /// Run at launch: retry transcriptions that failed in a previous session.
    func retryFailedTranscriptions() async {
        try? await pipeline.retryAllFailed()
    }

    /// Check whether an interrupted session exists.
    func checkForInterruptedSession() async -> RecoveredSessionInfo? {
        try? await recoverUseCase.execute()
    }

    /// Factory: create a detail ViewModel for the given session.
    func makeDetailViewModel(for session: SessionDisplayModel) -> SessionDetailViewModel {
        let vm = SessionDetailViewModel(
            session:      session,
            fetchUseCase: fetchSegmentsUseCase,
            changeStream: segmentRepo.observeChanges(sessionID: session.id)
        )
        let capturedQueue = transcriptionQueue
        vm.onRetryWithGroq = { segmentID, filePath in
            capturedQueue.enqueue(segmentID: segmentID, filePath: filePath, retryCount: 0, forcedProvider: .groq)
        }
        vm.onRetryWithWhisperKit = { segmentID, filePath in
            capturedQueue.enqueue(segmentID: segmentID, filePath: filePath, retryCount: 0, forcedProvider: .whisperkit)
        }
        return vm
    }
}
