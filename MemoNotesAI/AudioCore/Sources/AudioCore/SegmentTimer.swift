// AudioCore/SegmentTimer.swift

import Foundation

public final class SegmentTimer: @unchecked Sendable {
    public static let segmentDuration: TimeInterval = 30

    private let queue = DispatchQueue(label: "com.memonotesai.segment-timer", qos: .userInitiated)
    private var timer: DispatchSourceTimer?
    private var isPaused = false
    private var isRunning = false
    private let onFire: @Sendable () -> Void

    public init(onFire: @escaping @Sendable () -> Void) {
        self.onFire = onFire
    }

    public func start() {
        queue.async { [weak self] in
            guard let self else { return }
            self.timer?.cancel()
            self.isRunning = true
            self.isPaused = false

            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now() + Self.segmentDuration, repeating: Self.segmentDuration)
            timer.setEventHandler { [weak self] in
                guard let self, self.isRunning, !self.isPaused else { return }
                self.onFire()
            }
            timer.resume()
            self.timer = timer
        }
    }

    public func pause() {
        queue.async { [weak self] in
            self?.isPaused = true
        }
    }

    public func resume() {
        queue.async { [weak self] in
            guard let self, self.isRunning else { return }
            self.isPaused = false
        }
    }

    public func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.isRunning = false
            self.isPaused = false
            self.timer?.cancel()
            self.timer = nil
        }
    }
}
