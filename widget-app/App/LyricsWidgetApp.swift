import SwiftUI
import WidgetKit
import AuthenticationServices
import UIKit

@main
struct LyricsWidgetApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
                .onOpenURL { url in
                    if url.scheme == "https" || url.scheme == "http" { UIApplication.shared.open(url) }
                }
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var clientID = SharedStore.clientID
    @Published var loggedIn = SpotifyAuth.isLoggedIn
    @Published var state = EngineState()
    @Published var loading = false
    @Published var offset = SharedStore.offset
    @Published var spicyEnabled = SpicySource.enabled
    @Published var spicyKey = SpicySource.apiKey
    @Published var spicyStatus = SpicySource.lastStatus
    @Published var error: String?

    func saveSettings() {
        SharedStore.clientID = clientID
        SharedStore.offset = offset
        SpicySource.enabled = spicyEnabled
        SpicySource.apiKey = spicyKey
    }

    func login(using session: WebAuthenticationSession) async {
        saveSettings()
        error = nil
        do {
            let verifier = SpotifyAuth.makeVerifier()
            let url = try SpotifyAuth.authorizeURL(verifier: verifier)
            let callback = try await session.authenticate(using: url, callbackURLScheme: SpotifyAuth.callbackScheme)
            try await SpotifyAuth.exchange(callback: callback, verifier: verifier)
            loggedIn = true
            await refresh()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func logout() {
        SpotifyAuth.tokens = nil
        loggedIn = false
        state = EngineState()
        WidgetCenter.shared.reloadAllTimelines()
    }

    func clearLyricsCache() {
        let dir = SharedStore.directory
        for f in (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [] where f.hasPrefix("lyrics_") {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(f))
        }
    }

    func refresh() async {
        guard loggedIn else { return }
        saveSettings()
        loading = true
        state = await LyricsEngine.refresh()
        spicyStatus = SpicySource.lastStatus
        loading = false
        WidgetCenter.shared.reloadAllTimelines()
    }
}

struct ContentView: View {
    @StateObject private var model = AppModel()
    @Environment(\.webAuthenticationSession) private var webAuth
    @Environment(\.scenePhase) private var phase

    var body: some View {
        NavigationStack {
            Form {
                if model.loggedIn { nowPlayingSection } else { loginSection }
                syncSection
                spicySection
                if model.loggedIn {
                    Section { Button("Выйти из Spotify", role: .destructive) { model.logout() } }
                }
            }
            .navigationTitle("Lyrics Widget")
            .refreshable { await model.refresh() }
        }
        .task { await model.refresh() }
        .onChange(of: phase) { _, p in if p == .active { Task { await model.refresh() } } }
    }

    private var loginSection: some View {
        Section {
            TextField("Client ID", text: $model.clientID)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .font(.system(.body, design: .monospaced))
            Button("Войти в Spotify") { Task { await model.login(using: webAuth) } }
                .disabled(model.clientID.trimmingCharacters(in: .whitespaces).isEmpty)
            if let e = model.error { Text(e).foregroundStyle(.red).font(.footnote) }
        } header: {
            Text("Вход")
        } footer: {
            Text("1. developer.spotify.com → Dashboard → Create app.\n2. Redirect URI: \(SpotifyAuth.redirectURI)\n3. API: Web API. Сохранить, скопировать Client ID сюда.\n4. В User Management добавить свой аккаунт (email).")
                .textSelection(.enabled)
        }
    }

    private var nowPlayingSection: some View {
        Section {
            if let np = model.state.nowPlaying {
                VStack(alignment: .leading, spacing: 2) {
                    Text(np.track.title).font(.headline)
                    Text(np.track.artist).foregroundStyle(.secondary)
                    if let ly = model.state.lyrics { AttributionView(lyrics: ly) }
                }
                if let ly = model.state.lyrics { LivePreview(np: np, lines: ly.lines, offset: model.offset) }
            }
            if let e = model.state.error { Text(e).foregroundStyle(.orange) }
            Button(model.loading ? "Обновляю…" : "Синхронизировать виджет") { Task { await model.refresh() } }
                .disabled(model.loading)
        } header: {
            Text("Сейчас играет")
        } footer: {
            Text("Добавь виджет «Текст песни» на экран «Домой» или экран блокировки. После перемотки жми ↻ на виджете.")
        }
    }

    private var syncSection: some View {
        Section("Синхронизация") {
            Stepper(value: $model.offset, in: -3...3, step: 0.1) {
                Text("Сдвиг: \(model.offset, specifier: "%+.1f") с")
            }
            .onChange(of: model.offset) { _, _ in model.saveSettings(); WidgetCenter.shared.reloadAllTimelines() }
        }
    }

    private var spicySection: some View {
        Section {
            Toggle("Spicy Lyrics", isOn: $model.spicyEnabled)
                .onChange(of: model.spicyEnabled) { _, _ in
                    model.saveSettings(); model.clearLyricsCache(); Task { await model.refresh() }
                }
            if model.spicyEnabled {
                SecureField(Secrets.spicyAPIKey.isEmpty ? "Ключ sl_pk_…" : "Свой ключ (необязательно)", text: $model.spicyKey)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .onSubmit { model.saveSettings(); model.clearLyricsCache(); Task { await model.refresh() } }
                if !model.spicyStatus.isEmpty {
                    Text("Ответ сервера: \(model.spicyStatus)").font(.footnote).foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Источник")
        } footer: {
            Text("Тексты Spicy Lyrics Developer API (developers.spicylyrics.org). Если Spicy не нашёл текст, используется LRCLIB. Тексты хранятся не дольше 30 дней.")
        }
    }
}

struct LivePreview: View {
    var np: NowPlaying
    var lines: [LyricLine]
    var offset: Double

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.2)) { ctx in
            let i = LyricsTimeline.index(in: lines, at: np.position(at: ctx.date) + offset)
            let nextIndex = (i ?? -1) + 1
            VStack(alignment: .leading, spacing: 6) {
                if let i, i > 0 { Text(lines[i - 1].text).opacity(0.35) }
                Text(i.map { lines[$0].isInterlude ? "• • •" : lines[$0].text } ?? "• • •")
                    .font(.title3.weight(.heavy))
                if nextIndex < lines.count { Text(lines[nextIndex].text).opacity(0.45) }
            }
            .font(.body.weight(.bold))
            .animation(.easeInOut(duration: 0.25), value: i)
        }
    }
}

struct AttributionView: View {
    var lyrics: Lyrics
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Текст: \(lyrics.source)").font(.caption).foregroundStyle(.green)
            if let u = lyrics.uploader { credit("загрузил", u) }
            if let m = lyrics.maker { credit("синхронизировал", m) }
        }
    }
    @ViewBuilder private func credit(_ label: String, _ c: Credit) -> some View {
        if let s = c.url, let url = URL(string: s) {
            HStack(spacing: 4) { Text(label).foregroundStyle(.secondary); Link(c.name, destination: url) }.font(.caption)
        } else {
            Text("\(label) \(c.name)").font(.caption).foregroundStyle(.secondary)
        }
    }
}
