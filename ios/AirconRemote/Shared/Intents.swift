import AppIntents
import Foundation

// App Intents（ADR-023）。ショートカット、Siri、Spotlight、アクションボタン、オートメーション、
// ウィジェット、コントロールセンターから同じ操作を呼べるようにする、iOS 側の「API」。
// アプリ本体とウィジェット拡張の両方にコンパイルする（ウィジェット・コントロールからは拡張側で実行される）。
// 202 は「送信要求を受け付けた」だけであり、機器が動いたとは言わない（ADR-012）。

struct RemoteIntentError: Error, CustomLocalizedStringResourceConvertible {
    let message: String
    var localizedStringResource: LocalizedStringResource { LocalizedStringResource(stringLiteral: message) }
}

// MARK: - 列挙値（ショートカットの選択肢）

extension LightButton: AppEnum {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "照明ボタン"
    static var caseDisplayRepresentations: [LightButton: DisplayRepresentation] = [
        .on: DisplayRepresentation(title: "全灯", image: .init(systemName: "lightbulb.max")),
        .eco: DisplayRepresentation(title: "ECO", image: .init(systemName: "leaf")),
        .mame: DisplayRepresentation(title: "常夜灯", image: .init(systemName: "moon")),
        .off: DisplayRepresentation(title: "消灯", image: .init(systemName: "lightbulb.slash")),
    ]
}

extension Mode: AppEnum {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "運転モード"
    static var caseDisplayRepresentations: [Mode: DisplayRepresentation] = [
        .auto: "自動",
        .cool: "冷房",
        .dry: "ドライ",
        .heat: "暖房",
        .fan: "送風",
    ]
}

extension Fan: AppEnum {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "風量"
    static var caseDisplayRepresentations: [Fan: DisplayRepresentation] = [
        .auto: "自動",
        .one: "1",
        .two: "2",
        .three: "3",
    ]
}

extension Vane: AppEnum {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "風向"
    static var caseDisplayRepresentations: [Vane: DisplayRepresentation] = [
        .auto: "自動",
        .highest: "最上",
        .high: "上",
        .middle: "中央",
        .low: "下",
        .lowest: "最下",
        .swing: "スイング",
    ]
}

// MARK: - 照明

struct LightIntent: AppIntent {
    static var title: LocalizedStringResource = "照明を操作"
    static var description = IntentDescription("天井照明に、全灯・ECO・常夜灯・消灯のどれか1つを1回送ります。")

    @Parameter(title: "ボタン")
    var button: LightButton

    static var parameterSummary: some ParameterSummary {
        Summary("照明を\(\.$button)にする")
    }

    init() {}
    init(button: LightButton) { self.button = button }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let outcome = await RemoteActions.sendLight(button)
        guard outcome.isSuccess else { throw RemoteIntentError(message: outcome.message) }
        return .result(dialog: IntentDialog(stringLiteral: "照明「\(button.label)」の送信要求を受け付けました"))
    }
}

// MARK: - エアコン（即時）

struct AirconOnIntent: AppIntent {
    static var title: LocalizedStringResource = "エアコンを運転"
    static var description = IntentDescription("エアコンを運転します。指定しなかった項目は前回送った設定を使います。")

    @Parameter(title: "モード")
    var mode: Mode?

    @Parameter(title: "温度", description: "16〜31℃")
    var temp: Int?

    @Parameter(title: "風量")
    var fan: Fan?

    @Parameter(title: "風向")
    var vane: Vane?

    static var parameterSummary: some ParameterSummary {
        Summary("エアコンを\(\.$mode)で運転") {
            \.$temp
            \.$fan
            \.$vane
        }
    }

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let setting = try overridingLastSetting(power: true, mode: mode, temp: temp, fan: fan, vane: vane)
        let outcome = await RemoteActions.sendAircon(setting)
        guard outcome.isSuccess else { throw RemoteIntentError(message: outcome.message) }
        return .result(dialog: IntentDialog(stringLiteral: "エアコン（\(Setting.summary(setting))）の送信要求を受け付けました"))
    }
}

struct AirconOffIntent: AppIntent {
    static var title: LocalizedStringResource = "エアコンを停止"
    static var description = IntentDescription("エアコンを停止します。")

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let setting = try overridingLastSetting(power: false)
        let outcome = await RemoteActions.sendAircon(setting)
        guard outcome.isSuccess else { throw RemoteIntentError(message: outcome.message) }
        return .result(dialog: "エアコン停止の送信要求を受け付けました")
    }
}

// MARK: - 予約（最大1件、新規は置き換え。ADR-011）

struct ScheduleAirconIntent: AppIntent {
    static var title: LocalizedStringResource = "エアコンを予約"
    static var description = IntentDescription(
        "指定した時刻にエアコンの設定を送る予約をします。予約は1件だけで、既存の予約は置き換わります。指定しなかった項目は前回送った設定を使います。")

    @Parameter(title: "実行時刻")
    var date: Date

    @Parameter(title: "電源", default: true)
    var power: Bool

    @Parameter(title: "モード")
    var mode: Mode?

    @Parameter(title: "温度", description: "16〜31℃")
    var temp: Int?

    @Parameter(title: "風量")
    var fan: Fan?

    @Parameter(title: "風向")
    var vane: Vane?

    static var parameterSummary: some ParameterSummary {
        Summary("\(\.$date)にエアコンを予約") {
            \.$power
            \.$mode
            \.$temp
            \.$fan
            \.$vane
        }
    }

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard date > Date() else { throw RemoteIntentError(message: "実行時刻は未来の時刻にしてください") }
        let setting = try overridingLastSetting(power: power, mode: mode, temp: temp, fan: fan, vane: vane)
        let record = try await scheduled(RemoteActions.putSchedule(executeAt: date, setting: setting))
        return .result(dialog: IntentDialog(stringLiteral: "予約しました: \(record?.summary ?? Setting.summary(setting))"))
    }
}

struct SleepTimerIntent: AppIntent {
    static var title: LocalizedStringResource = "エアコンのおやすみタイマー"
    static var description = IntentDescription("指定した分数のあとにエアコンを停止する予約をします。既存の予約は置き換わります。")

    @Parameter(title: "何分後", default: 60)
    var minutes: Int

    static var parameterSummary: some ParameterSummary {
        Summary("\(\.$minutes)分後にエアコンを停止")
    }

    init() {}
    init(minutes: Int) { self.minutes = minutes }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let executeAt = SleepTimer.executeAt(minutes: minutes) else {
            throw RemoteIntentError(message: "分数は\(SleepTimer.range.lowerBound)〜\(SleepTimer.range.upperBound)で指定してください")
        }
        let setting = try overridingLastSetting(power: false)
        _ = try await scheduled(RemoteActions.putSchedule(executeAt: executeAt, setting: setting))
        let time = executeAt.formatted(date: .omitted, time: .shortened)
        return .result(dialog: IntentDialog(stringLiteral: "\(minutes)分後（\(time)）にエアコンを停止する予約をしました"))
    }
}

struct CancelScheduleIntent: AppIntent {
    static var title: LocalizedStringResource = "エアコンの予約を取り消す"
    static var description = IntentDescription("エアコンの予約を取り消します。")

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog {
        _ = try await scheduled(RemoteActions.deleteSchedule())
        return .result(dialog: "予約を取り消しました")
    }
}

struct GetScheduleIntent: AppIntent {
    static var title: LocalizedStringResource = "エアコンの予約を確認"
    static var description = IntentDescription("いまのエアコンの予約を文章で返します。予約がなければ「予約なし」を返します。")

    init() {}

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let record = try await scheduled(RemoteActions.getSchedule())
        let text = record?.summary ?? "予約なし"
        return .result(value: text, dialog: IntentDialog(stringLiteral: text))
    }
}

// MARK: - ウィジェット・コントロール用の1タップ操作

/// ウィジェットのボタンとコントロールセンターのボタンが実行する操作
enum QuickAction: String, CaseIterable, Identifiable, Codable {
    case lightOn, lightEco, lightMame, lightOff, airconOn, airconOff
    var id: String { rawValue }

    var label: String {
        switch self {
        case .lightOn: "照明 全灯"
        case .lightEco: "照明 ECO"
        case .lightMame: "照明 常夜灯"
        case .lightOff: "照明 消灯"
        case .airconOn: "エアコン 運転"
        case .airconOff: "エアコン 停止"
        }
    }

    var systemImage: String {
        switch self {
        case .lightOn, .lightEco, .lightMame, .lightOff: lightButton!.systemImage
        case .airconOn: "fan"
        case .airconOff: "power"
        }
    }

    var lightButton: LightButton? {
        switch self {
        case .lightOn: .on
        case .lightEco: .eco
        case .lightMame: .mame
        case .lightOff: .off
        case .airconOn, .airconOff: nil
        }
    }

    func run() async throws {
        let outcome: CommandOutcome
        if let lightButton {
            outcome = await RemoteActions.sendLight(lightButton)
        } else {
            let setting = try overridingLastSetting(power: self == .airconOn)
            outcome = await RemoteActions.sendAircon(setting)
        }
        guard outcome.isSuccess else { throw RemoteIntentError(message: outcome.message) }
    }
}

extension QuickAction: AppEnum {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "操作"
    static var caseDisplayRepresentations: [QuickAction: DisplayRepresentation] = [
        .lightOn: DisplayRepresentation(title: "照明 全灯", image: .init(systemName: "lightbulb.max")),
        .lightEco: DisplayRepresentation(title: "照明 ECO", image: .init(systemName: "leaf")),
        .lightMame: DisplayRepresentation(title: "照明 常夜灯", image: .init(systemName: "moon")),
        .lightOff: DisplayRepresentation(title: "照明 消灯", image: .init(systemName: "lightbulb.slash")),
        .airconOn: DisplayRepresentation(title: "エアコン 運転（前回の設定）", image: .init(systemName: "fan")),
        .airconOff: DisplayRepresentation(title: "エアコン 停止", image: .init(systemName: "power")),
    ]
}

struct QuickActionIntent: AppIntent {
    static var title: LocalizedStringResource = "おうちリモコンの操作"
    // ショートカットには個別のインテントを出すので、これはウィジェット・コントロール専用
    static var isDiscoverable: Bool = false

    @Parameter(title: "操作")
    var action: QuickAction

    init() {}
    init(action: QuickAction) { self.action = action }

    func perform() async throws -> some IntentResult {
        try await action.run()
        return .result()
    }
}

// MARK: - 共通

enum SleepTimer {
    static let range = 1...720

    static func executeAt(minutes: Int, now: Date = Date()) -> Date? {
        guard range.contains(minutes) else { return nil }
        return now.addingTimeInterval(TimeInterval(minutes * 60))
    }
}

private func overridingLastSetting(
    power: Bool? = nil, mode: Mode? = nil, temp: Int? = nil, fan: Fan? = nil, vane: Vane? = nil
) throws -> Setting {
    do {
        return try SharedStore.lastSetting.overriding(power: power, mode: mode, temp: temp, fan: fan, vane: vane)
    } catch {
        throw RemoteIntentError(message: "温度は\(Setting.tempRange.lowerBound)〜\(Setting.tempRange.upperBound)℃で指定してください")
    }
}

private func scheduled<T: Equatable>(_ outcome: ScheduleOutcome<T>) throws -> T {
    if case .ok(let value) = outcome { return value }
    throw RemoteIntentError(message: outcome.message ?? "予約の操作に失敗しました")
}
