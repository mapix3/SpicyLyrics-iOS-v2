import WidgetKit
import SwiftUI
import AppIntents
import UIKit

struct LyricsEntry: TimelineEntry {
    var date: Date
    var title: String = ""
    var artist: String = ""
    var previous: String?
    var current: String?
    var next: String?
    var isInterlude = false
    var message: String?
    var artwork: UIImage?
    var attribution: String?
    var creditURL: URL?
}

struct SyncLyricsIntent: AppIntent {
    static var title: LocalizedStringResource = "Синхронизировать текст"
    func perform() async throws -> some IntentResult { .result() }
}

struct LyricsProvider: TimelineProvider {
    func placeholder(in context: Context) -> LyricsEntry {
        LyricsEntry(date: .now, title: "Название", artist: "Артист",
                    previous: "Предыдущая строка", current: "Текущая строка песни", next: "Следующая строка")
    }

    func getSnapshot(in context: Context, completion: @escaping (LyricsEntry) -> Void) {
        if context.isPreview { completion(placeholder(in: context)); return }
        Task { completion(await build(now: .now).entries.first ?? placeholder(in: context)) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LyricsEntry>) -> Void) {
        Task {
            let r = await build(now: .now)
            completion(Timeline(entries: r.entries, policy: .after(r.reload)))
        }
    }

    private func build(now: Date) async -> (entries: [LyricsEntry], reload: Date) {
        let state = await LyricsEngine.refresh()
        let art = UIImage(contentsOfFile: LyricsEngine.artworkFile.path).flatMap { downscale($0) }

        guard let np = state.nowPlaying else {
            return ([LyricsEntry(date: now, message: state.error ?? "Ничего не играет")], now.addingTimeInterval(15 * 60))
        }
        var base = LyricsEntry(date: now, title: np.track.title, artist: np.track.artist, artwork: art)
        let trackEnd = np.date(atPosition: np.track.duration).addingTimeInterval(1.5)

        guard let lines = state.lyrics?.lines, !lines.isEmpty else {
            base.message = state.error ?? "Текста нет"
            return ([base], np.isPlaying ? max(trackEnd, now.addingTimeInterval(30)) : now.addingTimeInterval(15 * 60))
        }

        if let ly = state.lyrics {
            base.attribution = ly.attribution
            base.creditURL = (ly.maker?.url ?? ly.uploader?.url).flatMap(URL.init(string:))
        }
        let slots = LyricsTimeline.slots(np: np, lines: lines, now: now, offset: SharedStore.offset)
        let entries = slots.map { slot -> LyricsEntry in
            var e = base
            e.date = slot.date
            if let i = slot.index {
                e.current = lines[i].text
                e.isInterlude = lines[i].isInterlude
                e.previous = i > 0 ? lines[i - 1].text : nil
                e.next = i + 1 < lines.count ? lines[i + 1].text : nil
            } else {
                e.current = "♪"
                e.isInterlude = true
                e.next = lines.first?.text
            }
            if !np.isPlaying { e.message = "Пауза" }
            return e
        }
        let reload = np.isPlaying ? max(trackEnd, now.addingTimeInterval(30)) : now.addingTimeInterval(15 * 60)
        return (entries, reload)
    }

    private func downscale(_ img: UIImage) -> UIImage {
        let side: CGFloat = 200
        guard img.size.width > side else { return img }
        let r = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))
        return r.image { _ in img.draw(in: CGRect(x: 0, y: 0, width: side, height: side)) }
    }
}

struct LyricsWidgetView: View {
    @Environment(\.widgetFamily) var family
    var entry: LyricsEntry

    var body: some View {
        Group {
            switch family {
            case .accessoryRectangular: lockScreen
            case .systemLarge: full(prevNext: true, size: 26)
            default: full(prevNext: false, size: 21)
            }
        }
        .containerBackground(for: .widget) { background }
    }

    private var lockScreen: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(entry.current ?? entry.message ?? entry.title)
                .font(.headline).lineLimit(2).minimumScaleFactor(0.7)
            if let a = entry.attribution { Text(a).font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary).lineLimit(1) }
        }
    }

    private func full(prevNext: Bool, size: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if let a = entry.artwork {
                    Image(uiImage: a).resizable().aspectRatio(contentMode: .fill)
                        .frame(width: 30, height: 30).clipShape(RoundedRectangle(cornerRadius: 6))
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text(entry.title).font(.system(size: 13, weight: .bold)).lineLimit(1)
                    Text(entry.artist).font(.system(size: 11, weight: .medium)).opacity(0.7).lineLimit(1)
                }
                Spacer(minLength: 4)
                Button(intent: SyncLyricsIntent()) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 28, height: 28)
                        .background(.white.opacity(0.18), in: Circle())
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
            if let m = entry.message, entry.current == nil {
                Text(m).font(.system(size: 17, weight: .semibold)).opacity(0.8)
            } else {
                if prevNext, let p = entry.previous {
                    Text(p).font(.system(size: size * 0.7, weight: .bold)).opacity(0.35).lineLimit(2)
                }
                Text(entry.isInterlude ? "• • •" : (entry.current ?? ""))
                    .font(.system(size: size, weight: .heavy))
                    .lineLimit(prevNext ? 4 : 3)
                    .minimumScaleFactor(0.6)
                    .shadow(color: .white.opacity(0.35), radius: 6)
                if let n = entry.next {
                    Text(n).font(.system(size: size * 0.7, weight: .bold)).opacity(0.45).lineLimit(prevNext ? 2 : 1)
                }
                if let m = entry.message { Text(m).font(.caption2.weight(.semibold)).opacity(0.6) }
            }
            Spacer(minLength: 0)
            if let a = entry.attribution {
                let caption = Text("Текст: \(a)").font(.system(size: 10, weight: .semibold)).opacity(0.55).lineLimit(1)
                if let u = entry.creditURL { Link(destination: u) { caption } } else { caption }
            }
        }
        .padding(16)
        .foregroundStyle(.white)
    }

    private var background: some View {
        ZStack {
            Color(white: 0.08)
            if let a = entry.artwork {
                Image(uiImage: a).resizable().aspectRatio(contentMode: .fill)
                    .scaleEffect(1.6).blur(radius: 28).saturation(1.5)
            }
            Color.black.opacity(0.32)
        }
    }
}

@main
struct LyricsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SpicyLyricsWidget", provider: LyricsProvider()) { entry in
            LyricsWidgetView(entry: entry)
        }
        .configurationDisplayName("Текст песни")
        .description("Текущая строка песни из Spotify, синхронно с музыкой.")
        .supportedFamilies([.systemMedium, .systemLarge, .accessoryRectangular])
        .contentMarginsDisabled()
    }
}
