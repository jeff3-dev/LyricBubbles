import AVFoundation
import AudioToolbox
import CoreAudio
import Foundation

// MARK: - Level meter (audio thread -> main thread)

/// Accumulates loudness and bass energy on the audio thread; the UI drains it once per frame.
final class LevelMeter: @unchecked Sendable {
    private let lock = NSLock()
    private var sumSquares: Float = 0
    private var bassSquares: Float = 0
    private var frames = 0
    private var lowpass: Float = 0
    private let alpha: Float = 1 - exp(-2 * .pi * 150 / 48_000)   // ~150 Hz one-pole low-pass

    func process(_ samples: UnsafePointer<Float>, count: Int) {
        guard count > 0 else { return }
        var s: Float = 0, b: Float = 0
        var lp = lowpass
        for i in 0..<count {
            let x = samples[i]
            s += x * x
            lp += alpha * (x - lp)
            b += lp * lp
        }
        lowpass = lp
        lock.lock()
        sumSquares += s
        bassSquares += b
        frames += count
        lock.unlock()
    }

    /// RMS loudness and bass since the last call, or nil if no audio arrived.
    func drain() -> (rms: Double, bass: Double)? {
        lock.lock()
        defer { sumSquares = 0; bassSquares = 0; frames = 0; lock.unlock() }
        guard frames > 0 else { return nil }
        return (Double((sumSquares / Float(frames)).squareRoot()), Double((bassSquares / Float(frames)).squareRoot()))
    }
}

// MARK: - System audio (Core Audio process tap, macOS 14.2+)

/// Taps everything the Mac is playing through a private aggregate device.
/// macOS asks once for System Audio Recording permission (NSAudioCaptureUsageDescription).
@available(macOS 14.2, *)
final class SystemAudioTap {
    struct Failure: Error, CustomStringConvertible {
        let step: String
        let status: OSStatus
        var description: String { "\(step) failed (\(status))" }
    }

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private let queue = DispatchQueue(label: "LyricBubbles.audiotap", qos: .userInteractive)

    func start(meter: LevelMeter) throws {
        let tap = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        tap.uuid = UUID()
        tap.name = "LyricBubbles"
        tap.isPrivate = true
        tap.muteBehavior = .unmuted
        var status = AudioHardwareCreateProcessTap(tap, &tapID)
        guard status == noErr else { throw Failure(step: "Creating the audio tap", status: status) }

        let outputUID = try Self.defaultOutputUID()
        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: "LyricBubbles Tap",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapDriftCompensationKey: true,
                                               kAudioSubTapUIDKey: tap.uuid.uuidString]],
        ]
        status = AudioHardwareCreateAggregateDevice(description as CFDictionary, &aggregateID)
        guard status == noErr else { stop(); throw Failure(step: "Creating the tap device", status: status) }

        status = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, queue) { _, input, _, _, _ in
            for buffer in UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input)) {
                guard let data = buffer.mData else { continue }
                meter.process(data.assumingMemoryBound(to: Float.self),
                              count: Int(buffer.mDataByteSize) / MemoryLayout<Float>.size)
            }
        }
        guard status == noErr else { stop(); throw Failure(step: "Reading the tap", status: status) }

        status = AudioDeviceStart(aggregateID, procID)
        guard status == noErr else { stop(); throw Failure(step: "Starting the tap", status: status) }
    }

    func stop() {
        if let procID {
            AudioDeviceStop(aggregateID, procID)
            AudioDeviceDestroyIOProcID(aggregateID, procID)
        }
        if aggregateID != kAudioObjectUnknown { AudioHardwareDestroyAggregateDevice(aggregateID) }
        if tapID != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tapID) }
        procID = nil
        aggregateID = AudioObjectID(kAudioObjectUnknown)
        tapID = AudioObjectID(kAudioObjectUnknown)
    }

    private static func defaultOutputUID() throws -> String {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultSystemOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        guard status == noErr else { throw Failure(step: "Finding the output device", status: status) }

        address.mSelector = kAudioDevicePropertyDeviceUID
        var uid: Unmanaged<CFString>?
        size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &uid)
        guard status == noErr, let uid else { throw Failure(step: "Reading the output device", status: status) }
        return uid.takeRetainedValue() as String
    }
}

// MARK: - Microphone

final class MicrophoneTap {
    private let engine = AVAudioEngine()

    func start(meter: LevelMeter) throws {
        let input = engine.inputNode
        input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buffer, _ in
            guard let channel = buffer.floatChannelData?[0] else { return }
            meter.process(channel, count: Int(buffer.frameLength))
        }
        try engine.start()
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }
}

// MARK: - Reactor

/// Turns raw audio into smooth 0...1 `level` and `beat` values for visuals.
@MainActor
final class AudioReactor: ObservableObject {
    enum Source: String, CaseIterable, Identifiable {
        case off, system, microphone
        var id: String { rawValue }
        var label: String {
            switch self {
            case .off: "Off"
            case .system: "System audio"
            case .microphone: "Microphone"
            }
        }
    }

    static let sourceKey = "audioSource"

    @Published private(set) var status = ""
    private(set) var source: Source = .off
    var isActive: Bool { source != .off }

    private let meter = LevelMeter()
    private var systemTap: AnyObject?          // SystemAudioTap (macOS 14.2+)
    private var micTap: MicrophoneTap?

    // Smoothing state, advanced once per frame in `sample`.
    private var lastSample = Date.distantPast
    private var rawRMS = 0.0, rawBass = 0.0
    private var env = 0.0, bassEnv = 0.0, bassAvg = 0.0, peak = 0.05
    private var beat = 0.0, lastBeat = Date.distantPast
    private var silentFor = 0.0
    private var cached = (level: 0.0, beat: 0.0)

    func setSource(_ new: Source) {
        guard new != source || (new != .off && systemTap == nil && micTap == nil) else { return }
        if #available(macOS 14.2, *) { (systemTap as? SystemAudioTap)?.stop() }
        systemTap = nil
        micTap?.stop(); micTap = nil
        source = new
        silentFor = 0
        switch new {
        case .off:
            status = ""
        case .system:
            guard #available(macOS 14.2, *) else {
                status = "System audio needs macOS 14.2 or later. Try Microphone instead."
                return
            }
            let tap = SystemAudioTap()
            do {
                try tap.start(meter: meter)
                systemTap = tap
                status = "Listening to system audio"
            } catch {
                status = "Couldn't tap system audio: \(error). Try Microphone instead."
            }
        case .microphone:
            Task {
                guard await AVCaptureDevice.requestAccess(for: .audio) else {
                    status = "Microphone access denied. Allow it in System Settings > Privacy & Security."
                    return
                }
                guard source == .microphone else { return }
                let tap = MicrophoneTap()
                do {
                    try tap.start(meter: meter)
                    micTap = tap
                    status = "Listening to the microphone"
                } catch {
                    status = "Couldn't start the microphone: \(error.localizedDescription)"
                }
            }
        }
    }

    /// Smoothed loudness (auto-gained to 0...1) and a beat pulse that jumps to 1 on kicks and decays.
    func sample(at date: Date) -> (level: Double, beat: Double) {
        guard isActive else { return (0, 0) }
        let dt = min(0.1, max(0, date.timeIntervalSince(lastSample)))
        guard dt > 0 else { return cached }
        lastSample = date

        if let fresh = meter.drain() { rawRMS = fresh.rms; rawBass = fresh.bass }
        func follow(_ value: inout Double, to target: Double, attack: Double, release: Double) {
            let tau = target > value ? attack : release
            value += (target - value) * (1 - exp(-dt / tau))
        }
        follow(&env, to: rawRMS, attack: 0.025, release: 0.22)
        follow(&bassEnv, to: rawBass, attack: 0.01, release: 0.12)
        follow(&bassAvg, to: rawBass, attack: 0.8, release: 0.8)

        peak = max(env, peak * exp(-dt / 6), 0.02)
        let level = pow(min(1, env / peak), 1.3)

        if bassEnv > bassAvg * 1.4, bassEnv > 0.01, date.timeIntervalSince(lastBeat) > 0.22 {
            beat = 1
            lastBeat = date
        }
        beat *= exp(-dt / 0.2)

        // Silence for a while usually means permission was not granted.
        silentFor = rawRMS < 1e-6 ? silentFor + dt : 0
        if source == .system, silentFor > 5, !status.hasPrefix("Hearing") {
            status = "Hearing silence. If music is playing, allow System Audio Recording for LyricBubbles in System Settings > Privacy & Security."
        } else if source == .system, silentFor == 0, status.hasPrefix("Hearing") {
            status = "Listening to system audio"
        }

        cached = (level, beat)
        return cached
    }
}
