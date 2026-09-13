# ios

SwiftUI アプリ `AirconRemote`（design.md §6）。段階6で Xcode プロジェクトをここに作る。

- APP_TOKEN と Worker URL は設定画面から入力し Keychain に保存する。UserDefaults、ソース、リポジトリへ置かない
- 操作ごとに全設定を `POST /command` へ送る
- 予約の `executeAt` は UTC・小数秒なしの `YYYY-MM-DDTHH:mm:ssZ` で送る
