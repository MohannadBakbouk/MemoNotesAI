// AudioCore/Models/RecordingState.swift

import Foundation

public enum RecordingState: Sendable, Equatable {
    case idle
    case recording
    case paused
}
