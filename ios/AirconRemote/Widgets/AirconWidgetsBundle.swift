import SwiftUI
import WidgetKit

// ウィジェット拡張の入口（ADR-023）。拡張は iOS 18 以上（コントロールのため）。アプリ本体は iOS 17 のまま。
@main
struct AirconWidgetsBundle: WidgetBundle {
    var body: some Widget {
        LightWidget()
        AirconWidget()
        QuickActionWidget()
        QuickActionControl()
        SleepTimerControl()
    }
}
