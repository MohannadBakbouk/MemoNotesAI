// AudioCore/AudioSessionConfigurator.swift

import AVFoundation

public enum AudioSessionConfigurator {
    public static func configureForRecording() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playAndRecord,
            mode: .default,
            options: [.defaultToSpeaker, .allowBluetoothHFP]
        )
        try session.setActive(true, options: [])
    }
}
