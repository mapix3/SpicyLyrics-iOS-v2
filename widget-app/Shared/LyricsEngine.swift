import Foundation

/// Что играло на момент запроса. Позиция в любой момент = progress + (t - capturedAt), если играет.
struct NowPlaying: Codable {
    var track: TrackInfo
    var progress: Double
    var capturedAt: Date
    var isPlaying: Bool

    func position(at date: Date) -> Double {
        isPlaying ? min(progress + date.timeIntervalSince(capturedAt), track.duration) : progress
    }
    /// Когда трек дойдёт до секунды `t`.
    func date(atPosition t: Double) -> Date {
        capturedAt.addingTimeInterval(t - progress)
    }
}

struct EngineState {
    var nowPlaying: NowPlaying?
    var lyrics: Lyrics?
    var error: String?
}

enum LyricsEngine {
    /// Узнать, что играет, и подготовить текст целиком (из кэша или из сети).
    static func refresh() async -> EngineState {
        let token: String
        do { token = try await SpotifyAuth.accessToken() } catch {
            return EngineState(error: error.localizedDescription)
        }

        let np: NowPlaying?
        do { np = try await currentlyPlaying(token: token) } catch {
            return EngineState(nowPlaying: SharedStore.load(NowPlaying.self, from: "nowplaying.json"), error: error.localizedDescription)
        }
        guard let np else {
            return EngineState(error: "Сейчас ничего не играет")
        }
        SharedStore.save(np, as: "nowplaying.json")
        await cacheArtwork(np.track)

        let file = "lyrics_\(np.track.id).json"
        // кэш не дольше 30 дней (условие Spicy Lyrics API)
        if let cached = SharedStore.load(Lyrics.self, from: file),
           let at = cached.fetchedAt, Date().timeIntervalSince(at) < 30 * 24 * 3600 {
            return EngineState(nowPlaying: np, lyrics: cached)
        }
        var ly = await SpicySource.lyrics(for: np.track)
        if ly == nil { ly = await LRCLib.lyrics(for: np.track) }
        ly?.fetchedAt = Date()
        if let ly { SharedStore.save(ly, as: file) } else { try? FileManager.default.removeItem(at: SharedStore.directory.appendingPathComponent(file)) }
        return EngineState(nowPlaying: np, lyrics: ly, error: ly == nil ? "Синхронного текста нет" : nil)
    }

    static func currentlyPlaying(token: String) async throws -> NowPlaying? {
        var req = URLRequest(url: URL(string: "https://api.spotify.com/v1/me/player/currently-playing?additional_types=track")!,
                             timeoutInterval: 10)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let sent = Date()
        let (data, resp) = try await URLSession.shared.data(for: req)
        let received = Date()
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if status == 204 { return nil }
        guard status == 200,
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let item = json["item"] as? [String: Any],
              let id = item["id"] as? String else {
            if status == 401 { throw SpotifyAuth.AuthError.notLoggedIn }
            if status == 403 { throw SpotifyAuth.AuthError.http(403, "аккаунт не добавлен в приложение на developer.spotify.com") }
            if status == 200 { return nil }   // реклама/подкаст
            throw SpotifyAuth.AuthError.http(status, "")
        }
        let artists = (item["artists"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }
        let album = item["album"] as? [String: Any]
        let images = album?["images"] as? [[String: Any]] ?? []
        let art = images.min { abs(($0["width"] as? Int ?? 0) - 300) < abs(($1["width"] as? Int ?? 0) - 300) }?["url"] as? String
        let track = TrackInfo(id: id, title: item["name"] as? String ?? "",
                              artist: artists.joined(separator: ", "),
                              album: album?["name"] as? String ?? "",
                              duration: (item["duration_ms"] as? Double ?? 0) / 1000,
                              artworkURL: art)
        // позиция была замерена где-то посередине запроса
        let mid = sent.addingTimeInterval(received.timeIntervalSince(sent) / 2)
        return NowPlaying(track: track,
                          progress: (json["progress_ms"] as? Double ?? 0) / 1000,
                          capturedAt: mid,
                          isPlaying: json["is_playing"] as? Bool ?? false)
    }

    static var artworkFile: URL { SharedStore.directory.appendingPathComponent("artwork.jpg") }

    private static func cacheArtwork(_ t: TrackInfo) async {
        let d = SharedStore.defaults
        guard let s = t.artworkURL, d.string(forKey: "artworkFor") != t.id, let url = URL(string: s),
              let (data, _) = try? await URLSession.shared.data(from: url) else { return }
        try? data.write(to: artworkFile, options: .atomic)
        d.set(t.id, forKey: "artworkFor")
    }
}

/// Расписание строк для виджета.
enum LyricsTimeline {
    struct Slot {
        var date: Date
        var index: Int?          // индекс строки (nil = до первой строки)
    }

    static func index(in lines: [LyricLine], at position: Double) -> Int? {
        var ans: Int? = nil
        for (i, l) in lines.enumerated() where l.start <= position { ans = i }
        return ans
    }

    /// Слоты: «сейчас» + момент начала каждой следующей строки (с учётом сдвига).
    static func slots(np: NowPlaying, lines: [LyricLine], now: Date, offset: Double, limit: Int = 150) -> [Slot] {
        let pos = np.position(at: now) + offset
        var slots = [Slot(date: now, index: index(in: lines, at: pos))]
        guard np.isPlaying else { return slots }
        for (i, l) in lines.enumerated() where l.start > pos {
            let d = np.date(atPosition: l.start - offset)
            if d <= now { continue }
            slots.append(Slot(date: d, index: i))
            if slots.count >= limit { break }
        }
        return slots
    }
}
