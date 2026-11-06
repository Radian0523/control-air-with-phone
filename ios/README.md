# ios

SwiftUI アプリ `AirconRemote`（design.md §6）。

## 構成

```text
AirconRemote/
├ project.yml              xcodegen の定義（xcodeproj はここから生成。コミットしない）
├ Sources/                 アプリ本体だけ
│  ├ AirconRemoteApp.swift  エントリ（起動時に保存場所を共有グループへ移す）
│  ├ AppShortcuts.swift     App Shortcuts（Siri・Spotlight・アクションボタンのフレーズ）
│  ├ AppConfig.swift        Worker URL と APP_TOKEN（画面用）
│  ├ SettingStore.swift     設定値の正本（ADR-015）
│  ├ ContentView.swift      操作画面
│  └ SettingsView.swift     設定画面
├ Shared/                  アプリ本体とウィジェット拡張の両方に入れる
│  ├ Models.swift           Mode / Fan / Vane / Setting / LightButton（§5.4 と同じ文字列）
│  ├ APIClient.swift        POST /command・/light と HTTP → 表示文言の対応（§6 の表）
│  ├ ScheduleAPI.swift      GET / PUT / DELETE /schedule
│  ├ Keychain.swift         Keychain（共有アクセスグループ）
│  ├ SharedStore.swift      拡張と共有する値（APP_TOKEN、URL、前回の設定、最後の送信結果）
│  ├ RemoteActions.swift    どこから操作しても通る共通の入口（結果の記録とウィジェット更新）
│  └ Intents.swift          App Intents（ショートカット・Siri・ウィジェット・コントロールの操作）
├ Widgets/                 ウィジェット拡張（iOS 18 以上）
│  ├ LightWidget.swift      照明 4 ボタン
│  ├ AirconWidget.swift     エアコン運転・停止、予約表示、60 分タイマー
│  ├ QuickActionWidget.swift ロック画面などの 1 ボタン
│  └ Controls.swift         コントロールセンター / ロック画面 / アクションボタンのボタン
└ Tests/                    JSON 形式・文言方針・インテントの共通ロジックのユニットテスト
```

## 開く・ビルドする

```bash
cd ios/AirconRemote && xcodegen generate && open AirconRemote.xcodeproj
```

実機で動かすときは Xcode の Signing & Capabilities で、`AirconRemote` と `AirconWidgets` の両方に同じ自分の Team を選ぶ（無料 Apple ID 可。7日ごとに再インストールが必要。ADR-009）。Team が違うと Keychain を共有できず、ウィジェットが「未設定」のままになる。

## 方針

- APP_TOKEN は設定画面から入力し Keychain に保存する。UserDefaults、ソース、リポジトリへ置かない
- 操作ごとに全設定を `POST /command` へ送る。fan は文字列 `"1"`〜`"3"`
- 202 は「送信要求を受け付けました」と表示し、エアコンが動いたとは表示しない
- 予約の `executeAt` は UTC・小数秒なしの `YYYY-MM-DDTHH:mm:ssZ` で送る（段階7で追加）
- ショートカット・Siri・ウィジェット・コントロールは App Intents で作る（ADR-023、design.md §6.1）
- アプリと拡張の共有は Keychain の共有アクセスグループ。App Groups は無料 Apple ID で不安定なので使わない
- 通知、Live Activity、ローカルネットワーク権限は使わない
