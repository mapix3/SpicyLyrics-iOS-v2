import WidgetKit
import SwiftUI
import AppIntents
import UIKit

struct LyricsEntry: TimelineEntry {
    var date: Date
    var state: WidgetState?
    var artwork: UIImage?
    var index: Int?
}

struct ReloadLyricsIntent: AppIntent {
    static var title: LocalizedStringResource = "Reload lyrics"
    func perform() async throws -> some IntentResult { .result() }
}

struct LyricsProvider: TimelineProvider {
    func placeholder(in context: Context) -> LyricsEntry {
        let state = WidgetState(v: 1, titleLabel: "Lyrics", capturedAt: Date().timeIntervalSince1970,
                                trackKey: "preview", title: "Song", artist: "Artist", duration: 200, position: 30,
                                playing: false, hasArtwork: false, status: "ok", message: nil,
                                palette: ["#7A4FD0", "#D04F8A", "#4F8AD0", "#D0A04F"], base: "#1E1630",
                                lines: [WidgetLine(s: 0, e: 20, t: "Previous line", i: false),
                                        WidgetLine(s: 20, e: 40, t: "Current line of the song", i: false),
                                        WidgetLine(s: 40, e: 60, t: "Next line", i: false)],
                                synced: true, footer: "Lyrics: Spicy Lyrics")
        return LyricsEntry(date: .now, state: state, artwork: nil, index: 1)
    }

    func getSnapshot(in context: Context, completion: @escaping (LyricsEntry) -> Void) {
        if context.isPreview, WidgetStore.load() == nil { completion(placeholder(in: context)); return }
        completion(entries(now: .now).first ?? placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LyricsEntry>) -> Void) {
        let now = Date()
        let list = entries(now: now)
        var reload = now.addingTimeInterval(30 * 60)
        if let s = list.first?.state, s.isPlaying, let d = s.duration, d > 0 {
            reload = max(s.date(at: d).addingTimeInterval(2), now.addingTimeInterval(20))
        }
        completion(Timeline(entries: list, policy: .after(reload)))
    }

    private func entries(now: Date) -> [LyricsEntry] {
        let state = WidgetStore.load()
        let art = (state?.hasArtwork ?? false) ? WidgetStore.artwork() : nil
        var first = LyricsEntry(date: now, state: state, artwork: art, index: nil)
        guard let s = state, let lines = s.lines, !lines.isEmpty, s.synced ?? false else { return [first] }
        let pos = s.position(at: now)
        first.index = lines.lastIndex { $0.s <= pos }
        var list = [first]
        guard s.isPlaying else { return list }
        for (i, l) in lines.enumerated() where l.s > pos {
            let d = s.date(at: l.s)
            if d <= now { continue }
            var e = first
            e.date = d
            e.index = i
            list.append(e)
            if list.count >= 160 { break }
        }
        return list
    }
}

struct PaletteBackground: View {
    var state: WidgetState?

    private static let points: [CGPoint] = [CGPoint(x: 0.15, y: 0.2), CGPoint(x: 0.85, y: 0.25),
                                            CGPoint(x: 0.25, y: 0.85), CGPoint(x: 0.8, y: 0.8)]

    var body: some View {
        GeometryReader { g in
            let w = g.size.width
            let h = g.size.height
            let d = max(w, h) * 1.15
            let colors = (state?.palette ?? []).map { Color(hex: $0) }
            let blobs = colors.isEmpty ? [Color(white: 0.3)] : colors
            ZStack {
                Color(hex: state?.base ?? "#1F1F1F")
                ForEach(0..<4, id: \.self) { i in
                    let c = blobs[i % blobs.count]
                    Circle()
                        .fill(RadialGradient(colors: [c, c.opacity(0.55), c.opacity(0)], center: .center, startRadius: 0, endRadius: d / 2))
                        .frame(width: d, height: d)
                        .position(x: w * Self.points[i].x, y: h * Self.points[i].y)
                        .opacity(0.9)
                }
                Color.black.opacity(0.22)
                LinearGradient(colors: [.black.opacity(0.18), .clear, .black.opacity(0.35)], startPoint: .top, endPoint: .bottom)
            }
        }
    }
}

struct LyricsWidgetView: View {
    @Environment(\.widgetFamily) var family
    var entry: LyricsEntry

    private var state: WidgetState? { entry.state }
    private var lines: [WidgetLine] { state?.lines ?? [] }
    private var synced: Bool { state?.synced ?? false }

    var body: some View {
        content
            .containerBackground(for: .widget) { PaletteBackground(state: state) }
    }

    @ViewBuilder private var content: some View {
        switch family {
        case .accessoryRectangular: lockScreen
        case .systemSmall: card(size: 17, context: false, header: false)
        case .systemLarge: card(size: 26, context: true, header: true)
        default: card(size: 21, context: false, header: true)
        }
    }

    private var currentText: String? {
        guard synced, !lines.isEmpty else { return nil }
        guard let i = entry.index, i < lines.count else { return "• • •" }
        return lines[i].i ? "• • •" : lines[i].t
    }

    private var previousText: String? {
        guard synced, let i = entry.index, i > 0 else { return nil }
        return lines[..<i].last { !$0.i && !$0.t.isEmpty }?.t
    }

    private var nextText: String? {
        guard synced, !lines.isEmpty else { return nil }
        let start = (entry.index ?? -1) + 1
        guard start < lines.count else { return nil }
        return lines[start...].first { !$0.i && !$0.t.isEmpty }?.t
    }

    private var message: String? {
        if let m = state?.message { return m }
        return state == nil ? "Spotify" : nil
    }

    private var lockScreen: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(currentText ?? message ?? state?.title ?? "♪")
                .font(.headline).lineLimit(2).minimumScaleFactor(0.7)
            if let n = nextText {
                Text(n).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func card(size: CGFloat, context: Bool, header: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if header { headerRow }
            Spacer(minLength: 0)
            lyricsBlock(size: size, context: context)
            Spacer(minLength: 0)
            if family != .systemSmall, let f = state?.footer {
                Text(f).font(.system(size: 10, weight: .semibold)).opacity(0.55).lineLimit(1)
            }
        }
        .padding(family == .systemSmall ? 12 : 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .foregroundStyle(.white)
    }

    private var headerRow: some View {
        HStack(spacing: 8) {
            if let a = entry.artwork {
                Image(uiImage: a).resizable().aspectRatio(contentMode: .fill)
                    .frame(width: 30, height: 30)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 4) {
                    Text(state?.titleLabel ?? "Lyrics").font(.system(size: 13, weight: .bold)).lineLimit(1)
                    if let s = state, !s.isPlaying, s.trackKey != nil {
                        Image(systemName: "pause.fill").font(.system(size: 9, weight: .bold)).opacity(0.7)
                    }
                }
                let sub = [state?.title, state?.artist].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
                if !sub.isEmpty {
                    Text(sub).font(.system(size: 11, weight: .medium)).opacity(0.7).lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            Button(intent: ReloadLyricsIntent()) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 12, weight: .bold))
                    .frame(width: 28, height: 28)
                    .background(.white.opacity(0.16), in: Circle())
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder private func lyricsBlock(size: CGFloat, context: Bool) -> some View {
        if let current = currentText {
            VStack(alignment: .leading, spacing: 6) {
                if context, let p = previousText {
                    Text(p).font(.system(size: size * 0.72, weight: .bold)).opacity(0.35).lineLimit(2)
                }
                Text(current)
                    .font(.system(size: size, weight: .heavy))
                    .lineLimit(context ? 4 : 3)
                    .minimumScaleFactor(0.6)
                    .shadow(color: .white.opacity(0.3), radius: 6)
                if let n = nextText {
                    Text(n).font(.system(size: size * 0.72, weight: .bold)).opacity(0.45).lineLimit(context ? 2 : 1)
                }
            }
        } else if !synced, !lines.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(lines.prefix(context ? 6 : 3).enumerated()), id: \.offset) { _, l in
                    Text(l.t).font(.system(size: size * 0.8, weight: .bold)).opacity(0.85).lineLimit(1)
                }
            }
        } else if let m = message {
            Text(m).font(.system(size: size * 0.8, weight: .semibold)).opacity(0.85).lineLimit(3)
        } else {
            Text("♪").font(.system(size: size, weight: .heavy)).opacity(0.6)
        }
    }
}

@main
struct SpicyLyricsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SpicyLyricsWidget", provider: LyricsProvider()) { entry in
            LyricsWidgetView(entry: entry)
        }
        .configurationDisplayName("Spicy Lyrics")
        .description("Synced lyrics of the song playing in Spotify.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular])
        .contentMarginsDisabled()
    }
}
