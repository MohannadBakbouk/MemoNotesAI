// AudioCore/Models/AudioCoreError.swift

import Foundation

public enum AudioCoreError: Error, Sendable, Equatable {
    case notRecording
    case alreadyRecording
    case engineNotPrepared
    case fileCreationFailed(String)
    case engineStartFailed(String)
    case invalidAudioFormat
    case writeFailed(String)
}
