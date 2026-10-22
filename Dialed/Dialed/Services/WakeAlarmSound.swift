//
//  WakeAlarmSound.swift
//  Dialed
//
//  The alarm's sound. "System" is the Clock-style default; the rest are
//  Dialed's own tones, synthesized once into Library/Sounds (where both
//  AlarmKit and notifications look for named sounds) so no audio assets
//  ship with the app. A "gentle start" version fades in over the first
//  20 seconds. Files stay under 30 s, the notification sound limit.
//

import Foundation
import AVFoundation

enum AlarmSound: String, Codable, CaseIterable, Identifiable {
    case system, classic, chime, sunrise, pulse, siren

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system:  return "System alarm"
        case .classic: return "Classic beeps"
        case .chime:   return "Chime"
        case .sunrise: return "Sunrise"
        case .pulse:   return "Pulse"
        case .siren:   return "Siren"
        }
    }

    /// Synthesized by Dialed (can fade in and be previewed).
    var isCustom: Bool { self != .system }
}

enum AlarmSoundLibrary {

    private static let version = 1
    private static let sampleRate = 22_050
    private static let seconds = 28.0
    private static let rampSeconds = 20.0

    /// Library/Sounds: AlarmKit and UNNotificationSound find named sounds here.
    private static var folder: URL {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0].appendingPathComponent("Sounds", isDirectory: true)
    }

    /// File name for `sound` (nil for the system sound).
    static func fileName(_ sound: AlarmSound, ramp: Bool) -> String? {
        guard sound.isCustom else { return nil }
        return "dialed-alarm-\(sound.rawValue)\(ramp ? "-rise" : "")-v\(version).wav"
    }

    static func url(_ sound: AlarmSound, ramp: Bool) -> URL? {
        fileName(sound, ramp: ramp).map { folder.appendingPathComponent($0) }
    }

    /// Makes sure the file exists and returns its name, or nil for the system
    /// sound or if it couldn't be written (callers then use the default).
    @discardableResult
    static func prepare(_ sound: AlarmSound, ramp: Bool) -> String? {
        guard let name = fileName(sound, ramp: ramp), let url = url(sound, ramp: ramp) else { return nil }
        if FileManager.default.fileExists(atPath: url.path) { return name }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try render(sound, ramp: ramp).write(to: url, options: .atomic)
            return name
        } catch {
            print("⚠️ [WakeAlarm] couldn't write sound: \(error.localizedDescription)")
            return nil
        }
    }

    /// `prepare` off the main thread (the first render of a sound takes a moment).
    static func prepared(_ sound: AlarmSound, ramp: Bool) async -> String? {
        guard sound.isCustom else { return nil }
        return await Task.detached(priority: .userInitiated) { AlarmSoundLibrary.prepare(sound, ramp: ramp) }.value
    }

    // MARK: - Synthesis

    /// 16-bit mono WAV.
    private static func render(_ sound: AlarmSound, ramp: Bool) -> Data {
        let count = Int(seconds * Double(sampleRate))
        var samples = [Int16](repeating: 0, count: count)
        var phase = 0.0
        let dt = 1.0 / Double(sampleRate)
        for i in 0..<count {
            let t = Double(i) * dt
            var v = sample(sound, t: t, dt: dt, phase: &phase)
            if ramp { v *= min(1, 0.12 + 0.88 * t / rampSeconds) }
            // Short fade at the very end so a loop doesn't click.
            v *= min(1, (seconds - t) / 0.05)
            samples[i] = Int16(max(-1, min(1, v * 0.85)) * Double(Int16.max))
        }
        return wav(samples)
    }

    /// 5 ms in and out so tones don't click.
    private static func gate(_ tau: Double, length: Double) -> Double {
        guard tau >= 0, tau <= length else { return 0 }
        return min(1, tau / 0.005, (length - tau) / 0.005)
    }

    private static func tone(_ f: Double, _ tau: Double) -> Double { sin(2 * .pi * f * tau) }

    private static func sample(_ sound: AlarmSound, t: Double, dt: Double, phase: inout Double) -> Double {
        switch sound {
        case .system:
            return 0
        case .classic:
            // Four quick beeps a second, a touch of square for bite.
            let c = t.truncatingRemainder(dividingBy: 1.0)
            let beep = c.truncatingRemainder(dividingBy: 0.2)
            guard c < 0.8 else { return 0 }
            let g = gate(beep, length: 0.12)
            return g * (0.8 * tone(1000, beep) + 0.2 * tone(3000, beep))
        case .chime:
            // C–E–G–C bells, each ringing out.
            let c = t.truncatingRemainder(dividingBy: 2.0)
            let notes: [(Double, Double)] = [(0.0, 1046.5), (0.3, 1318.5), (0.6, 1568.0), (0.9, 2093.0)]
            var v = 0.0
            for (start, f) in notes where c >= start {
                let tau = c - start
                v += min(1, tau / 0.004) * exp(-3.2 * tau) * (tone(f, tau) + 0.3 * tone(f * 2.01, tau))
            }
            return v * 0.45
        case .sunrise:
            // A soft rising arpeggio that swells.
            let c = t.truncatingRemainder(dividingBy: 2.4)
            let notes: [(Double, Double)] = [(0.0, 523.25), (0.4, 659.25), (0.8, 783.99), (1.2, 1046.5)]
            var v = 0.0
            for (start, f) in notes where c >= start && c < start + 1.1 {
                let tau = c - start
                v += sin(.pi * tau / 1.1) * tone(f, tau)
            }
            return v * 0.5
        case .pulse:
            // Low pulses with a wobble: hard to sleep through, not shrill.
            let c = t.truncatingRemainder(dividingBy: 0.75)
            let g = gate(c, length: 0.5)
            return g * (0.6 + 0.4 * sin(2 * .pi * 8 * c)) * (tone(520, c) + 0.35 * tone(1040, c))
        case .siren:
            // Up and down sweep; phase is integrated so the pitch glides.
            let c = t.truncatingRemainder(dividingBy: 1.8)
            let x = c < 0.9 ? c / 0.9 : (1.8 - c) / 0.9
            let f = 650 + 600 * x
            phase += 2 * .pi * f * dt
            if phase > 2 * .pi { phase -= 2 * .pi }
            return 0.8 * sin(phase)
        }
    }

    private static func wav(_ samples: [Int16]) -> Data {
        var data = Data()
        func put32(_ v: UInt32) { var x = v.littleEndian; withUnsafeBytes(of: &x) { data.append(contentsOf: $0) } }
        func put16(_ v: UInt16) { var x = v.littleEndian; withUnsafeBytes(of: &x) { data.append(contentsOf: $0) } }
        let bytes = UInt32(samples.count * 2)
        data.append(contentsOf: Array("RIFF".utf8)); put32(36 + bytes)
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8)); put32(16)
        put16(1)                                  // PCM
        put16(1)                                  // mono
        put32(UInt32(sampleRate))
        put32(UInt32(sampleRate * 2))             // byte rate
        put16(2)                                  // block align
        put16(16)                                 // bits
        data.append(contentsOf: Array("data".utf8)); put32(bytes)
        for s in samples { put16(UInt16(bitPattern: s)) }
        return data
    }
}

// MARK: - Preview

/// Plays a few seconds of a sound in the settings card.
@MainActor
final class AlarmSoundPreview: ObservableObject {
    @Published private(set) var playing: AlarmSound?
    private var player: AVAudioPlayer?
    private var stopTask: Task<Void, Never>?

    func toggle(_ sound: AlarmSound, ramp: Bool) {
        if playing == sound { stop() } else { play(sound, ramp: ramp) }
    }

    func play(_ sound: AlarmSound, ramp: Bool) {
        stop()
        playing = sound
        stopTask = Task { [weak self] in
            guard await AlarmSoundLibrary.prepared(sound, ramp: ramp) != nil,
                  !Task.isCancelled, let self else { return }
            self.start(sound, ramp: ramp)
        }
    }

    private func start(_ sound: AlarmSound, ramp: Bool) {
        guard let url = AlarmSoundLibrary.url(sound, ramp: ramp) else { playing = nil; return }
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        guard let player = try? AVAudioPlayer(contentsOf: url) else { playing = nil; return }
        player.volume = 0.8
        player.play()
        self.player = player
        playing = sound
        stopTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(ramp ? 8.0 : 5.0))
            guard !Task.isCancelled else { return }
            self?.stop()
        }
    }

    func stop() {
        stopTask?.cancel()
        stopTask = nil
        playing = nil
        guard player != nil else { return }
        player?.stop()
        player = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
