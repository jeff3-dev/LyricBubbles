import Foundation

// MARK: - Strength

/// How much of each extra to add. 0 = off, 0.5 = "lively", 1 = maximum.
struct Intensity: Hashable {
    var emoji: Double
    var reactions: Double
    var bubble: Double
    var screen: Double
    var attachments: Double
    var banners: Double

    static let calm = Intensity(emoji: 0.35, reactions: 0.3, bubble: 0.35, screen: 0.3, attachments: 0.4, banners: 0.25)
    static let lively = Intensity(emoji: 0.5, reactions: 0.5, bubble: 0.5, screen: 0.5, attachments: 0.5, banners: 0.5)
    static let off = Intensity(emoji: 0, reactions: 0, bubble: 0, screen: 0, attachments: 0, banners: 0)
}

// MARK: - Thread model

enum Tapback: Equatable {
    case heart, thumbsUp, thumbsDown, haha, emphasize, question
    case emoji(String)

    var verb: String {
        switch self {
        case .heart: "Loved"
        case .thumbsUp: "Liked"
        case .thumbsDown: "Disliked"
        case .haha: "Laughed at"
        case .emphasize: "Emphasized"
        case .question: "Questioned"
        case .emoji(let e): "Reacted \(e) to"
        }
    }
}

/// iMessage-style bubble effects, played when the bubble arrives.
enum BubbleEffect: String, Equatable {
    case slam, loud, gentle
    var label: String { rawValue.capitalized }
}

/// Full-window effects, played over the whole thread.
enum ScreenEffect: String, Equatable, CaseIterable {
    case confetti, balloons, hearts, sparkles, fireworks
    var label: String { rawValue.capitalized }
}

enum Weather: String, Equatable, CaseIterable {
    case sunny, rain, storm, snow, night, windy, cloudy

    var symbol: String {
        switch self {
        case .sunny: "sun.max.fill"
        case .rain: "cloud.rain.fill"
        case .storm: "cloud.bolt.rain.fill"
        case .snow: "cloud.snow.fill"
        case .night: "moon.stars.fill"
        case .windy: "wind"
        case .cloudy: "cloud.fill"
        }
    }

    var label: String {
        switch self {
        case .sunny: "Sunny"
        case .rain: "Rain"
        case .storm: "Thunderstorms"
        case .snow: "Snow"
        case .night: "Clear"
        case .windy: "Windy"
        case .cloudy: "Cloudy"
        }
    }
}

/// Rich messages dropped into the thread between lyrics.
enum Attachment: Equatable {
    case liveLocation(place: String)
    case trip(place: String, minutes: Int)        // route with a moving dot and an arrival countdown
    case weather(place: String, kind: Weather, temp: Int)
    case voice(seconds: Int, seed: UInt64)
    case photo
    case event(title: String, when: String, place: String)
}

/// A verse turned into turn-by-turn navigation: each lyric line is a stop on the route.
struct RouteInfo: Equatable {
    struct Stop: Equatable {
        let time: Double
        let text: String
    }
    let stops: [Stop]
    let start: Double       // when the dot leaves the start point (card arrival)
    let place: String
    let minutes: Int        // ETA at the start of the trip
    let seed: UInt64
}

struct Sticker: Equatable {
    let emoji: String
    let angle: Double     // degrees
    let x: Double         // 0...1 across the bubble
    let at: Double        // song time it gets stuck on
}

struct Reaction: Equatable {
    let tapback: Tapback
    let at: Double      // song time the tapback pops in
    let byMe: Bool      // blue badge if "you" reacted, gray if the other side did
}

struct ChatItem: Identifiable, Equatable {
    enum Kind: Equatable {
        case lyric(String)
        case jumbo(String)              // emoji-only message, drawn big with no bubble
        case link                       // song preview card
        case attachment(Attachment)
        case route(RouteInfo)           // navigation card that carries a whole verse
    }

    let id: Int
    let time: Double
    var kind: Kind
    var outgoing: Bool
    var sender: Int                 // 0 = you / lead singer; others = contact or other singers
    var emoji: String? = nil        // appended to the lyric
    var reaction: Reaction? = nil
    var sticker: Sticker? = nil
    var bubbleEffect: BubbleEffect? = nil
    var screenEffect: ScreenEffect? = nil

    var isLyric: Bool { if case .lyric = kind { true } else { false } }
}

struct EffectCue: Equatable {
    let effect: ScreenEffect
    let at: Double
    let seed: UInt64
    static let duration = 3.6
}

struct Banner: Identifiable, Equatable {
    let id: Int
    let at: Double
    let title: String
    let body: String
    let showsArt: Bool
    static let duration = 3.8
}

/// While a map is live the chat zooms onto it. `end` is always before the next event,
/// so the zoom-out finishes before anything else appears.
struct FocusWindow: Equatable {
    let id: Int          // ChatItem id of the map card
    let start: Double
    let end: Double

    static let zoomIn = 0.8
    static let zoomOut = 0.75

    /// 0 = normal view, 1 = fully focused. Eased in and out.
    func amount(at pos: Double) -> Double {
        let t = min((pos - start) / Self.zoomIn, (end - pos) / Self.zoomOut)
        if t <= 0 { return 0 }
        if t >= 1 { return 1 }
        return 0.5 - 0.5 * cos(.pi * t)
    }
}

struct ChatThread: Equatable {
    var items: [ChatItem]
    var cues: [EffectCue]
    var banners: [Banner]
    var focus: [FocusWindow] = []
}

// MARK: - Deterministic randomness

/// SplitMix64 seeded from a string, so a song gets the same flair every time it plays.
struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64

    init(_ seed: String) {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for b in seed.utf8 { h ^= UInt64(b); h &*= 0x100_0000_01b3 }
        state = h
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Always draws one number, so changing a slider doesn't reshuffle everything else.
    mutating func chance(_ p: Double) -> Bool { Double.random(in: 0..<1, using: &self) < p }
    mutating func pick<T>(_ a: [T]) -> T { a[Int.random(in: 0..<a.count, using: &self)] }
    mutating func range(_ r: ClosedRange<Double>) -> Double { Double.random(in: r, using: &self) }
}

// MARK: - Keywords

enum EmojiMap {
    static let table: [(Set<String>, [String])] = [
        (["love", "loved", "loving", "lover"], ["❤️", "😍", "🥰"]),
        (["heart", "hearts"], ["❤️", "💘", "❤️‍🩹"]),
        (["kiss", "kisses", "kissed", "lips"], ["😘", "💋"]),
        (["fire", "burn", "burning", "flame", "flames", "hot"], ["🔥"]),
        (["cry", "crying", "cried", "tears", "tear"], ["😭", "💧"]),
        (["night", "tonight", "moon", "midnight"], ["🌙", "🌃"]),
        (["star", "stars"], ["⭐️", "✨"]),
        (["sun", "sunshine", "summer"], ["☀️", "😎"]),
        (["rain", "raining", "storm"], ["🌧️", "⛈️"]),
        (["dance", "dancing", "dancin"], ["💃", "🕺"]),
        (["party", "celebrate"], ["🎉", "🥳"]),
        (["drink", "drinking", "whiskey", "beer", "wine", "drunk", "bar"], ["🥃", "🍻", "🍷"]),
        (["money", "cash", "rich", "dollar", "dollars"], ["💸", "💰"]),
        (["car", "drive", "driving", "road", "highway", "truck"], ["🚗", "🛣️"]),
        (["home", "house"], ["🏡"]),
        (["phone", "call", "calling", "text"], ["📱"]),
        (["sky", "fly", "flying", "wings"], ["🕊️", "☁️"]),
        (["ocean", "sea", "wave", "waves", "beach"], ["🌊", "🏖️"]),
        (["goodbye", "leave", "leaving", "gone"], ["👋", "🥀"]),
        (["remember", "memory", "memories"], ["💭", "📸"]),
        (["forever", "time", "clock"], ["⏳", "♾️"]),
        (["god", "heaven", "pray", "angel"], ["🙏", "😇"]),
        (["devil", "hell", "sin"], ["😈"]),
        (["smile", "happy", "laugh", "laughing"], ["😊", "😂"]),
        (["sad", "lonely", "alone"], ["🥺", "💔"]),
        (["broken", "break", "breaking"], ["💔"]),
        (["baby", "babe"], ["🥹", "💕"]),
        (["gold", "golden", "diamond", "diamonds"], ["✨", "💎"]),
        (["cold", "ice", "snow", "winter"], ["🥶", "❄️"]),
        (["music", "song", "sing", "singing", "radio"], ["🎶", "🎤"]),
        (["eyes", "watch", "look", "looking"], ["👀"]),
        (["run", "running", "runnin"], ["🏃"]),
        (["wild", "crazy", "insane"], ["🤪", "🤯"]),
        (["yeah", "yes"], ["🙌", "💯"]),
    ]

    static let mood = ["🎶", "🔥", "😭", "🙌", "✨", "💯", "😮‍💨", "🫶", "🥹", "👀"]
    static let stickers = ["🔥", "💯", "😭", "❤️", "✨", "🥹", "🎶", "👀", "🤠", "😎", "🌟", "🫶"]

    static let love: Set<String> = ["love", "loved", "loving", "lover", "heart", "hearts", "kiss", "kisses"]
    static let night: Set<String> = ["night", "tonight", "star", "stars", "moon", "sky", "dream", "dreams", "shine", "light", "lights"]
    static let party: Set<String> = ["fire", "party", "celebrate", "explode", "boom", "fireworks", "wild"]
    static let laugh: Set<String> = ["ha", "haha", "laugh", "laughing", "funny", "joke"]
    static let sad: Set<String> = ["cry", "crying", "cried", "tears", "sad", "lonely", "broken"]

    static let travel: Set<String> = ["drive", "driving", "road", "highway", "truck", "car", "ride", "riding", "miles", "town", "city", "home", "way", "street", "train"]
    static let event: Set<String> = ["tonight", "tomorrow", "weekend", "friday", "saturday", "sunday", "monday", "date", "dinner", "wedding", "party", "show"]
    static let voice: Set<String> = ["sing", "singing", "voice", "call", "calling", "hear", "listen", "talk", "talking", "say", "said", "radio"]
    static let photo: Set<String> = ["picture", "pictures", "photo", "photograph", "polaroid", "camera", "smile", "remember", "memories"]

    static let weather: [(Set<String>, Weather)] = [
        (["thunder", "lightning", "storm", "storms", "hurricane"], .storm),
        (["rain", "raining", "rainy", "drizzle"], .rain),
        (["snow", "snowing", "winter", "freezing", "ice"], .snow),
        (["sun", "sunny", "sunshine", "summer", "heat"], .sunny),
        (["wind", "windy", "breeze", "blowing"], .windy),
        (["cloud", "clouds", "cloudy", "gray", "grey"], .cloudy),
        (["moon", "moonlight", "midnight", "stars"], .night),
    ]

    static func tokens(_ text: String) -> Set<String> {
        Set(text.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init))
    }

    static func candidates(_ tokens: Set<String>) -> [String] {
        table.filter { !$0.0.isDisjoint(with: tokens) }.flatMap(\.1)
    }

    static func weather(_ tokens: Set<String>) -> Weather? {
        weather.first { !$0.0.isDisjoint(with: tokens) }?.1
    }
}

/// Place names that show up in songs. Matched as whole words, longest first.
enum Places {
    static let names: [String] = [
        "New York", "Los Angeles", "San Francisco", "New Orleans", "Las Vegas", "Kansas City", "St. Louis",
        "Nashville", "Memphis", "Austin", "Dallas", "Houston", "Atlanta", "Chicago", "Detroit", "Brooklyn",
        "Manhattan", "Hollywood", "Vegas", "Miami", "Seattle", "Denver", "Boston", "Philadelphia", "Phoenix",
        "Malibu", "Tulsa", "Paris", "London", "Tokyo", "Rome", "Berlin", "Toronto", "Dublin", "Amsterdam",
        "Barcelona", "Sydney", "Mexico", "California", "Texas", "Tennessee", "Carolina", "Alabama", "Kentucky",
        "Montana", "Colorado", "Arizona", "Florida", "Ohio", "Michigan", "Mississippi", "Louisiana", "Virginia",
        "Oregon", "Hawaii", "Alaska", "Nevada", "Utah", "Idaho", "Wyoming", "Dakota", "Arkansas", "Missouri",
        "Oklahoma", "Iowa", "Maine", "Vermont", "Georgia", "Jersey", "Harlem", "Compton", "Venice",
    ]

    static let fallback = ["Nashville, TN", "Austin, TX", "Los Angeles, CA", "Brooklyn, NY", "Denver, CO", "Chicago, IL"]

    private static let patterns: [(String, NSRegularExpression)] = names
        .sorted { $0.count > $1.count }
        .map { ($0, try! NSRegularExpression(pattern: "\\b" + NSRegularExpression.escapedPattern(for: $0) + "\\b",
                                              options: .caseInsensitive)) }

    static func find(in text: String) -> String? {
        let range = NSRange(location: 0, length: (text as NSString).length)
        return patterns.first { $0.1.firstMatch(in: text, range: range) != nil }?.0
    }
}

// MARK: - Planner

/// Turns timed lyric lines into a full chat thread: who sends each line,
/// plus emojis, tapbacks, stickers, effects, attachments and notification banners.
enum ThreadPlanner {
    static func plan(lines: [LyricLine], trackID: String, title: String, artist: String,
                     duration: Double, style: BubbleSide, cast: Cast,
                     intensity k: Intensity = .lively) -> ChatThread {
        // Strength 0.5 = the base rates below; 1.0 doubles them.
        let mE = k.emoji * 2, mR = k.reactions * 2, mB = k.bubble * 2
        let mS = k.screen * 2, mA = k.attachments * 2, mN = k.banners * 2
        func cooldown(_ base: Double, _ m: Double) -> Double { base / max(m, 0.25) }

        var rng = SeededRNG(trackID)
        var sideRNG = SeededRNG(trackID + "/sides")
        var attachRNG = SeededRNG(trackID + "/attach")
        let words = lines.filter { !$0.text.isEmpty }
        let group = style == .group && cast.isMulti
        let contact = group ? cast.name(cast.names.count > 1 ? 1 : 0) : artist

        // Chorus starts: first line of a block whose lines repeat elsewhere in the song.
        var occurrences: [String: Int] = [:]
        for w in words { occurrences[SingerDetector.norm(w.text), default: 0] += 1 }
        var chorusStarts = Set<Int>()
        for i in words.indices where i == 0 || words[i].section != words[i - 1].section {
            if (occurrences[SingerDetector.norm(words[i].text)] ?? 0) > 1 { chorusStarts.insert(i) }
        }

        // Who sends each line.
        var sides: [(out: Bool, sender: Int)] = []
        switch style {
        case .incoming:
            sides = words.map { _ in (false, 1) }
        case .outgoing:
            sides = words.map { _ in (true, 0) }
        case .group where group:
            sides = words.map { ($0.singer == 0, $0.singer) }
        case .group:
            sides = words.map { _ in (false, 1) }
        case .alternate:
            // Runs of 1-3 lines per side, and a new block always flips sides.
            var out = false
            var run = 0
            var target = runLength(&sideRNG)
            var lastSection = words.first?.section ?? 0
            for w in words {
                if run >= target || w.section != lastSection {
                    out.toggle()
                    run = 0
                    target = runLength(&sideRNG)
                }
                run += 1
                lastSection = w.section
                sides.append((out, out ? 0 : 1))
            }
        }

        func reply(to item: ChatItem) -> (Bool, Int) {
            switch style {
            case .alternate: return item.outgoing ? (false, 1) : (true, 0)
            case .outgoing: return (true, 0)
            default: return (false, 1)
            }
        }

        var items: [ChatItem] = [ChatItem(id: 900_000, time: 0.3, kind: .link, outgoing: true, sender: 0)]
        var cues: [EffectCue] = []
        var lastReaction = -100.0
        var lastSticker = -100.0
        var lastBubbleFX = -100.0
        var lastScreenFX = -100.0
        var seenChorus = false

        for (i, w) in words.enumerated() {
            var item = ChatItem(id: w.id, time: w.time, kind: .lyric(w.text),
                                outgoing: sides[i].out, sender: sides[i].sender)
            let tokens = EmojiMap.tokens(w.text)
            let letters = w.text.filter(\.isLetter)
            let shouting = letters.count >= 4 && letters.allSatisfy(\.isUppercase)
            let firstChorus = chorusStarts.contains(i) && !seenChorus

            let options = EmojiMap.candidates(tokens)
            if rng.chance(0.45 * mE) && !options.isEmpty { item.emoji = rng.pick(options) }

            if w.time - lastBubbleFX > cooldown(10, mB) {
                var fx: BubbleEffect?
                let strong = rng.chance(mB)   // gates the always-on triggers by strength
                if (shouting || firstChorus) && strong { fx = .slam }
                else if w.text.hasSuffix("!") && rng.chance(0.6 * mB) { fx = .loud }
                else if w.text.hasPrefix("(") && w.text.hasSuffix(")") && strong { fx = .gentle }
                else if rng.chance(0.05 * mB) { fx = rng.pick([.loud, .gentle]) }
                if let fx { item.bubbleEffect = fx; lastBubbleFX = w.time }
            }

            if w.time - lastScreenFX > cooldown(22, mS) {
                var sfx: ScreenEffect?
                if firstChorus && rng.chance(mS) { sfx = rng.pick([.confetti, .balloons, .fireworks]) }
                else if !tokens.isDisjoint(with: EmojiMap.love) && rng.chance(0.5 * mS) { sfx = .hearts }
                else if !tokens.isDisjoint(with: EmojiMap.night) && rng.chance(0.4 * mS) { sfx = .sparkles }
                else if !tokens.isDisjoint(with: EmojiMap.party) && rng.chance(0.5 * mS) { sfx = .fireworks }
                if let sfx {
                    item.screenEffect = sfx
                    cues.append(EffectCue(effect: sfx, at: w.time, seed: rng.next()))
                    lastScreenFX = w.time
                }
            }
            if chorusStarts.contains(i) { seenChorus = true }

            if w.time - lastReaction > cooldown(5, mR) {
                var p = 0.2
                var tb: Tapback?
                if !tokens.isDisjoint(with: EmojiMap.love) { tb = .heart; p = 0.5 }
                else if w.text.contains("?") { tb = .question; p = 0.45 }
                else if !tokens.isDisjoint(with: EmojiMap.laugh) { tb = .haha; p = 0.5 }
                else if shouting || chorusStarts.contains(i) { tb = .emphasize; p = 0.5 }
                else if !tokens.isDisjoint(with: EmojiMap.sad) { tb = .emoji(rng.pick(["😭", "🥺"])); p = 0.35 }
                if rng.chance(p * mR) {
                    let pick = tb ?? randomTapback(&rng, options: options)
                    item.reaction = Reaction(tapback: pick, at: w.time + rng.range(0.9...2.4), byMe: !item.outgoing)
                    lastReaction = w.time
                }
            }

            // Stickers: an emoji slapped onto a bubble at an angle, a bit after it lands.
            if item.reaction == nil, w.time - lastSticker > cooldown(18, mR), rng.chance(0.08 * mR) {
                item.sticker = Sticker(emoji: options.isEmpty ? rng.pick(EmojiMap.stickers) : rng.pick(options),
                                       angle: rng.range(-28...28), x: rng.range(0.55...0.95),
                                       at: w.time + rng.range(1.2...2.6))
                lastSticker = w.time
            }
            items.append(item)
        }

        // Lyric routes: a verse becomes a navigation card whose turns are the lines.
        var routeWindows: [ClosedRange<Double>] = []
        if k.attachments > 0, !words.isEmpty {
            let want = k.attachments >= 0.75 ? 2 : 1
            let blocks = Dictionary(grouping: words.indices, by: { words[$0].section })
                .values.map { $0.sorted() }
                .sorted { $0[0] < $1[0] }
            var scored: [(score: Double, idx: [Int])] = []
            for (b, block) in blocks.enumerated() where block.count >= 3 {
                let idx = Array(block.prefix(7))
                let text = idx.map { words[$0].text }.joined(separator: " ")
                let tokens = EmojiMap.tokens(text)
                var score = attachRNG.range(0...1)
                if !tokens.isDisjoint(with: EmojiMap.travel) { score += 2 }
                if Places.find(in: text) != nil { score += 2 }
                if !idx.contains(where: { chorusStarts.contains($0) }) { score += 1 }
                if b == 0 && blocks.count > 1 { score -= 3 }   // let the chat get going first
                scored.append((score, idx))
            }
            var routeID = 600_000
            for cand in scored.sorted(by: { $0.score > $1.score }) where routeWindows.count < want {
                let first = words[cand.idx.first!].time
                let last = words[cand.idx.last!].time
                guard !routeWindows.contains(where: { abs($0.lowerBound - first) < 40 || $0.contains(first) || $0.contains(last) })
                else { continue }

                let ids = Set(cand.idx.map { words[$0].id })
                let before = items.filter { $0.time < first && !ids.contains($0.id) }.map(\.time).max() ?? 0
                let start = max(before + 0.3, first - 1.4)
                let text = cand.idx.map { words[$0].text }.joined(separator: " ")
                let route = RouteInfo(
                    stops: cand.idx.map { RouteInfo.Stop(time: words[$0].time, text: words[$0].text) },
                    start: min(start, first - 0.2),
                    place: Places.find(in: text) ?? attachRNG.pick(Places.fallback),
                    minutes: Int(attachRNG.range(8...24)),
                    seed: attachRNG.next())

                let prev = items.last { $0.time < first && !ids.contains($0.id) }
                let side = prev.map(reply(to:)) ?? (false, 1)
                items.removeAll { ids.contains($0.id) }
                items.append(ChatItem(id: routeID, time: route.start, kind: .route(route), outgoing: side.0, sender: side.1))
                items.sort { $0.time < $1.time }
                routeWindows.append(route.start...(last + 3))
                routeID += 1
            }
        }
        func inRoute(_ a: Double, _ b: Double) -> Bool {
            routeWindows.contains { $0.overlaps(a...b) }
        }
        // Nothing else fires during a route, so the map keeps the stage.
        cues.removeAll { c in routeWindows.contains { $0.contains(c.at) } }

        // Attachments: keyword replies right after a line, plus a few in long gaps.
        var usedGaps = Set<Int>()   // index into `items` of the message before a used gap
        var lastAttach = -100.0
        var attachID = 700_000
        let anchors = items
        for (n, (a, b)) in zip(anchors, anchors.dropFirst()).enumerated() {
            let gap = b.time - a.time
            guard gap >= 3.2, a.time - lastAttach > cooldown(30, mA), !inRoute(a.time, b.time) else { continue }
            guard case .lyric(let text) = a.kind else { continue }
            let tokens = EmojiMap.tokens(text)
            let place = Places.find(in: text)

            var attachment: Attachment?
            if let place, attachRNG.chance(0.8 * mA) {
                attachment = attachRNG.chance(0.5)
                    ? .liveLocation(place: place)
                    : .trip(place: place, minutes: Int(attachRNG.range(6...38)))
            } else if let wx = EmojiMap.weather(tokens), attachRNG.chance(0.6 * mA) {
                attachment = .weather(place: place ?? attachRNG.pick(Places.fallback), kind: wx, temp: temperature(wx, &attachRNG))
            } else if !tokens.isDisjoint(with: EmojiMap.travel), attachRNG.chance(0.35 * mA) {
                attachment = .trip(place: attachRNG.pick(Places.fallback), minutes: Int(attachRNG.range(6...38)))
            } else if !tokens.isDisjoint(with: EmojiMap.event), attachRNG.chance(0.4 * mA) {
                attachment = .event(title: attachRNG.pick(["Late drive", "Hang out", "Dinner?", "Show tonight", "Road trip", "Rooftop"]),
                                    when: eventTime(tokens, &attachRNG),
                                    place: attachRNG.pick(Places.fallback))
            } else if !tokens.isDisjoint(with: EmojiMap.voice), attachRNG.chance(0.3 * mA) {
                attachment = .voice(seconds: Int(attachRNG.range(4...14)), seed: attachRNG.next())
            } else if !tokens.isDisjoint(with: EmojiMap.photo), attachRNG.chance(0.35 * mA) {
                attachment = .photo
            } else if gap >= 7, attachRNG.chance(0.18 * mA) {
                attachment = attachRNG.pick([.photo, .voice(seconds: Int(attachRNG.range(4...12)), seed: attachRNG.next()),
                                             .liveLocation(place: attachRNG.pick(Places.fallback))])
            }
            guard let attachment else { continue }
            let side = reply(to: a)
            items.append(ChatItem(id: attachID, time: a.time + min(1.6, gap * 0.4),
                                  kind: .attachment(attachment), outgoing: side.0, sender: side.1))
            attachID += 1
            usedGaps.insert(n)
            lastAttach = a.time
        }

        // Emoji-only replies in long gaps (intro, instrumental breaks) not used above.
        var jumboID = 800_000
        for (n, (a, b)) in zip(anchors, anchors.dropFirst()).enumerated() {
            let gap = b.time - a.time
            guard gap >= 6.5, !usedGaps.contains(n), rng.chance(0.55 * mE), !inRoute(a.time, b.time) else { continue }
            let recent = anchors.filter { $0.time <= a.time }.suffix(3).compactMap { item -> [String]? in
                if case .lyric(let t) = item.kind { return EmojiMap.candidates(EmojiMap.tokens(t)) }
                return nil
            }.flatMap { $0 }
            let pool = recent.isEmpty ? EmojiMap.mood : recent
            let first = rng.pick(pool)
            let count = Int.random(in: 1...3, using: &rng)
            let text = rng.chance(0.5)
                ? String(repeating: first, count: count)
                : ([first] + (1..<max(count, 2)).map { _ in rng.pick(EmojiMap.mood) }).joined()
            let side = reply(to: a)
            items.append(ChatItem(id: jumboID, time: a.time + min(2.6, gap * 0.35),
                                  kind: .jumbo(text), outgoing: side.0, sender: side.1))
            jumboID += 1
        }
        items.sort { $0.time < $1.time }

        // Notification banners.
        var banners: [Banner] = []
        if mN > 0 {
            var t = 18 + rng.range(0...10) / max(mN, 0.25)
            var bannerID = 0
            let end = duration - 12
            while t < end {
                let kind = Int.random(in: 0..<3, using: &rng)
                var banner: Banner?
                if kind == 0, let reacted = items.last(where: { ($0.reaction?.at ?? .infinity) <= t && $0.reaction?.byMe == false }),
                   case .lyric(let text) = reacted.kind, let r = reacted.reaction {
                    let snippet = text.count > 28 ? String(text.prefix(28)) + "…" : text
                    banner = Banner(id: bannerID, at: t, title: contact, body: "\(r.tapback.verb) “\(snippet)”", showsArt: false)
                } else if kind == 2 {
                    banner = Banner(id: bannerID, at: t, title: contact, body: "📷 Photo", showsArt: true)
                }
                banners.append(banner ?? Banner(id: bannerID, at: t, title: contact,
                                                body: rng.pick(EmojiMap.mood) + rng.pick(EmojiMap.mood), showsArt: false))
                bannerID += 1
                t += rng.range(35...65) / mN
            }
            if duration > 90 && k.banners >= 0.2 {
                let last = duration - 30
                banners.removeAll { abs($0.at - last) < 10 }
                banners.append(Banner(id: bannerID, at: last, title: "Now Playing",
                                      body: "30 seconds left in \(title)", showsArt: true))
            }
        }

        banners.removeAll { b in routeWindows.contains { $0.contains(b.at) || $0.contains(b.at + Banner.duration) } }
        banners.sort { $0.at < $1.at }

        // Focus windows: zoom onto live maps, out again before the next event.
        let events = (items.map(\.time) + cues.map(\.at) + banners.map(\.at)).sorted()
        var focus: [FocusWindow] = []
        for item in items {
            let start: Double, hold: Double
            switch item.kind {
            case .route(let r):
                start = r.start + 0.35
                hold = (r.stops.last?.time ?? r.start) + 2.9   // through the zoomed-out arrival view
            case .attachment(.liveLocation), .attachment(.trip):
                start = item.time + 0.6
                hold = item.time + 5.5
            default:
                continue
            }
            let next = events.first { $0 > item.time + 0.001 } ?? .infinity
            let end = min(hold, next - 0.15)
            if end - start >= 1.2 { focus.append(FocusWindow(id: item.id, start: start, end: end)) }
        }

        return ChatThread(items: items, cues: cues, banners: banners, focus: focus)
    }

    private static func runLength(_ rng: inout SeededRNG) -> Int {
        let r = rng.range(0...1)
        return r < 0.4 ? 1 : (r < 0.8 ? 2 : 3)
    }

    private static func randomTapback(_ rng: inout SeededRNG, options: [String]) -> Tapback {
        let r = rng.range(0...1)
        if r < 0.30 { return .heart }
        if r < 0.55 { return .thumbsUp }
        if r < 0.70 { return .emphasize }
        if r < 0.80 { return .haha }
        return .emoji(options.isEmpty ? rng.pick(["🔥", "🥹", "💯", "😮‍💨"]) : rng.pick(options))
    }

    private static func temperature(_ w: Weather, _ rng: inout SeededRNG) -> Int {
        switch w {
        case .sunny: Int(rng.range(78...96))
        case .snow: Int(rng.range(18...31))
        case .night: Int(rng.range(52...66))
        default: Int(rng.range(55...74))
        }
    }

    private static func eventTime(_ tokens: Set<String>, _ rng: inout SeededRNG) -> String {
        let day = ["friday", "saturday", "sunday", "monday", "tomorrow", "tonight"].first { tokens.contains($0) }
        let hour = rng.pick(["7:00 PM", "8:30 PM", "9:00 PM", "10:00 PM", "11:30 PM"])
        return "\(day?.capitalized ?? "Tonight") · \(hour)"
    }
}
