import Foundation
import Security

// APP_TOKEN などの保管先（design.md §6、ADR-013, 023）。UserDefaults には入れない。
// アプリとウィジェット拡張で共有するため、共有アクセスグループ（<Team ID>.local.aircon.shared）に置く。
// App Groups は無料 Apple ID で安定して使えないので使わない（ADR-023）。
enum Keychain {
    private static let service = "local.aircon.AirconRemote"

    /// 共有アクセスグループ。Info.plist の AppIdentifierPrefix（= "<Team ID>."）から組み立てる。
    /// 署名なし（Team 未選択のシミュレータなど）では nil になり、各ターゲット既定のグループを使う。
    static let sharedAccessGroup: String? = {
        guard let prefix = Bundle.main.object(forInfoDictionaryKey: "AppIdentifierPrefix") as? String,
            !prefix.isEmpty, !prefix.hasPrefix("$(")
        else { return nil }
        return prefix + "local.aircon.shared"
    }()

    private static func baseQuery(for key: String, group: String?) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        if let group { query[kSecAttrAccessGroup as String] = group }
        return query
    }

    static func save(_ value: String, for key: String) throws {
        // グループ指定なしの削除は、参照できる全グループの同名項目（旧版の項目を含む）を消す
        SecItemDelete(baseQuery(for: key, group: nil) as CFDictionary)
        var status = add(value, for: key, group: sharedAccessGroup)
        if status == errSecMissingEntitlement, sharedAccessGroup != nil {
            // 署名設定の都合で共有グループの権限が無い場合でも、アプリ単体では動くようにする
            status = add(value, for: key, group: nil)
        }
        guard status == errSecSuccess else { throw KeychainError.status(status) }
    }

    private static func add(_ value: String, for key: String, group: String?) -> OSStatus {
        var attributes = baseQuery(for: key, group: group)
        attributes[kSecValueData as String] = Data(value.utf8)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(attributes as CFDictionary, nil)
    }

    static func load(for key: String) -> String? {
        // 共有グループを優先し、無ければ旧版（アプリ既定グループ）の項目を探す
        if let group = sharedAccessGroup, let value = copy(baseQuery(for: key, group: group)) {
            return value
        }
        return copy(baseQuery(for: key, group: nil))
    }

    /// 旧版で共有グループ外に保存した項目を共有グループへ移す。アプリ起動時に呼ぶ
    static func migrateToSharedGroup(for key: String) {
        guard let group = sharedAccessGroup, copy(baseQuery(for: key, group: group)) == nil,
            let legacy = copy(baseQuery(for: key, group: nil))
        else { return }
        try? save(legacy, for: key)
    }

    static func delete(for key: String) {
        SecItemDelete(baseQuery(for: key, group: nil) as CFDictionary)
    }

    private static func copy(_ base: [String: Any]) -> String? {
        var query = base
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
            let data = item as? Data
        else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    enum KeychainError: Error { case status(OSStatus) }
}
