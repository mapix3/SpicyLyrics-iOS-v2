import Foundation

struct TrackInfo: Codable, Equatable {
    var id: String
    var title: String
    var artist: String
    var album: String
    var duration: Double
    var artworkURL: String?
}

private let userAgent = "SpicyLyricsWidget/1.0 (https://github.com/mapix3/SpicyLyrics-iOS-v2)"

private func getJSON(_ url: URL, headers: [String: String] = [:]) async -> (Any?, Int) {
    var req = URLRequest(url: url, timeoutInterval: 12)
    req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
    headers.forEach { req.setValue($0.value, forHTTPHeaderField: $0.key) }
    guard let (data, resp) = try? await URLSession.shared.data(for: req) else { return (nil, -1) }
    return (try? JSONSerialization.jsonObject(with: data), (resp as? HTTPURLResponse)?.statusCode ?? 0)
}

enum LRCLib {
    static func lyrics(for t: TrackInfo) async -> Lyrics? {
        func q(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? s }
        let exact = URL(string: "https://lrclib.net/api/get?track_name=\(q(t.title))&artist_name=\(q(t.artist))&album_name=\(q(t.album))&duration=\(Int(t.duration.rounded()))")!
        if case let (json as [String: Any], 200) = await getJSON(exact),
           let ly = make(json, t) { return ly }

        let search = URL(string: "https://lrclib.net/api/search?track_name=\(q(cleanTitle(t.title)))&artist_name=\(q(firstArtist(t.artist)))")!
        guard case let (items as [[String: Any]], _) = await getJSON(search) else { return nil }
        let best = items
            .filter { ($0["syncedLyrics"] as? String)?.isEmpty == false }
            .map { ($0, abs(($0["duration"] as? Double ?? 0) - t.duration)) }
            .filter { $0.1 <= 2.0 }
            .min { $0.1 < $1.1 }
        return best.flatMap { make($0.0, t) }
    }

    private static func make(_ json: [String: Any], _ t: TrackInfo) -> Lyrics? {
        guard let synced = json["syncedLyrics"] as? String, !synced.isEmpty else { return nil }
        let lines = LyricsParser.parseLRC(synced, duration: t.duration)
        return lines.isEmpty ? nil : Lyrics(trackID: t.id, source: "LRCLIB", synced: true, lines: lines)
    }

    static func cleanTitle(_ s: String) -> String {
        var r = s
        if let d = r.range(of: " - ") { r = String(r[..<d.lowerBound]) }
        if let p = r.range(of: #"\s*[\(\[](feat\.?|ft\.?|with)[^\)\]]*[\)\]]"#, options: [.regularExpression, .caseInsensitive]) {
            r.removeSubrange(p)
        }
        return r.trimmingCharacters(in: .whitespaces)
    }

    static func firstArtist(_ s: String) -> String {
        s.components(separatedBy: ", ").first ?? s
    }
}

enum SpicySource {
    static let endpoint = "https://api.spicylyrics.org/v1/lyrics/"

    static var enabled: Bool {
        get { SharedStore.defaults.object(forKey: "spicyEnabled") as? Bool ?? !Secrets.spicyAPIKey.isEmpty }
        set { SharedStore.defaults.set(newValue, forKey: "spicyEnabled") }
    }
    static var apiKey: String {
        get { SharedStore.defaults.string(forKey: "spicyKey") ?? "" }
        set { SharedStore.defaults.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "spicyKey") }
    }
    static var effectiveKey: String { apiKey.isEmpty ? Secrets.spicyAPIKey : apiKey }

    static var lastStatus: String {
        get { SharedStore.defaults.string(forKey: "spicyStatus") ?? "" }
        set { SharedStore.defaults.set(newValue, forKey: "spicyStatus") }
    }

    static func lyrics(for t: TrackInfo) async -> Lyrics? {
        guard enabled else { return nil }
        let key = effectiveKey
        guard !key.isEmpty else { lastStatus = "нет ключа"; return nil }
        guard let url = URL(string: endpoint + t.id) else { return nil }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        guard let (data, resp) = try? await URLSession.shared.data(for: req) else { lastStatus = "нет соединения"; return nil }
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let body = json?["Body"] as? [String: Any]
        guard status == 200, let body else {
            if status == 404 { lastStatus = "текста нет"; return nil }
            let code = body?["error"] as? String ?? ""
            let msg = body?["message"] as? String ?? ""
            lastStatus = "\(status) \(code) \(msg)".trimmingCharacters(in: .whitespaces)
            return nil
        }
        guard let ly = parse(body, t) else { lastStatus = "неизвестный формат"; return nil }
        lastStatus = "ок"
        return ly
    }

    static func parse(_ d: [String: Any], _ t: TrackInfo) -> Lyrics? {
        let type = d["Type"] as? String ?? ""
        var starts: [(Double, String, Double?)] = []
        func num(_ v: Any?) -> Double? { (v as? NSNumber)?.doubleValue }
        if type == "Syllable", let content = d["Content"] as? [[String: Any]] {
            for c in content {
                guard let lead = c["Lead"] as? [String: Any], let syl = lead["Syllables"] as? [[String: Any]], !syl.isEmpty else { continue }
                var text = ""
                for (i, s) in syl.enumerated() {
                    text += s["Text"] as? String ?? ""
                    if !((s["IsPartOfWord"] as? Bool) ?? false), i + 1 < syl.count { text += " " }
                }
                let start = num(lead["StartTime"]) ?? num(syl.first?["StartTime"]) ?? 0
                let end = num(lead["EndTime"]) ?? num(syl.last?["EndTime"])
                starts.append((start, text, end))
            }
        } else if type == "Line", let content = d["Content"] as? [[String: Any]] {
            for c in content { starts.append((num(c["StartTime"]) ?? 0, c["Text"] as? String ?? "", num(c["EndTime"]))) }
        } else {
            return nil
        }
        let lines = LyricsParser.build(starts: starts, duration: t.duration)
        guard !lines.isEmpty else { return nil }

        let provider: String
        switch d["source"] as? String ?? "" {
        case "spicy_lyrics": provider = "Spicy Lyrics"
        case "apple_music": provider = "Apple Music (через Spicy Lyrics)"
        case "spotify": provider = "Spotify (через Spicy Lyrics)"
        case let other: provider = other.isEmpty ? "Spicy Lyrics" : "\(other) (через Spicy Lyrics)"
        }
        func credit(_ v: Any?) -> Credit? {
            guard let o = v as? [String: Any], let name = o["username"] as? String, !name.isEmpty else { return nil }
            return Credit(name: name, url: o["url"] as? String)
        }
        let attr = d["UploadAttribution"] as? [String: Any]
        return Lyrics(trackID: t.id, source: provider, synced: true, lines: lines,
                      uploader: credit(attr?["Uploader"]), maker: credit(attr?["Maker"]))
    }
}
