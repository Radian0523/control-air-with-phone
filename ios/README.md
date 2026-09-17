# ios

SwiftUI アプリ `AirconRemote`（design.md §6）。

## 構成

```text
AirconRemote/
├ project.yml              xcodegen の定義（xcodeproj はここから生成。コミットしない）
├ Sources/
│  ├ AirconRemoteApp.swift  エントリ
│  ├ Models.swift           Mode / Fan / Vane / Setting（§5.4 と同じ文字列）
│  ├ Keychain.swift         APP_TOKEN の保管
│  ├ AppConfig.swift        Worker URL（UserDefaults）と APP_TOKEN（Keychain）
│  ├ SettingStore.swift     設定値の正本（ADR-015）。端末に保存
│  ├ APIClient.swift        POST /command と HTTP → 表示文言の対応（§6 の表）
│  ├ ContentView.swift      操作画面
│  └ SettingsView.swift     設定画面
└ Tests/                    JSON 形式と文言方針のユニットテスト
```

## 開く・ビルドする

```bash
cd ios/AirconRemote && xcodegen generate && open AirconRemote.xcodeproj
```

実機で動かすときは Xcode の Signing & Capabilities で自分の Team を選ぶ（無料 Apple ID 可。7日ごとに再インストールが必要。ADR-009）。

## 方針

- APP_TOKEN は設定画面から入力し Keychain に保存する。UserDefaults、ソース、リポジトリへ置かない
- 操作ごとに全設定を `POST /command` へ送る。fan は文字列 `"1"`〜`"3"`
- 202 は「送信要求を受け付けました」と表示し、エアコンが動いたとは表示しない
- 予約の `executeAt` は UTC・小数秒なしの `YYYY-MM-DDTHH:mm:ssZ` で送る（段階7で追加）
- 通知、ウィジェット、ローカルネットワーク権限は使わない
