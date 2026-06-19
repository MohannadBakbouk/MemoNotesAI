// AudioCore/SegmentWriter.swift

import AVFoundation
import Foundation
import os
import PersistenceCore

public final class SegmentWriter: @unchecked Sendable {
    public static let sampleRate: Double = 16_000
    public static let channelCount: AVAudioChannelCount = 1

    private let sessionID: UUID
    private let fileStore: FileStoreProtocol
    private let recordingFormat: AVAudioFormat
    private var fileLock = os_unfair_lock()

    private var currentFile: AVAudioFile?
    private var currentPath: String?
    private var currentSegmentIndex: Int
    private var currentSegmentStartTime: TimeInterval
    private var currentSegmentFrameCount: Int64
    private var totalSessionFrameCount: Int64

    public init(sessionID: UUID, fileStore: FileStoreProtocol) throws {
        self.sessionID = sessionID
        self.fileStore = fileStore
        self.currentSegmentIndex = 0
        self.currentSegmentStartTime = 0
        self.currentSegmentFrameCount = 0
        self.totalSessionFrameCount = 0

        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: Self.sampleRate,
            channels: Self.channelCount,
            interleaved: false
        ) else {
            throw AudioCoreError.invalidAudioFormat
        }
        self.recordingFormat = format

        try openNewSegment(at: 0, startTime: 0)
    }

    public var format: AVAudioFormat {
        recordingFormat
    }

    /// Real-time safe: writes to the active file without ever leaving `currentFile` nil during rollover.
    public func write(_ buffer: AVAudioPCMBuffer) {
        os_unfair_lock_lock(&fileLock)
        let file = currentFile
        os_unfair_lock_unlock(&fileLock)

        guard let file else {
            return
        }

        do {
            try file.write(from: buffer)
            os_unfair_lock_lock(&fileLock)
            currentSegmentFrameCount += Int64(buffer.frameLength)
            totalSessionFrameCount += Int64(buffer.frameLength)
            os_unfair_lock_unlock(&fileLock)
        } catch {
            // Real-time path: swallow write errors; coordinator handles storage failures separately.
        }
    }

    /// Option B double-buffer swap: create the new file first, swap, then finalize the closing file.
    public func rollover() throws -> ClosedSegmentInfo {
        let closingSnapshot = snapshotCurrentSegment()

        let nextIndex = closingSnapshot.index + 1
        let nextStartTime = Double(totalSessionFrameCount) / Self.sampleRate
        let newFile = try createFile(segmentIndex: nextIndex)
        let newPath = newFile.url.path

        os_unfair_lock_lock(&fileLock)
        let closingFile = currentFile
        currentFile = newFile
        currentPath = newPath
        currentSegmentIndex = nextIndex
        currentSegmentStartTime = nextStartTime
        currentSegmentFrameCount = 0
        os_unfair_lock_unlock(&fileLock)

        closingFile?.close()

        return ClosedSegmentInfo(
            path: closingSnapshot.path,
            segmentIndex: closingSnapshot.index,
            startTime: closingSnapshot.startTime,
            duration: closingSnapshot.duration,
            frameCount: closingSnapshot.frameCount
        )
    }

    public func rolloverOnResume() throws -> ClosedSegmentInfo {
        try rollover()
    }

    public func finalizeOpenSegment() throws -> ClosedSegmentInfo? {
        os_unfair_lock_lock(&fileLock)
        let snapshot = SegmentSnapshot(
            path: currentPath ?? "",
            index: currentSegmentIndex,
            startTime: currentSegmentStartTime,
            duration: Double(currentSegmentFrameCount) / Self.sampleRate,
            frameCount: currentSegmentFrameCount
        )
        let closingFile = currentFile
        currentFile = nil
        currentPath = nil
        os_unfair_lock_unlock(&fileLock)

        closingFile?.close()

        guard snapshot.frameCount > 0, !snapshot.path.isEmpty else {
            return nil
        }

        return ClosedSegmentInfo(
            path: snapshot.path,
            segmentIndex: snapshot.index,
            startTime: snapshot.startTime,
            duration: snapshot.duration,
            frameCount: snapshot.frameCount
        )
    }

    private struct SegmentSnapshot {
        let path: String
        let index: Int
        let startTime: TimeInterval
        let duration: TimeInterval
        let frameCount: Int64
    }

    private func snapshotCurrentSegment() -> SegmentSnapshot {
        os_unfair_lock_lock(&fileLock)
        defer { os_unfair_lock_unlock(&fileLock) }

        return SegmentSnapshot(
            path: currentPath ?? "",
            index: currentSegmentIndex,
            startTime: currentSegmentStartTime,
            duration: Double(currentSegmentFrameCount) / Self.sampleRate,
            frameCount: currentSegmentFrameCount
        )
    }

    private func openNewSegment(at index: Int, startTime: TimeInterval) throws {
        let file = try createFile(segmentIndex: index)
        os_unfair_lock_lock(&fileLock)
        currentFile = file
        currentPath = file.url.path
        currentSegmentIndex = index
        currentSegmentStartTime = startTime
        currentSegmentFrameCount = 0
        os_unfair_lock_unlock(&fileLock)
    }

    private func createFile(segmentIndex: Int) throws -> AVAudioFile {
        _ = try fileStore.sessionDirectory(for: sessionID)
        let url = fileStore.segmentFileURL(sessionID: sessionID, segmentIndex: segmentIndex)

        var settings = recordingFormat.settings
        settings[AVFormatIDKey] = kAudioFormatLinearPCM
        settings[AVLinearPCMIsBigEndianKey] = false
        settings[AVLinearPCMIsFloatKey] = false
        settings[AVLinearPCMBitDepthKey] = 16

        do {
            return try AVAudioFile(
                forWriting: url,
                settings: settings,
                commonFormat: .pcmFormatInt16,
                interleaved: false
            )
        } catch {
            throw AudioCoreError.fileCreationFailed(error.localizedDescription)
        }
    }
}

private extension AVAudioFile {
    func close() {
        // Releasing the file handle finalizes the .caf container.
    }
}
