import Foundation

struct LyricLine: Identifiable, Equatable {
    let id: Int
    let time: Double   // seconds from track start
    var text: String
    var singer: Int = 0     // index into Cast.names; Cast.everyone for "all singers"
    var section: Int = 0    // verse/chorus block, split on long pauses
}

enum LyricsResult: Equatable {
    case synced([LyricLine])
    case plainOnly
    case instrumental
    case notFound
}

/// Parses LRC text: "[mm:ss.xx] line". A line may carry several time tags.
enum LRCParser {
    private static let tag = try! NSRegularExpression(pattern: #"\[(\d+):(\d+(?:[.:]\d+)?)\]"#)

    static func parse(_ lrc: String) -> [LyricLine] {
        var entries: [(Double, String)] = []
        for raw in lrc.components(separatedBy: .newlines) {
            let ns = raw as NSString
            let matches = tag.matches(in: raw, range: NSRange(location: 0, length: ns.length))
            guard let last = matches.last else { continue }
            let text = ns.substring(from: last.range.location + last.range.length)
                .trimmingCharacters(in: .whitespaces)
            for m in matches {
                let min = Double(ns.substring(with: m.range(at: 1))) ?? 0
                let sec = Double(ns.substring(with: m.range(at: 2)).replacingOccurrences(of: ":", with: ".")) ?? 0
                entries.append((min * 60 + sec, text))
            }
        }
        return entries
            .sorted { $0.0 < $1.0 }
            .enumerated()
            .map { LyricLine(id: $0.offset, time: $0.element.0, text: $0.element.1) }
    }
}

/// Fetches time-synced lyrics from LRCLIB (https://lrclib.net), a free public LRC database.
actor LyricsService {
    private struct Record: Decodable {
        let duration: Double?
        let instrumental: Bool?
        let plainLyrics: String?
        let syncedLyrics: String?
    }

    private var cache: [String: LyricsResult] = [:]
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = ["User-Agent": "LyricBubbles/1.0"]
        config.timeoutIntervalForRequest = 10
        return URLSession(configuration: config)
    }()

    func lyrics(for s: SpotifySnapshot) async -> LyricsResult {
        if let hit = cache[s.trackID] { return hit }
        let result = await fetch(s)
        cache[s.trackID] = result
        return result
    }

    private func fetch(_ s: SpotifySnapshot) async -> LyricsResult {
        // 1. Exact match on title + artist + album + duration.
        if let rec: Record = await get("/api/get", [
            "track_name": s.title,
            "artist_name": s.artist,
            "album_name": s.album,
            "duration": String(Int(s.durationSeconds.rounded())),
        ]), let r = classify(rec) {
            return r
        }

        // 2. Fuzzy search; prefer synced results whose length is close to the track.
        let cleanTitle = Self.stripDecorations(s.title)
        guard let list: [Record] = await get("/api/search", [
            "track_name": cleanTitle,
            "artist_name": s.artist,
        ]), !list.isEmpty else { return .notFound }

        let ranked = list.sorted {
            abs(($0.duration ?? 0) - s.durationSeconds) < abs(($1.duration ?? 0) - s.durationSeconds)
        }
        if let best = ranked.first(where: { $0.syncedLyrics?.isEmpty == false
            && abs(($0.duration ?? 0) - s.durationSeconds) < 8 }) {
            return classify(best) ?? .notFound
        }
        return ranked.first.flatMap(classify) ?? .notFound
    }

    private func classify(_ r: Record) -> LyricsResult? {
        if r.instrumental == true { return .instrumental }
        if let synced = r.syncedLyrics, !synced.isEmpty {
            let lines = LRCParser.parse(synced)
            if !lines.isEmpty { return .synced(lines) }
        }
        if r.plainLyrics?.isEmpty == false { return .plainOnly }
        return nil
    }

    private func get<T: Decodable>(_ path: String, _ query: [String: String]) async -> T? {
        var comps = URLComponents(string: "https://lrclib.net")!
        comps.path = path
        comps.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = comps.url,
              let (data, resp) = try? await session.data(from: url),
              (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    /// "Song - Remastered 2011" / "Song (feat. X)" -> "Song"
    static func stripDecorations(_ title: String) -> String {
        var t = title
        if let r = t.range(of: " - ") { t = String(t[..<r.lowerBound]) }
        if let r = t.range(of: #"\s*[\(\[].*?(feat|with|remaster|version|edit|live).*?[\)\]]"#,
                           options: [.regularExpression, .caseInsensitive]) {
            t.removeSubrange(r)
        }
        return t.trimmingCharacters(in: .whitespaces)
    }
}
