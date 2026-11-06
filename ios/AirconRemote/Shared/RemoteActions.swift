import Foundation
import WidgetKit

// アプリ画面・ショートカット・Siri・ウィジェット・コントロールが共通で使う操作の入口。
// どこから操作しても、結果の記録とウィジェットの更新を同じ形で行う。
enum RemoteActions {
    // MARK: 即時操作

    static func sendLight(_ button: LightButton) async -> CommandOutcome {
        guard let client = SharedStore.client() else { return finish(.notConfigured, action: "照明 \(button.label)") }
        return finish(await client.sendLight(button), action: "照明 \(button.label)")
    }

    /// 全設定を送る（ADR-015）。受け付けられたら、その設定を正本として保存する
    static func sendAircon(_ setting: Setting) async -> CommandOutcome {
        let action = "エアコン \(Setting.summary(setting))"
        guard let client = SharedStore.client() else { return finish(.notConfigured, action: action) }
        let outcome = await client.sendCommand(setting)
        if outcome.isSuccess { SharedStore.lastSetting = setting }
        return finish(outcome, action: action)
    }

    // MARK: 予約（最大1件、置き換え。ADR-011）

    static func getSchedule() async -> ScheduleOutcome<ScheduleRecord?> {
        guard let client = SharedStore.client() else { return .notConfigured }
        return await client.getSchedule()
    }

    static func putSchedule(executeAt: Date, setting: Setting) async -> ScheduleOutcome<ScheduleRecord?> {
        guard let client = SharedStore.client() else { return .notConfigured }
        let outcome = await client.putSchedule(executeAt: executeAt, setting: setting)
        if case .ok = outcome { WidgetCenter.shared.reloadAllTimelines() }
        return outcome
    }

    static func deleteSchedule() async -> ScheduleOutcome<Bool> {
        guard let client = SharedStore.client() else { return .notConfigured }
        let outcome = await client.deleteSchedule()
        if case .ok = outcome { WidgetCenter.shared.reloadAllTimelines() }
        return outcome
    }

    // MARK: -

    private static func finish(_ outcome: CommandOutcome, action: String) -> CommandOutcome {
        SharedStore.lastResult = LastResult(action: action, success: outcome.isSuccess, message: outcome.message, at: Date())
        WidgetCenter.shared.reloadAllTimelines()
        return outcome
    }
}

extension Setting {
    enum OverrideError: Error, Equatable {
        case tempOutOfRange(Int)
    }

    /// 前回の設定を土台に、指定された項目だけ差し替える（ショートカットの省略可能な引数用）
    func overriding(
        power: Bool? = nil, mode: Mode? = nil, temp: Int? = nil, fan: Fan? = nil, vane: Vane? = nil
    ) throws -> Setting {
        var s = self
        if let power { s.power = power }
        if let mode { s.mode = mode }
        if let temp {
            guard Setting.tempRange.contains(temp) else { throw OverrideError.tempOutOfRange(temp) }
            s.temp = temp
        }
        if let fan { s.fan = fan }
        if let vane { s.vane = vane }
        return s
    }
}

extension ScheduleRecord {
    /// 「11/6 23:00 冷房 26℃ …」の形の1行要約（端末のタイムゾーン）
    var summary: String {
        let when = ExecuteAtFormat.date(from: executeAt).map { $0.formatted(date: .abbreviated, time: .shortened) } ?? executeAt
        return "\(when) \(Setting.summary(setting))"
    }
}
