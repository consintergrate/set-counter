import AVFoundation
import AudioToolbox

struct RestAlarmSettings {
    var sound: AlarmSound
    var volume: Float
    var vibrate: Bool
    var duration: TimeInterval

    static var saved: RestAlarmSettings {
        let defaults = UserDefaults.standard
        return RestAlarmSettings(
            sound: .current,
            volume: Float(defaults.object(forKey: "alarmVolume") as? Double ?? 0.8),
            vibrate: defaults.object(forKey: "vibrationOn") as? Bool ?? true,
            duration: TimeInterval(defaults.object(forKey: "alarmDuration") as? Int ?? 4)
        )
    }
}

/// Plays the in-app rest alarm. Activating a non-mixable audio session pauses
/// other apps' music; deactivating with `.notifyOthersOnDeactivation` lets it resume.
@MainActor
final class AlarmPlayer {
    static let shared = AlarmPlayer()

    private var player: AVAudioPlayer?
    private var vibrationTask: Task<Void, Never>?
    private var stopTask: Task<Void, Never>?
    private var cache: [AlarmSound: Data] = [:]

    func play(sound: AlarmSound, volume: Float, vibrate: Bool, duration: TimeInterval = 4, onFinish: (() -> Void)? = nil) {
        stop()

        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [])
        try? session.setActive(true)

        player = try? AVAudioPlayer(data: wav(for: sound))
        player?.volume = volume
        player?.numberOfLoops = -1
        player?.play()

        if vibrate {
            vibrationTask = Task {
                while !Task.isCancelled {
                    AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
                    try? await Task.sleep(for: .seconds(1))
                }
            }
        }

        stopTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            self?.stop()
            onFinish?()
        }
    }

    func preview(sound: AlarmSound, volume: Float) {
        play(sound: sound, volume: volume, vibrate: false, duration: 2)
    }

    func stop() {
        stopTask?.cancel()
        stopTask = nil
        vibrationTask?.cancel()
        vibrationTask = nil
        guard let player else { return }
        player.stop()
        self.player = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func wav(for sound: AlarmSound) -> Data {
        if let data = cache[sound] { return data }
        let data = Self.makeWAV(sound)
        cache[sound] = data
        return data
    }

    /// One loop of the alarm as 16-bit mono WAV, generated so no asset is needed.
    private static func makeWAV(_ sound: AlarmSound) -> Data {
        let sampleRate = 44_100
        var samples: [Int16] = []

        /// `decay` > 0 gives a struck-bell envelope instead of a flat beep.
        func tone(_ seconds: Double, frequencies: [Double], level: Double = 0.9, decay: Double = 0) {
            let count = Int(seconds * Double(sampleRate))
            let fade = 220.0
            for i in 0..<count {
                let t = Double(i) / Double(sampleRate)
                var envelope = min(1, Double(i) / fade, Double(count - i) / fade)
                if decay > 0 { envelope *= exp(-decay * t) }
                let wave = frequencies.reduce(0) { $0 + sin(2 * .pi * $1 * t) } / Double(frequencies.count)
                samples.append(Int16(wave * envelope * level * Double(Int16.max)))
            }
        }
        func silence(_ seconds: Double) {
            samples += Array(repeating: 0, count: Int(seconds * Double(sampleRate)))
        }

        switch sound {
        case .beeps:
            for _ in 0..<3 {
                tone(0.12, frequencies: [1760])
                silence(0.08)
            }
            silence(0.4)
        case .bell:
            tone(0.6, frequencies: [880, 1320, 2640], decay: 5)
            tone(0.6, frequencies: [660, 990, 1980], decay: 5)
            silence(0.2)
        case .soft:
            // Slow swell in and out so it doesn't startle.
            let count = Int(0.9 * Double(sampleRate))
            for i in 0..<count {
                let t = Double(i) / Double(sampleRate)
                let envelope = sin(.pi * Double(i) / Double(count))
                samples.append(Int16(sin(2 * .pi * 660 * t) * envelope * 0.7 * Double(Int16.max)))
            }
            silence(0.3)
        }

        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        let byteCount = UInt32(samples.count * 2)
        data.append(contentsOf: Array("RIFF".utf8))
        append(36 + byteCount)
        data.append(contentsOf: Array("WAVEfmt ".utf8))
        append(UInt32(16))                 // fmt chunk size
        append(UInt16(1))                  // PCM
        append(UInt16(1))                  // mono
        append(UInt32(sampleRate))
        append(UInt32(sampleRate * 2))     // byte rate
        append(UInt16(2))                  // block align
        append(UInt16(16))                 // bits per sample
        data.append(contentsOf: Array("data".utf8))
        append(byteCount)
        for sample in samples { append(sample) }
        return data
    }
}
