import Foundation

struct LyricLine: Codable, Hashable {
    var start: Double
    var end: Double
    var text: String
    var isInterlude: Bool = false
}

struct Credit: Codable, Hashable {
    var name: String
    var url: String?
}

struct Lyrics: Codable {
    var trackID: String
    var source: String
    var synced: Bool
    var lines: [LyricLine]
    var uploader: Credit? = nil
    var maker: Credit? = nil
    var fetchedAt: Date? = nil

    var attribution: String {
        var s = source
        if let u = uploader { s += " · загрузил \(u.name)" }
        if let m = maker { s += " · синхронизировал \(m.name)" }
        return s
    }
}

enum LyricsParser {
    static let interludeGap = 3.0

    static func isInstrumental(_ s: String) -> Bool {
        s.trimmingCharacters(in: CharacterSet(charactersIn: "♪♫♬♩🎵🎶 .…-–—*•").union(.whitespaces)).isEmpty
    }

    static func build(starts: [(Double, String, Double?)], duration: Double) -> [LyricLine] {
        let sorted = starts.sorted { $0.0 < $1.0 }
        var lines: [LyricLine] = []
        for (i, s) in sorted.enumerated() {
            if isInstrumental(s.1) { continue }
            let next = i + 1 < sorted.count ? sorted[i + 1].0 : duration
            let end = s.2 ?? next
            lines.append(LyricLine(start: s.0, end: max(end, s.0 + 0.1), text: s.1.trimmingCharacters(in: .whitespaces)))
        }
        var out: [LyricLine] = []
        for (i, l) in lines.enumerated() {
            if i == 0, l.start >= interludeGap { out.append(LyricLine(start: 0, end: l.start, text: "♪", isInterlude: true)) }
            out.append(l)
            if i + 1 < lines.count, lines[i + 1].start - l.end >= interludeGap {
                out.append(LyricLine(start: l.end, end: lines[i + 1].start, text: "♪", isInterlude: true))
            }
        }
        return out
    }

    static func parseLRC(_ lrc: String, duration: Double) -> [LyricLine] {
        let lineTag = try! NSRegularExpression(pattern: #"\[(\d{1,3}):(\d{1,2}(?:[.:,]\d{1,3})?)\]"#)
        let wordTag = try! NSRegularExpression(pattern: #"<\d{1,3}:\d{1,2}(?:[.:,]\d{1,3})?>"#)
        var starts: [(Double, String, Double?)] = []
        for raw in lrc.components(separatedBy: .newlines) {
            let ns = raw as NSString
            let tags = lineTag.matches(in: raw, range: NSRange(location: 0, length: ns.length))
            guard let last = tags.last else { continue }
            var body = ns.substring(from: last.range.location + last.range.length)
            body = wordTag.stringByReplacingMatches(in: body, range: NSRange(location: 0, length: (body as NSString).length), withTemplate: "")
            for t in tags {
                let m = Double(ns.substring(with: t.range(at: 1))) ?? 0
                let s = Double(ns.substring(with: t.range(at: 2)).replacingOccurrences(of: ",", with: ".").replacingOccurrences(of: ":", with: ".")) ?? 0
                starts.append((m * 60 + s, body, nil))
            }
        }
        return build(starts: starts, duration: duration)
    }
}
