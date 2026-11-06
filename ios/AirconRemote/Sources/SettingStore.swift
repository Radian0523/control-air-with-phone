import Foundation

// 設定値の正本（ADR-015）。端末に保存し、操作ごとに全項目を送る。
// ショートカットやウィジェットから送った設定も同じ場所（SharedStore）に入るので、前面に戻るたびに読み直す。
@MainActor
final class SettingStore: ObservableObject {
    @Published var setting: Setting {
        didSet {
            if setting != oldValue { SharedStore.lastSetting = setting }
        }
    }

    init() {
        setting = SharedStore.lastSetting
    }

    func reload() {
        let saved = SharedStore.lastSetting
        if saved != setting { setting = saved }
    }
}
