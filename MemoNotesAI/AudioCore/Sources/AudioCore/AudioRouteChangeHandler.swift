// AudioCore/AudioRouteChangeHandler.swift

import AVFoundation
import Foundation

public final class AudioRouteChangeHandler: @unchecked Sendable {
    public var onRouteChanged: (@Sendable () -> Void)?

    private var isObserving = false

    public init() {}

    public func startObserving() {
        guard !isObserving else { return }
        isObserving = true

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteChange(_:)),
            name: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance()
        )
    }

    public func stopObserving() {
        guard isObserving else { return }
        isObserving = false
        NotificationCenter.default.removeObserver(
            self,
            name: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance()
        )
    }

    @objc
    private func handleRouteChange(_ notification: Notification) {
        guard
            let userInfo = notification.userInfo,
            let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
            let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue)
        else {
            return
        }

        switch reason {
        case .newDeviceAvailable,
             .oldDeviceUnavailable,
             .categoryChange,
             .override,
             .wakeFromSleep,
             .unknown:
            onRouteChanged?()
        default:
            break
        }
    }

    deinit {
        stopObserving()
    }
}
