import Foundation

/// Snapshot of what Spotify is doing right now, read via AppleScript.
struct SpotifySnapshot: Equatable {
    enum State: String { case playing, paused, stopped }

    let trackID: String
    let title: String
    let artist: String
    let album: String
    let durationSeconds: Double
    let positionSeconds: Double
    let state: State
    let artworkURL: URL?

    func with(position: Double, state: State? = nil) -> SpotifySnapshot {
        SpotifySnapshot(trackID: trackID, title: title, artist: artist, album: album, durationSeconds: durationSeconds,
                        positionSeconds: position, state: state ?? self.state, artworkURL: artworkURL)
    }

    /// Same song and state; the position may differ. Views only need a new status when this is false.
    func sameExceptPosition(_ o: SpotifySnapshot) -> Bool {
        trackID == o.trackID && title == o.title && artist == o.artist && album == o.album
            && durationSeconds == o.durationSeconds && state == o.state && artworkURL == o.artworkURL
    }
}

/// Playback actions Spotify's AppleScript dictionary supports. (It has no way to read the
/// play queue, so there's no "Next Up".)
enum PlaybackCommand {
    case playPause, next, previous

    var appleScript: String {
        switch self {
        case .playPause: "playpause"
        case .next: "next track"
        case .previous: "previous track"
        }
    }
}

enum SpotifyStatus: Equatable {
    case notRunning
    case stopped
    case active(SpotifySnapshot)
    case error(String)
}

/// Talks to the Spotify desktop app through its AppleScript dictionary.
/// Needs Automation permission (System Settings > Privacy & Security > Automation).
/// All AppleScript work happens on `queue`, so it is safe to share across tasks.
final class SpotifyBridge: @unchecked Sendable {
    private let queue = DispatchQueue(label: "LyricBubbles.spotify")

    private static let source = """
    if application "Spotify" is running then
        tell application "Spotify"
            if player state is stopped then return "STOPPED"
            set t to current track
            set out to (id of t) & linefeed & (name of t) & linefeed & (artist of t) & linefeed & (album of t)
            set out to out & linefeed & ((duration of t) as string) & linefeed & ((player position) as string)
            set out to out & linefeed & ((player state) as string) & linefeed & (artwork url of t)
            return out
        end tell
    else
        return "NOTRUNNING"
    end if
    """

    /// Just the playhead, as one Apple event, so its timing can be pinned down closely.
    private static let positionSource = """
    if application "Spotify" is running then
        tell application "Spotify" to return ((player position) as string)
    end if
    return ""
    """

    private lazy var script: NSAppleScript? = NSAppleScript(source: Self.source)
    private lazy var positionScript: NSAppleScript? = NSAppleScript(source: Self.positionSource)

    /// Sends a playback command through Spotify's AppleScript dictionary. Returns an error
    /// message when Spotify refused (or isn't running), or nil on success.
    func send(_ command: PlaybackCommand) async -> String? {
        await withCheckedContinuation { cont in
            queue.async {
                let source = """
                if application "Spotify" is running then
                    tell application "Spotify" to \(command.appleScript)
                end if
                """
                var errorInfo: NSDictionary?
                NSAppleScript(source: source)?.executeAndReturnError(&errorInfo)
                let message = errorInfo.map { $0[NSAppleScript.errorMessage] as? String ?? "Spotify didn't respond." }
                cont.resume(returning: message)
            }
        }
    }

    /// Reads Spotify's state. `sampledAt` is when the snapshot's position was true: the middle of
    /// a dedicated one-event position read, timed here on the AppleScript queue (not after the
    /// hop back to the main actor, which can be busy drawing).
    func poll() async -> (status: SpotifyStatus, sampledAt: Date) {
        await withCheckedContinuation { cont in
            queue.async {
                var t0 = Date()
                var status = self.runScript()
                var t1 = Date()
                if case .active(let s) = status, let pos = self.readPosition(&t0, &t1) {
                    status = .active(s.with(position: pos))
                }
                cont.resume(returning: (status, t0.addingTimeInterval(t1.timeIntervalSince(t0) / 2)))
            }
        }
    }

    private func readPosition(_ t0: inout Date, _ t1: inout Date) -> Double? {
        guard let positionScript else { return nil }
        var errorInfo: NSDictionary?
        let start = Date()
        let result = positionScript.executeAndReturnError(&errorInfo)
        let end = Date()
        guard errorInfo == nil, let text = result.stringValue,
              let pos = Double(text.replacingOccurrences(of: ",", with: ".")) else { return nil }
        (t0, t1) = (start, end)
        return pos
    }

    private func runScript() -> SpotifyStatus {
        guard let script else { return .error("Could not build AppleScript") }
        var errorInfo: NSDictionary?
        let result = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let code = errorInfo[NSAppleScript.errorNumber] as? Int ?? 0
            if code == -1743 {
                return .error("Allow LyricBubbles to control Spotify in System Settings > Privacy & Security > Automation.")
            }
            let msg = errorInfo[NSAppleScript.errorMessage] as? String ?? "AppleScript error \(code)"
            return .error(msg)
        }
        guard let text = result.stringValue else { return .error("Empty reply from Spotify") }
        if text == "NOTRUNNING" { return .notRunning }
        if text == "STOPPED" { return .stopped }

        let parts = text.components(separatedBy: "\n")
        guard parts.count >= 8 else { return .error("Unexpected reply from Spotify") }

        // AppleScript formats reals with the system locale, so "12,5" is possible.
        func number(_ s: String) -> Double { Double(s.replacingOccurrences(of: ",", with: ".")) ?? 0 }

        return .active(SpotifySnapshot(
            trackID: parts[0],
            title: parts[1],
            artist: parts[2],
            album: parts[3],
            durationSeconds: number(parts[4]) / 1000.0,
            positionSeconds: number(parts[5]),
            state: SpotifySnapshot.State(rawValue: parts[6]) ?? .paused,
            artworkURL: URL(string: parts[7])
        ))
    }
}
