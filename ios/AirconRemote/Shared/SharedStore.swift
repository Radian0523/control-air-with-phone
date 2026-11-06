import Foundation

// アプリとウィジェット拡張（ウィジェット、コントロール、ショートカットの実行先）で共有する値（ADR-023）。
// 共有手段は Keychain の共有アクセスグループだけ。App Groups の UserDefaults は使わない。
enum SharedStore {
    static let defaultBaseURLString = "https://aircon.aircon-worker.workers.dev"

    private enum Key {
        static let token = "APP_TOKEN"
        static let baseURL = "workerBaseURL"
        static let lastSetting = "lastSetting"
        static let lastResult = "lastResult"
    }

    // MARK: 接続設定

    static var baseURLString: String {
        get { Keychain.load(for: Key.baseURL) ?? defaultBaseURLString }
        set { try? Keychain.save(newValue, for: Key.baseURL) }
    }

    static var baseURL: URL? { validatedURL(baseURLString) }

    static func validatedURL(_ string: String) -> URL? {
        guard let url = URL(string: string.trimmingCharacters(in: .whitespacesAndNewlines)),
            url.scheme == "https", url.host != nil
        else { return nil }
        return url
    }

    static var token: String? { Keychain.load(for: Key.token) }

    static func saveToken(_ token: String) throws {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            Keychain.delete(for: Key.token)
        } else {
            try Keychain.save(trimmed, for: Key.token)
        }
    }

    /// URL と APP_TOKEN がそろっていれば API クライアントを返す
    static func client() -> APIClient? {
        guard let url = baseURL, let token else { return nil }
        return APIClient(baseURL: url, token: token)
    }

    // MARK: エアコン設定の正本（ADR-015）

    static var lastSetting: Setting {
        get { decode(Setting.self, Key.lastSetting) ?? .default }
        set { encode(newValue, Key.lastSetting) }
    }

    // MARK: 最後の送信結果（ウィジェットに出す）

    static var lastResult: LastResult? {
        get { decode(LastResult.self, Key.lastResult) }
        set {
            if let newValue { encode(newValue, Key.lastResult) } else { Keychain.delete(for: Key.lastResult) }
        }
    }

    // MARK: 旧版からの移行

    /// 旧版は URL と設定を UserDefaults、APP_TOKEN をアプリ既定の Keychain グループに置いていた。
    /// アプリ起動時に1回呼び、拡張からも読める共有グループへ移す。
    static func migrateLegacyStorage(defaults: UserDefaults = .standard) {
        Keychain.migrateToSharedGroup(for: Key.token)
        for key in [Key.baseURL, Key.lastSetting, Key.lastResult] {
            Keychain.migrateToSharedGroup(for: key)
        }
        if let url = defaults.string(forKey: Key.baseURL) {
            if Keychain.load(for: Key.baseURL) == nil { baseURLString = url }
            defaults.removeObject(forKey: Key.baseURL)
        }
        if let data = defaults.data(forKey: Key.lastSetting) {
            if Keychain.load(for: Key.lastSetting) == nil, let saved = try? JSONDecoder().decode(Setting.self, from: data) {
                lastSetting = saved
            }
            defaults.removeObject(forKey: Key.lastSetting)
        }
    }

    // MARK: JSON ⇄ Keychain

    private static func decode<T: Decodable>(_ type: T.Type, _ key: String) -> T? {
        guard let json = Keychain.load(for: key) else { return nil }
        return try? JSONDecoder().decode(type, from: Data(json.utf8))
    }

    private static func encode(_ value: some Encodable, _ key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? Keychain.save(String(decoding: data, as: UTF8.self), for: key)
    }
}

/// 最後に送った操作の結果。ウィジェットで「いつ・何を・どうなったか」を1行で出す
struct LastResult: Codable, Equatable {
    var action: String  // 例: "照明 全灯"、"エアコン 冷房 26℃"
    var success: Bool
    var message: String
    var at: Date
}
