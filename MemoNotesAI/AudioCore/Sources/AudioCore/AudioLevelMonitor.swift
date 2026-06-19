// AudioCore/AudioLevelMonitor.swift

import AVFoundation
import os

public final class AudioLevelMonitor: @unchecked Sendable {
    private var lock = os_unfair_lock()
    private var level: Float = 0

    public init() {}

    public func update(with buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else {
            return
        }

        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else {
            return
        }

        var sum: Float = 0
        for index in 0..<frameCount {
            let sample = channelData[index]
            sum += sample * sample
        }

        let rootMeanSquare = sqrt(sum / Float(frameCount))
        let normalized = min(max(rootMeanSquare * 8, 0), 1)

        os_unfair_lock_lock(&lock)
        level = normalized
        os_unfair_lock_unlock(&lock)
    }

    public func updateFromInt16(with buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.int16ChannelData?[0] else {
            return
        }

        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else {
            return
        }

        var sum: Float = 0
        for index in 0..<frameCount {
            let sample = Float(channelData[index]) / Float(Int16.max)
            sum += sample * sample
        }

        let rootMeanSquare = sqrt(sum / Float(frameCount))
        let normalized = min(max(rootMeanSquare * 8, 0), 1)

        os_unfair_lock_lock(&lock)
        level = normalized
        os_unfair_lock_unlock(&lock)
    }

    public func currentLevel() -> Float {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return level
    }

    public func reset() {
        os_unfair_lock_lock(&lock)
        level = 0
        os_unfair_lock_unlock(&lock)
    }
}
