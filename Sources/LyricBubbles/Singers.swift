import Foundation

/// Who sings in a track. Index 0 is the lead (first-listed) artist.
struct Cast: Equatable {
    enum Source: Equatable {
        case single    // one known singer
        case tagged    // lyrics carried singer tags ("Name: ...", "[Verse 2: Name]", "v2: ...")
        case guessed   // inferred from song structure
    }
    static let everyone = -1

    var names: [String]
    var source: Source
    var edited = false   // user reassigned at least one section

    var isMulti: Bool { names.count > 1 }

    func name(_ i: Int) -> String {
        if i == Cast.everyone { return "Everyone" }
        return names.indices.contains(i) ? names[i] : "Singer \(i + 1)"
    }
}

/// Works out which singer has each lyric line.
///
/// LRC files rarely mark singers, so this tries, in order:
/// 1. explicit tags in the lyric text;
/// 2. a structure guess: repeated blocks (choruses) go to everyone,
///    other blocks (verses) rotate through the credited artists.
enum SingerDetector {
    // MARK: Artists

    static func artists(artist: String, title: String) -> [String] {
        var out: [String] = []
        func add(_ raw: String) {
            let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty, !out.contains(where: { norm($0) == norm(t) }) else { return }
            out.append(t)
        }
        split(artist).forEach(add)

        let feat = try! NSRegularExpression(
            pattern: #"[\(\[](?:feat\.?|ft\.?|featuring|with)\s+([^\)\]]+)[\)\]]"#,
            options: .caseInsensitive)
        let ns = title as NSString
        for m in feat.matches(in: title, range: NSRange(location: 0, length: ns.length)) {
            split(ns.substring(with: m.range(at: 1))).forEach(add)
        }
        return out
    }

    /// "A, B & C feat. D" -> [A, B, C, D]
    static func split(_ s: String) -> [String] {
        s.replacingOccurrences(
            of: #"\s*(?:,|&|\s+x\s+|\bfeat\.?\s|\bft\.?\s|\bfeaturing\s|\bwith\s)\s*"#,
            with: "\u{1F}", options: [.regularExpression, .caseInsensitive])
        .components(separatedBy: "\u{1F}")
    }

    static func norm(_ s: String) -> String {
        s.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    // MARK: Tag patterns

    private static let everyoneWords: Set<String> = ["both", "all", "everyone", "together", "allartists", "group", "tutti"]

    /// "[Verse 2: Name]" or "(Name)" alone on a line.
    static func header(_ text: String) -> String? {
        guard let m = text.range(of: #"^\s*[\[\(]([^\]\)]{1,60})[\]\)]\s*$"#, options: .regularExpression) else { return nil }
        return String(text[m]).trimmingCharacters(in: CharacterSet(charactersIn: "[]() \t"))
    }

    /// "Name: words" or "(Name) words" -> (Name, words)
    static func prefix(_ text: String) -> (String, String)? {
        for pattern in [#"^\s*([^:\(\)\[\]]{1,30}):\s+(\S.*)$"#, #"^\s*[\(\[]([^\)\]]{1,30})[\)\]]\s+(\S.*)$"#] {
            let re = try! NSRegularExpression(pattern: pattern)
            let ns = text as NSString
            if let m = re.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) {
                return (ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespaces),
                        ns.substring(with: m.range(at: 2)))
            }
        }
        return nil
    }

    private static func vIndex(_ s: String) -> Int? {
        guard let m = s.range(of: #"^[vV](\d)$"#, options: .regularExpression) else { return nil }
        return Int(s[m].dropFirst()).map { $0 - 1 }
    }

    private static func looksLikeName(_ s: String) -> Bool {
        let words = s.split(separator: " ")
        return (1...4).contains(words.count) && (s.first?.isUppercase ?? false)
    }

    /// Index of a credited name the candidate refers to ("Gaga" -> "Lady Gaga").
    static func matchName(_ candidate: String, in names: [String]) -> Int? {
        let c = norm(candidate)
        guard c.count >= 2 else { return nil }
        if let i = names.firstIndex(where: { norm($0) == c }) { return i }
        return names.firstIndex { n in
            let nn = norm(n)
            return (nn.count >= 3 && c.contains(nn)) || (c.count >= 3 && nn.contains(c))
        }
    }

    private static func resolve(_ candidate: String, names: inout [String], isHeader: Bool) -> Int? {
        if everyoneWords.contains(norm(candidate)) { return Cast.everyone }
        if let v = vIndex(candidate) {
            while names.count <= v { names.append("Singer \(names.count + 1)") }
            return v
        }
        if isHeader {
            // "Verse 2: A & B" names two singers -> everyone.
            let hits = names.indices.filter { norm(candidate).contains(norm(names[$0])) && norm(names[$0]).count >= 3 }
            if hits.count >= 2 { return Cast.everyone }
            if let h = hits.first { return h }
            let words = candidate.lowercased().split(whereSeparator: { !$0.isLetter })
            if words.contains(where: { everyoneWords.contains(String($0)) }) { return Cast.everyone }
            return nil
        }
        return matchName(candidate, in: names)
    }

    // MARK: Detect

    static func detect(_ input: [LyricLine], artist: String, title: String) -> ([LyricLine], Cast) {
        var names = artists(artist: artist, title: title)
        if names.isEmpty { names = [artist.isEmpty ? "Singer 1" : artist] }
        var lines = input

        // An unknown "Name:" prefix used twice or more is treated as a singer too.
        var seen: [String: Int] = [:]
        for l in lines {
            if let (p, _) = prefix(l.text) { seen[p, default: 0] += 1 }
        }
        for l in lines {
            guard let (p, _) = prefix(l.text), seen[p, default: 0] >= 2, looksLikeName(p),
                  matchName(p, in: names) == nil, vIndex(p) == nil,
                  !everyoneWords.contains(norm(p)) else { continue }
            names.append(p)
            seen[p] = 0
        }

        // Pass 1: explicit tags. Untagged lines inherit the last tagged singer.
        var current = 0
        var tagged = 0
        for i in lines.indices {
            let text = lines[i].text
            if let inner = header(text) {
                if let s = resolve(inner, names: &names, isHeader: true) {
                    current = s
                    tagged += 1
                    lines[i].text = ""   // header becomes a section break
                }
            } else if let (p, rest) = prefix(text), let s = resolve(p, names: &names, isHeader: false) {
                current = s
                tagged += 1
                lines[i].text = rest
            }
            lines[i].singer = current
        }

        markSections(&lines)

        let source: Cast.Source
        if tagged >= 2 {
            source = .tagged
        } else if names.count >= 2 {
            guess(&lines, singers: names.count)
            source = .guessed
        } else {
            for i in lines.indices { lines[i].singer = 0 }
            source = .single
        }
        return (lines, Cast(names: names, source: source))
    }

    /// Splits the song into blocks at blank LRC lines, long pauses, or where
    /// repeated (chorus-like) lines start or stop.
    static func markSections(_ lines: inout [LyricLine]) {
        let words = lines.indices.filter { !lines[$0].text.isEmpty }
        let gaps = zip(words, words.dropFirst()).map { lines[$1].time - lines[$0].time }.sorted()
        let median = gaps.isEmpty ? 3 : gaps[gaps.count / 2]
        let threshold = max(3.5, median * 1.8)

        var occurrences: [String: Int] = [:]
        for i in words { occurrences[norm(lines[i].text), default: 0] += 1 }
        let repeated = words.map { (occurrences[norm(lines[$0].text)] ?? 0) > 1 }

        var section = 0
        var k = -1           // index into `words` of the current line
        var sawBreak = false
        for i in lines.indices {
            if lines[i].text.isEmpty {
                sawBreak = true
                lines[i].section = section
                continue
            }
            k += 1
            if k > 0 {
                let pause = lines[i].time - lines[words[k - 1]].time >= threshold
                // Repetition flips and holds for at least 2 lines: chorus starts or ends here.
                let flip = repeated[k] != repeated[k - 1]
                    && (k + 1 >= words.count || repeated[k + 1] == repeated[k])
                if sawBreak || pause || flip { section += 1 }
            }
            sawBreak = false
            lines[i].section = section
        }
    }

    /// Repeated blocks (choruses) -> everyone. Other blocks rotate through singers.
    static func guess(_ lines: inout [LyricLine], singers: Int) {
        let sections = Dictionary(grouping: lines.filter { !$0.text.isEmpty }, by: \.section)

        var sectionsContaining: [String: Int] = [:]
        for (_, ls) in sections {
            for key in Set(ls.map { norm($0.text) }) { sectionsContaining[key, default: 0] += 1 }
        }

        var assign: [Int: Int] = [:]
        var verse = 0
        for sec in sections.keys.sorted() {
            let ls = sections[sec]!
            let repeated = ls.filter { (sectionsContaining[norm($0.text)] ?? 0) > 1 }.count
            if ls.count >= 2 && Double(repeated) >= Double(ls.count) * 0.5 {
                assign[sec] = Cast.everyone
            } else if ls.count <= 1, let prev = assign[sec - 1] {
                assign[sec] = prev   // one-line ad-lib stays with the block before it
            } else {
                assign[sec] = verse % singers
                verse += 1
            }
        }
        for i in lines.indices { lines[i].singer = assign[lines[i].section] ?? 0 }
    }
}

/// User fixes to singer guesses, saved per track and per section.
enum SingerOverrides {
    private static let key = "singerOverrides"

    static func load(_ track: String) -> [Int: Int] {
        let all = UserDefaults.standard.dictionary(forKey: key) as? [String: [String: Int]] ?? [:]
        return Dictionary(uniqueKeysWithValues: (all[track] ?? [:]).compactMap { k, v in Int(k).map { ($0, v) } })
    }

    static func save(_ track: String, _ map: [Int: Int]) {
        var all = UserDefaults.standard.dictionary(forKey: key) as? [String: [String: Int]] ?? [:]
        all[track] = map.isEmpty ? nil : Dictionary(uniqueKeysWithValues: map.map { (String($0.key), $0.value) })
        UserDefaults.standard.set(all, forKey: key)
    }

    static func apply(_ map: [Int: Int], to lines: inout [LyricLine], cast: inout Cast) {
        guard !map.isEmpty else { return }
        for i in lines.indices {
            if let s = map[lines[i].section] { lines[i].singer = s }
        }
        let top = map.values.max() ?? 0
        while cast.names.count <= top { cast.names.append("Singer \(cast.names.count + 1)") }
        cast.edited = true
    }
}
