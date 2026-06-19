// AudioCore/AudioRecordingService.swift

import AVFoundation
import Foundation
import PersistenceCore

public final class AudioRecordingService: AudioRecordingServiceProtocol, @unchecked Sendable {
    private static let tapBufferSize: AVAudioFrameCount = 1024

    private let audioQueue = DispatchQueue(label: "com.memonotesai.audio-recording", qos: .userInitiated)
    private let engine = AVAudioEngine()
    private let fileStore: FileStoreProtocol
    private let segmentClosedHandler: SegmentClosedHandler
    private let levelMonitor = AudioLevelMonitor()

    private var state: RecordingState = .idle
    private var activeSessionID: UUID?
    private var segmentWriter: SegmentWriter?
    private var segmentTimer: SegmentTimer?
    private var converter: AVAudioConverter?
    private var tapInstalled = false

    public init(
        fileStore: FileStoreProtocol,
        segmentClosedHandler: @escaping SegmentClosedHandler
    ) {
        self.fileStore = fileStore
        self.segmentClosedHandler = segmentClosedHandler
    }

    public var isRecording: Bool {
        get async { await recordingState == .recording }
    }

    public var isPaused: Bool {
        get async { await recordingState == .paused }
    }

    public var recordingState: RecordingState {
        get async {
            await withCheckedContinuation { continuation in
                audioQueue.async {
                    continuation.resume(returning: self.state)
                }
            }
        }
    }

    public var currentAudioLevel: Float {
        get async { levelMonitor.currentLevel() }
    }

    public func start(sessionID: UUID) async throws {
        try await runOnAudioQueue {
            guard self.state == .idle else {
                throw AudioCoreError.alreadyRecording
            }

            try AudioSessionConfigurator.configureForRecording()

            let writer = try SegmentWriter(sessionID: sessionID, fileStore: self.fileStore)
            self.segmentWriter = writer
            self.activeSessionID = sessionID

            try self.installTap(using: writer)
            self.engine.prepare()

            do {
                try self.engine.start()
            } catch {
                throw AudioCoreError.engineStartFailed(error.localizedDescription)
            }

            let timer = SegmentTimer { [weak self] in
                self?.handleSegmentTimerFire()
            }
            timer.start()
            self.segmentTimer = timer
            self.state = .recording
        }
    }

    public func stop() async throws -> [ClosedSegmentInfo] {
        try await runOnAudioQueue {
            guard self.state == .recording || self.state == .paused else {
                throw AudioCoreError.notRecording
            }

            self.segmentTimer?.stop()
            self.segmentTimer = nil

            self.removeTapIfNeeded()
            self.engine.stop()

            var closedSegments: [ClosedSegmentInfo] = []
            if let writer = self.segmentWriter, let finalSegment = try writer.finalizeOpenSegment() {
                closedSegments.append(finalSegment)
                self.segmentClosedHandler(finalSegment)
            }

            self.segmentWriter = nil
            self.converter = nil
            self.activeSessionID = nil
            self.state = .idle
            self.levelMonitor.reset()

            return closedSegments
        }
    }

    public func pause() async {
        await runOnAudioQueue {
            guard self.state == .recording else { return }

            self.segmentTimer?.pause()
            self.engine.pause()
            self.state = .paused
        }
    }

    public func resume() async throws {
        try await runOnAudioQueue {
            guard self.state == .paused else { return }

            try AudioSessionConfigurator.configureForRecording()
            try self.engine.start()
            self.segmentTimer?.resume()
            self.state = .recording
        }
    }

    public func rolloverOnResume() async throws -> ClosedSegmentInfo? {
        try await runOnAudioQueue {
            guard self.state == .recording || self.state == .paused else {
                throw AudioCoreError.notRecording
            }

            return try self.performRollover(usingResumeBoundary: true)
        }
    }

    public func rebuildTapAfterRouteChange() async throws -> ClosedSegmentInfo? {
        try await runOnAudioQueue {
            guard self.state == .recording || self.state == .paused else {
                throw AudioCoreError.notRecording
            }

            let closedSegment = try self.performRollover(usingResumeBoundary: true)

            self.removeTapIfNeeded()
            self.engine.stop()

            try AudioSessionConfigurator.configureForRecording()

            guard let writer = self.segmentWriter else {
                throw AudioCoreError.engineNotPrepared
            }

            self.engine.prepare()
            try self.installTap(using: writer)

            if self.state == .recording {
                try self.engine.start()
            }

            return closedSegment
        }
    }

    private func handleSegmentTimerFire() {
        audioQueue.async { [weak self] in
            guard let self, self.state == .recording else { return }
            _ = try? self.performRollover(usingResumeBoundary: false)
        }
    }

    @discardableResult
    private func performRollover(usingResumeBoundary: Bool) throws -> ClosedSegmentInfo? {
        guard let writer = segmentWriter else { return nil }

        let closedSegment: ClosedSegmentInfo
        if usingResumeBoundary {
            closedSegment = try writer.rolloverOnResume()
        } else {
            closedSegment = try writer.rollover()
        }

        segmentClosedHandler(closedSegment)
        return closedSegment
    }

    private func installTap(using writer: SegmentWriter) throws {
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        let recordingFormat = writer.format

        removeTapIfNeeded()

        if formatsAreCompatible(inputFormat, recordingFormat) {
            converter = nil
            inputNode.installTap(
                onBus: 0,
                bufferSize: Self.tapBufferSize,
                format: recordingFormat
            ) { buffer, _ in
                writer.write(buffer)
                self.levelMonitor.updateFromInt16(with: buffer)
            }
        } else {
            guard let audioConverter = AVAudioConverter(from: inputFormat, to: recordingFormat) else {
                throw AudioCoreError.invalidAudioFormat
            }
            converter = audioConverter

            inputNode.installTap(
                onBus: 0,
                bufferSize: Self.tapBufferSize,
                format: inputFormat
            ) { [weak self] buffer, _ in
                guard let self else { return }
                guard let converted = self.convert(buffer, using: audioConverter, to: recordingFormat) else {
                    return
                }
                writer.write(converted)
                self.levelMonitor.updateFromInt16(with: converted)
            }
        }

        tapInstalled = true
    }

    private func removeTapIfNeeded() {
        guard tapInstalled else { return }
        engine.inputNode.removeTap(onBus: 0)
        tapInstalled = false
    }

    private func formatsAreCompatible(_ lhs: AVAudioFormat, _ rhs: AVAudioFormat) -> Bool {
        lhs.sampleRate == rhs.sampleRate
            && lhs.channelCount == rhs.channelCount
            && lhs.commonFormat == rhs.commonFormat
    }

    private func convert(
        _ buffer: AVAudioPCMBuffer,
        using converter: AVAudioConverter,
        to format: AVAudioFormat
    ) -> AVAudioPCMBuffer? {
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1
        guard let converted = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
            return nil
        }

        let inputState = ConverterInputState(buffer: buffer)
        var error: NSError?
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            if inputState.hasProvidedInput {
                outStatus.pointee = .noDataNow
                return nil
            }
            inputState.hasProvidedInput = true
            outStatus.pointee = .haveData
            return inputState.buffer
        }

        converter.convert(to: converted, error: &error, withInputFrom: inputBlock)
        if error != nil {
            return nil
        }
        return converted
    }

    private func runOnAudioQueue(_ work: @escaping @Sendable () throws -> Void) async throws {
        try await withCheckedThrowingContinuation { continuation in
            audioQueue.async {
                do {
                    try work()
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func runOnAudioQueue(_ work: @escaping @Sendable () -> Void) async {
        await withCheckedContinuation { continuation in
            audioQueue.async {
                work()
                continuation.resume()
            }
        }
    }

    private func runOnAudioQueue<T>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            audioQueue.async {
                do {
                    let value = try work()
                    continuation.resume(returning: value)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

private final class ConverterInputState: @unchecked Sendable {
    var hasProvidedInput = false
    let buffer: AVAudioPCMBuffer

    init(buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }
}
