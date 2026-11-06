import AppIntents
import SwiftUI
import WidgetKit

// コントロール（iOS 18）。コントロールセンター、ロック画面の左右下のボタン、アクションボタンに置ける。
// 照明・エアコンとも今の状態は取れないので、トグルではなく1回送るボタンにする（ADR-012, 022）。

struct QuickActionControlConfig: ControlConfigurationIntent {
    static var title: LocalizedStringResource = "操作を選ぶ"

    @Parameter(title: "操作", default: .lightOn)
    var action: QuickAction

    init() {}

    func perform() async throws -> some IntentResult { .result() }
}

struct QuickActionControlProvider: AppIntentControlValueProvider {
    func previewValue(configuration: QuickActionControlConfig) -> QuickAction {
        configuration.action
    }

    func currentValue(configuration: QuickActionControlConfig) async throws -> QuickAction {
        configuration.action
    }
}

struct QuickActionControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(
            kind: "local.aircon.AirconRemote.QuickActionControl",
            provider: QuickActionControlProvider()
        ) { action in
            ControlWidgetButton(action: QuickActionIntent(action: action)) {
                Label(action.label, systemImage: action.systemImage)
            }
        }
        .displayName("おうちリモコン")
        .description("照明やエアコンの操作を1つ選んで、押すだけで送ります。")
        .promptsForUserConfiguration()
    }
}

struct SleepTimerControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "local.aircon.AirconRemote.SleepTimerControl") {
            ControlWidgetButton(action: SleepTimerIntent(minutes: 60)) {
                Label("60分後にエアコン停止", systemImage: "moon.zzz")
            }
        }
        .displayName("おやすみタイマー")
        .description("60分後にエアコンを停止する予約をします（既存の予約は置き換わります）。")
    }
}
