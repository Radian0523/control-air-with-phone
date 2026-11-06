import AppIntents

// App Shortcuts（ADR-023）。インストールするだけで、ショートカット App・Siri・Spotlight・
// アクションボタンに出る。フレーズには必ずアプリ名（おうちリモコン）を含める。
struct OuchiRemoteShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LightIntent(),
            phrases: [
                "\(.applicationName)で照明を\(\.$button)にして",
                "\(.applicationName)で照明を\(\.$button)",
                "\(.applicationName)の照明",
            ],
            shortTitle: "照明",
            systemImageName: "lightbulb"
        )
        AppShortcut(
            intent: AirconOnIntent(),
            phrases: [
                "\(.applicationName)でエアコンをつけて",
                "\(.applicationName)でエアコンを運転",
            ],
            shortTitle: "エアコン運転",
            systemImageName: "fan"
        )
        AppShortcut(
            intent: AirconOffIntent(),
            phrases: [
                "\(.applicationName)でエアコンを消して",
                "\(.applicationName)でエアコンを止めて",
            ],
            shortTitle: "エアコン停止",
            systemImageName: "power"
        )
        AppShortcut(
            intent: SleepTimerIntent(),
            phrases: [
                "\(.applicationName)でおやすみタイマー",
                "\(.applicationName)でエアコンのタイマー",
            ],
            shortTitle: "おやすみタイマー",
            systemImageName: "moon.zzz"
        )
        AppShortcut(
            intent: GetScheduleIntent(),
            phrases: [
                "\(.applicationName)の予約を確認",
                "\(.applicationName)の予約は",
            ],
            shortTitle: "予約を確認",
            systemImageName: "clock"
        )
        AppShortcut(
            intent: CancelScheduleIntent(),
            phrases: [
                "\(.applicationName)の予約を取り消して",
            ],
            shortTitle: "予約を取り消す",
            systemImageName: "clock.badge.xmark"
        )
    }
}
