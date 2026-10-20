import Foundation
import SwiftUI
import UIKit

struct WidgetLine: Codable, Hashable {
    var s: Double
    var e: Double
    var t: String
    var i: Bool
}

struct WidgetState: Codable {
    var v: Int?
    var titleLabel: String?
    var capturedAt: Double
    var trackKey: String?
    var title: String?
    var artist: String?
    var duration: Double?
    var position: Double?
    var playing: Bool?
    var hasArtwork: Bool?
    var status: String
    var message: String?
    var palette: [String]?
    var base: String?
    var lines: [WidgetLine]?
    var synced: Bool?
    var footer: String?

    var capturedDate: Date { Date(timeIntervalSince1970: capturedAt) }
    var isPlaying: Bool { playing ?? false }

    func position(at date: Date) -> Double {
        let p = position ?? 0
        guard isPlaying else { return p }
        return min(p + date.timeIntervalSince(capturedDate), duration ?? .greatestFiniteMagnitude)
    }

    func date(at position: Double) -> Date {
        capturedDate.addingTimeInterval(position - (self.position ?? 0))
    }
}

enum WidgetStore {
    static let defaultGroup = "group.com.spotify.client.widget"
    static let folder = "SpicyLyricsWidget"

    static var directory: URL? {
        var groups: [String] = []
        let host = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent()
        if let app = Bundle(url: host), let g = app.object(forInfoDictionaryKey: "ALTAppGroups") as? [String] { groups += g }
        if let g = Bundle.main.object(forInfoDictionaryKey: "ALTAppGroups") as? [String] { groups += g }
        groups.append(defaultGroup)
        for g in groups {
            if let u = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: g) {
                return u.appendingPathComponent(folder, isDirectory: true)
            }
        }
        return nil
    }

    static func load() -> WidgetState? {
        guard let dir = directory, let data = try? Data(contentsOf: dir.appendingPathComponent("state.json")) else { return nil }
        return try? JSONDecoder().decode(WidgetState.self, from: data)
    }

    static func artwork() -> UIImage? {
        guard let dir = directory else { return nil }
        return UIImage(contentsOfFile: dir.appendingPathComponent("artwork.jpg").path)
    }
}

extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        if s.count != 6 { s = "333333" }
        let v = UInt64(s, radix: 16) ?? 0x333333
        self.init(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}
