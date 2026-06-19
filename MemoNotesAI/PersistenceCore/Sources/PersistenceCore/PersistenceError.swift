import Foundation

public enum PersistenceError: Error, Sendable, Equatable {
    case sessionNotFound
    case segmentNotFound
    case transcriptionMissing
    case invalidStateTransition(from: SegmentProcessingStatus, to: SegmentProcessingStatus)
    case saveFailed(String)
    case fileOperationFailed(String)
}
