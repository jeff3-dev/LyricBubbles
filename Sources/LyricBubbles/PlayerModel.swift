import Foundation
import SwiftUI

/// Polls Spotify once a second and interpolates the playhead between polls (`PlayheadClock`),
/// so lyric timing stays smooth without hammering AppleScript.
@MainActor
final class PlayerModel: ObservableObject {
    /// Only reassigned when the song or play state changes, not on every poll, so windows
    /// don't rebuild their whole view tree once a second. Its `positionSeconds` is therefore
    /// stale; use `position(at:)`.
    @Published private(set) var status: SpotifyStatus = .notRunning
    @Published private(set) var lyrics: LyricsResult? = nil
    @Published private(set) var loadingLyrics = false
    @Published private(set) var cast = Cast(names: [], source: .single)
    @Published private(set) var artPalette: [Color] = []   // vivid colors from the album art
    /// Per-song timing fix in seconds (+ shows lyrics earlier), remembered by track ID.
    @Published private(set) var songNudge: Double = 0

    // Detector output before user overrides.
    private var baseLines: [LyricLine] = []
    private var baseCast = Cast(names: [], source: .single)

    private let bridge = SpotifyBridge()
    private let service = LyricsService()
    private var pollTask: Task<Void, Never>?
    private var lyricsTask: Task<Void, Never>?
    private var currentTrackID: String?
    private var clock = PlayheadClock()

    let audio = AudioReactor()

    var snapshot: SpotifySnapshot? {
        if case .active(let s) = status { return s }
        return nil
    }

    /// Song time at `date`, including this song's nudge (styles add the global lead time).
    func position(at date: Date = Date()) -> Double {
        clock.position(at: date) + songNudge
    }

    func start() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.tick()
                // Sleep about a second, or less when a playback button (or a doubtful reading) asked for a fresh read.
                for _ in 0..<20 {
                    if self?.pollSoon == true { break }
                    try? await Task.sleep(for: .milliseconds(50))
                }
                self?.pollSoon = false
            }
        }
    }

    private var pollSoon = false
    @Published private(set) var playbackError: String?

    /// Play/pause, next or previous in Spotify, then reads the new state right away.
    func control(_ command: PlaybackCommand) {
        // Flip the play state at once so the button answers the click before Spotify does.
        if command == .playPause, case .active(let s) = status {
            let flipped: SpotifySnapshot.State = s.state == .playing ? .paused : .playing
            let now = Date()
            let pos = clock.position(at: now)
            status = .active(s.with(position: pos, state: flipped))
            clock.jump(to: pos, at: now, playing: flipped == .playing)
        }
        Task {
            playbackError = await bridge.send(command)
            pollSoon = true
        }
    }

    private func tick() async {
        let (new, sampledAt) = await bridge.poll()

        if case .active(let s) = new {
            let newTrack = s.trackID != currentTrackID
            let doubtful = clock.ingest(position: s.positionSeconds, at: sampledAt,
                                        playing: s.state == .playing, forceJump: newTrack)
            if doubtful { pollSoon = true }
            if newTrack { trackChanged(s) }
        } else {
            clock.stop()
            if currentTrackID != nil {
                currentTrackID = nil
                lyricsTask?.cancel()
                lyrics = nil
                loadingLyrics = false
            }
        }
        if !Self.sameForViews(new, status) { status = new }
    }

    private static func sameForViews(_ a: SpotifyStatus, _ b: SpotifyStatus) -> Bool {
        if case .active(let x) = a, case .active(let y) = b { return x.sameExceptPosition(y) }
        return a == b
    }

    /// New song: reset per-song state and load its lyrics without holding up polling,
    /// so the playhead keeps being corrected while the lyrics download.
    private func trackChanged(_ s: SpotifySnapshot) {
        currentTrackID = s.trackID
        songNudge = SongNudges.load(s.trackID)
        threadCache = [:]
        artPalette = []
        if let url = s.artworkURL {
            Task { [weak self] in
                let colors = await ArtPalette.extract(from: url)
                if self?.currentTrackID == s.trackID { self?.artPalette = colors }
            }
        }
        lyrics = nil
        loadingLyrics = true
        lyricsTask?.cancel()
        lyricsTask = Task { [weak self, service] in
            let result = await service.lyrics(for: s)
            var detected: ([LyricLine], Cast)?
            if case .synced(let raw) = result {
                detected = await Task.detached(priority: .userInitiated) {
                    SingerDetector.detect(raw, artist: s.artist, title: s.title)
                }.value
            }
            guard let self, !Task.isCancelled, self.currentTrackID == s.trackID else { return }
            if let detected {
                (self.baseLines, self.baseCast) = detected
                self.rebuild()
            } else {
                self.baseLines = []
                self.cast = Cast(names: [s.artist], source: .single)
                self.lyrics = result
            }
            self.loadingLyrics = false
        }
    }

    // MARK: Per-song timing

    /// Shifts this song's lyrics; + shows them earlier. Remembered for the track.
    func nudgeSong(by delta: Double) {
        guard let id = currentTrackID else { return }
        songNudge = max(-5, min(5, ((songNudge + delta) * 100).rounded() / 100))
        SongNudges.save(id, songNudge)
    }

    func resetSongNudge() {
        guard let id = currentTrackID else { return }
        songNudge = 0
        SongNudges.save(id, 0)
    }


    // MARK: Singer fixes

    /// Reassigns every line in `section` to `singer` and remembers it for this track.
    func setSinger(_ singer: Int, forSection section: Int) {
        guard let id = currentTrackID else { return }
        var map = SingerOverrides.load(id)
        map[section] = singer
        SingerOverrides.save(id, map)
        rebuild()
    }

    func resetSingers() {
        guard let id = currentTrackID else { return }
        SingerOverrides.save(id, [:])
        rebuild()
    }

    // MARK: Chat thread

    /// Planned thread per style, built once per song (and again after singer fixes).
    private struct ThreadKey: Hashable { let style: BubbleSide; let intensity: Intensity }
    private var threadCache: [ThreadKey: ChatThread] = [:]

    func thread(style: BubbleSide, intensity: Intensity) -> ChatThread? {
        guard case .synced(let lines) = lyrics, let s = snapshot else { return nil }
        let key = ThreadKey(style: style, intensity: intensity)
        if let hit = threadCache[key] { return hit }
        if threadCache.count > 40 { threadCache = [:] }   // slider drags make many variants
        let t = ThreadPlanner.plan(lines: lines, trackID: s.trackID, title: s.title, artist: s.artist,
                                   duration: s.durationSeconds, style: style, cast: cast, intensity: intensity)
        threadCache[key] = t
        return t
    }

    private func rebuild() {
        threadCache = [:]
        guard let id = currentTrackID, !baseLines.isEmpty else { return }
        var lines = baseLines
        var c = baseCast
        SingerOverrides.apply(SingerOverrides.load(id), to: &lines, cast: &c)
        cast = c
        lyrics = .synced(lines)
    }
}
