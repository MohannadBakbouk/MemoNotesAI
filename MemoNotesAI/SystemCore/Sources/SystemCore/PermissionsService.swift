import AVFoundation

// MARK: - PermissionStatus

public enum PermissionStatus: Sendable, Equatable {
    case granted
    case denied
    case restricted
    case undetermined
}

// MARK: - PermissionsService

public enum PermissionsService {
    public static var microphoneStatus: PermissionStatus {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:       return .granted
        case .denied:        return .denied
        case .undetermined:  return .undetermined
        @unknown default:    return .undetermined
        }
    }

    public static func requestMicrophone() async -> PermissionStatus {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted ? .granted : .denied)
            }
        }
    }
}
