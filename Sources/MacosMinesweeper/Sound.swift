import AppKit

// Replacement for sound.c. The original plays the WAVE resources
// ID_SOUND_TICK / WIN / LOSE; here small retro sounds are synthesized once
// into in-memory WAV files and played with NSSound.

final class SoundPlayer {
    private let sampleRate = 22_050
    private lazy var tick = makeSound(tickSamples())
    private lazy var win = makeSound(winSamples())
    private lazy var lose = makeSound(loseSamples())

    func play(_ sound: GameSound) {
        let nsSound: NSSound?
        switch sound {
        case .tick: nsSound = tick
        case .win: nsSound = win
        case .lose: nsSound = lose
        }
        nsSound?.stop()
        nsSound?.play()
    }

    // MARK: - Synthesis

    private func tone(_ frequency: Double, seconds: Double, volume: Double, square: Bool = true) -> [Double] {
        let count = Int(Double(sampleRate) * seconds)
        return (0..<count).map { i in
            let t = Double(i) / Double(sampleRate)
            let phase = sin(2 * .pi * frequency * t)
            let wave = square ? (phase >= 0 ? 1.0 : -1.0) : phase
            let envelope = 1 - Double(i) / Double(count)
            return wave * volume * envelope
        }
    }

    private func tickSamples() -> [Double] {
        tone(1800, seconds: 0.015, volume: 0.25)
    }

    private func winSamples() -> [Double] {
        [523.25, 659.25, 783.99, 1046.5].flatMap { tone($0, seconds: 0.11, volume: 0.2) }
    }

    private func loseSamples() -> [Double] {
        let count = Int(Double(sampleRate) * 0.45)
        var level = 0.0
        return (0..<count).map { i in
            // Low-passed noise with a falling rumble: a small explosion
            level = level * 0.85 + Double.random(in: -1...1) * 0.15
            let t = Double(i) / Double(sampleRate)
            let rumble = sin(2 * .pi * (120 - 80 * t) * t)
            let envelope = pow(1 - Double(i) / Double(count), 2)
            return (level * 2.2 + rumble * 0.3) * 0.5 * envelope
        }
    }

    private func makeSound(_ samples: [Double]) -> NSSound? {
        var pcm = Data(capacity: samples.count * 2)
        for sample in samples {
            var value = Int16(max(-1, min(1, sample)) * Double(Int16.max)).littleEndian
            withUnsafeBytes(of: &value) { pcm.append(contentsOf: $0) }
        }

        var wav = Data()
        func append<T>(_ value: T) {
            var v = value
            withUnsafeBytes(of: &v) { wav.append(contentsOf: $0) }
        }
        wav.append(contentsOf: Array("RIFF".utf8))
        append(UInt32(36 + pcm.count).littleEndian)
        wav.append(contentsOf: Array("WAVEfmt ".utf8))
        append(UInt32(16).littleEndian)               // fmt chunk size
        append(UInt16(1).littleEndian)                // PCM
        append(UInt16(1).littleEndian)                // mono
        append(UInt32(sampleRate).littleEndian)
        append(UInt32(sampleRate * 2).littleEndian)   // byte rate
        append(UInt16(2).littleEndian)                // block align
        append(UInt16(16).littleEndian)               // bits per sample
        wav.append(contentsOf: Array("data".utf8))
        append(UInt32(pcm.count).littleEndian)
        wav.append(pcm)

        return NSSound(data: wav)
    }
}
