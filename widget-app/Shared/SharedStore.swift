import Foundation

/// Общее хранилище приложения и виджета (App Group).
/// SideStore/AltStore переименовывают группу (добавляют Team ID) и пишут реальное имя
/// в Info.plist (ALTAppGroups) — поэтому имя группы ищем, а не хардкодим.
enum SharedStore {
    static let defaultGroup = "group.com.mapix30.lyricswidget"

    static let groupID: String = {
        var candidates: [String] = []
        if let g = Bundle.main.object(forInfoDictionaryKey: "ALTAppGroups") as? [String] { candidates += g }
        // из расширения смотрим и Info.plist основного приложения (…/X.app/PlugIns/Y.appex)
        let appURL = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent()
        if appURL.pathExtension == "app", let app = Bundle(url: appURL),
           let g = app.object(forInfoDictionaryKey: "ALTAppGroups") as? [String] { candidates += g }
        candidates.append(defaultGroup)
        for g in candidates where FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: g) != nil {
            return g
        }
        return defaultGroup
    }()

    static var hasGroup: Bool {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID) != nil
    }

    static var defaults: UserDefaults { UserDefaults(suiteName: groupID) ?? .standard }

    static var directory: URL {
        let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID)
            ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("LyricsWidget", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func save<T: Encodable>(_ value: T, as name: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: directory.appendingPathComponent(name), options: .atomic)
    }

    static func load<T: Decodable>(_ type: T.Type, from name: String) -> T? {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent(name)) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    // MARK: - Настройки

    static var clientID: String {
        get { defaults.string(forKey: "clientID") ?? "" }
        set { defaults.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "clientID") }
    }

    /// Сдвиг синхронизации в секундах (+ = текст раньше).
    static var offset: Double {
        get { defaults.double(forKey: "offset") }
        set { defaults.set(newValue, forKey: "offset") }
    }
}
