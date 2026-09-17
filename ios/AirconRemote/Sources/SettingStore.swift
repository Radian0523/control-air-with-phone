import Foundation

// 設定値の正本（ADR-015）。端末にローカル保存し、操作ごとに全項目を送る。
@MainActor
final class SettingStore: ObservableObject {
    private static let key = "lastSetting"

    @Published var setting: Setting {
        didSet {
            if let data = try? JSONEncoder().encode(setting) {
                UserDefaults.standard.set(data, forKey: Self.key)
            }
        }
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode(Setting.self, from: data) {
            setting = saved
        } else {
            setting = .default
        }
    }
}
