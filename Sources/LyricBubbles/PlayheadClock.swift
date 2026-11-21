import Foundation

/// The song playhead between Spotify polls. Spotify is read about once a second; in between,
/// the position is extrapolated from the last trusted reading.
///
/// - Each reading carries the instant it was sampled (taken on the AppleScript queue, so a busy
///   main thread can't skew it).
/// - Small drift is absorbed by running the clock a few percent fast or slow, measured against
///   the median of the last few readings so one noisy reading can't steer it.
/// - A reading far from the prediction is either a seek or a glitch. It is only believed once a
///   second, quick re-read agrees; until then the clock keeps going as it was.
struct PlayheadClock {
    private(set) var anchorPosition: Double = 0
    private(set) var anchorDate = Date.distantPast
    private(set) var rate = 1.0
    private(set) var isPlaying = false

    /// Readings closer than this to the prediction are trusted and smoothed in.
    static let jumpThreshold = 0.35
    /// How quickly smoothed drift is corrected, and the most the clock may speed up or slow down.
    static let catchUp = 1.0
    static let maxRateNudge = 0.12

    /// `position - sampledAt` of recent trusted readings (the song's zero point in wall time).
    private var origins: [Double] = []
    /// A far-off reading waiting for a second one to confirm it.
    private var pending: (position: Double, at: Date)?

    func position(at date: Date) -> Double {
        isPlaying ? anchorPosition + date.timeIntervalSince(anchorDate) * rate : anchorPosition
    }

    /// Hard reset: new song, play/pause, or a confirmed seek.
    mutating func jump(to position: Double, at date: Date, playing: Bool) {
        anchorPosition = position
        anchorDate = date
        rate = 1
        isPlaying = playing
        origins = playing ? [position - date.timeIntervalSinceReferenceDate] : []
        pending = nil
    }

    /// Takes one reading. Returns true when the reading looked wrong and a quick re-read
    /// should confirm it.
    @discardableResult
    mutating func ingest(position measured: Double, at date: Date, playing: Bool, forceJump: Bool = false) -> Bool {
        if forceJump || playing != isPlaying || !playing {
            jump(to: measured, at: date, playing: playing)
            return false
        }
        let predicted = position(at: date)
        let drift = measured - predicted
        if abs(drift) > Self.jumpThreshold {
            // Believe it only if a second reading tells the same story.
            if let p = pending, abs((measured - p.position) - date.timeIntervalSince(p.at)) < Self.jumpThreshold {
                jump(to: measured, at: date, playing: true)
                return false
            }
            pending = (measured, date)
            return true
        }
        pending = nil
        origins.append(measured - date.timeIntervalSinceReferenceDate)
        if origins.count > 5 { origins.removeFirst(origins.count - 5) }
        let origin = origins.sorted()[origins.count / 2]
        let target = origin + date.timeIntervalSinceReferenceDate
        let smoothedDrift = target - predicted
        // Re-anchor at the prediction so the playhead never visibly jumps, then lean towards the target.
        anchorPosition = predicted
        anchorDate = date
        rate = abs(smoothedDrift) < 0.01 ? 1 : 1 + max(-Self.maxRateNudge, min(Self.maxRateNudge, smoothedDrift / Self.catchUp))
        return false
    }

    /// Stops extrapolating (Spotify quit or stopped).
    mutating func stop() {
        anchorPosition = position(at: Date())
        anchorDate = Date()
        isPlaying = false
        rate = 1
        origins = []
        pending = nil
    }
}

/// Per-song timing nudges (seconds, + = lyrics earlier), keyed by Spotify track ID.
/// LRCLIB timings sometimes come from a different release of a song, so one song can be off
/// while the rest are fine.
enum SongNudges {
    private static let key = "songTimingNudges"

    static func load(_ track: String) -> Double {
        (UserDefaults.standard.dictionary(forKey: key)?[track] as? Double) ?? 0
    }

    static func save(_ track: String, _ value: Double) {
        var all = UserDefaults.standard.dictionary(forKey: key) as? [String: Double] ?? [:]
        all[track] = abs(value) < 0.001 ? nil : value
        UserDefaults.standard.set(all, forKey: key)
    }
}
