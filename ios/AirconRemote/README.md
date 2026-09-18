# AirconRemote (iOS)

SwiftUI 製の操作アプリ。操作画面（設定値・今すぐ送る・一発予約を1画面に集約）と設定画面の 2 画面。

## 生成と実行

```bash
brew install xcodegen
cd ios/AirconRemote
xcodegen generate
open AirconRemote.xcodeproj
```

`AirconRemote.xcodeproj` は生成物なので gitignore 済み。テストは `AirconRemoteTests`（12 件）。

## 保管場所

| データ | 場所 | 理由 |
|---|---|---|
| APP_TOKEN | Keychain | UserDefaults や設定ファイルには置かない |
| Worker の URL | UserDefaults | 秘密ではない |
| 最後に送った設定 | UserDefaults | エアコン状態の正本はアプリ側（ADR-015） |

## 送信の扱い

- `POST /command` の 202 は「Worker が受け付けて機器へ送った」であり、エアコンが受理した保証ではない（ADR-012）。画面には「送信要求を受け付けました」と出す
- 503 `device_offline` は ESP32 が未接続。設計 §9 の障害判断表を参照
- 予約の `executeAt` は UTC の秒精度 `YYYY-MM-DDTHH:MM:SSZ`。`ExecuteAtFormat` で生成
