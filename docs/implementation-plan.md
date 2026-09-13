# 実装計画

基準日: 2026-09-13  
準拠: [設計](./design.md) §11、[ADR](./adr.md)  
状態: 段階2 進行中（2c のスケッチは作成・コンパイル済み。2a/2b と 2c の実機試験は部材到着後）

設計§11の8段階を、作るもの・作業・ゲートまで落とす。各段階はゲートを通るまで次へ進まない。問題が出たら、その段階で新しく加えた境界から調べる。

## リポジトリ構成

```text
control-air-with-phone/
├ docs/                         設計・ADR・レビュー・本計画・採取記録
├ tools/                        既存の解析スケッチ（ir_dump, ir_led_check, ir_loopback_test）
├ cloudflare/                   Worker + Durable Object（wrangler プロジェクト）
│  ├ wrangler.toml
│  ├ src/index.ts               Worker入口。認証、ルーティング
│  ├ src/home.ts                Durable Object "home"。WebSocket、予約、Alarm
│  ├ src/encoder.ts             encode(setting) -> 36文字。純粋関数
│  ├ src/validate.ts            エアコン設定と executeAt の検証。純粋関数
│  ├ src/auth.ts                SHA-256 + timingSafeEqual
│  └ test/                      vitest
├ firmware/
│  ├ aircon_bridge/             本番ファーム
│  │  ├ aircon_bridge.ino
│  │  ├ secrets.h               SSID・パスワード・接続先・DEVICE_TOKEN（gitignore済み）
│  │  ├ secrets.example.h       雛形
│  │  └ ca_bundle.h             生成した full bundle の C 配列
│  ├ ir_serial_test/            段階2用。USBシリアルから36文字を受けて送信
│  └ ca_bundle/                 cacert.pem、取得日、SHA-256、生成手順のメモ
└ ios/AirconRemote/             SwiftUI アプリ（Xcode プロジェクト）
```

## 段階0. 準備

作業:

- `git init` し、`.gitignore` へ `firmware/**/secrets.h`、`cloudflare/.wrangler/`、`cloudflare/node_modules/`、`ios/**/xcuserdata/` を追加する
- Cloudflare アカウントと wrangler CLI を用意する。Node.js LTS を入れる
- Xcode と Apple ID（無料でよい）を用意する
- 部材を揃える。ESP32ボード、S8050、940nm IR LED ×3、100Ω ×3（予備で68Ω ×3）、220Ω、10kΩ、IR受信モジュール、USBケーブル、テスター

ゲート: 空のリポジトリに docs と tools が入り、`.gitignore` が secrets を除外している。

## 段階1. Encoder（Cloudflare、ネットワークなし）

作るもの:

- `encoder.ts`: 設計§7.1の規則どおりに18バイトを組み、36文字の大文字16進を返す
- `validate.ts`: §5.4 の設定検証（必須、型、範囲、列挙値。未知フィールドは無視）と、§5.2 の `executeAt` 検証（正規形の正規表現、パース、成分一致、現在以前の拒否）。現在時刻は引数で受け取り、テストで固定できるようにする
- `test/encoder.test.ts`: §7.2 の4件。導出ベクトルである旨をコメントに書く
- `test/validate.test.ts`: 各項目の境界値、`executeAt` の不正形式・存在しない日時・現在以前・小数秒付き

ゲート: 4件のテストベクトルと検証テストが全件一致する。

## 段階2. 赤外線（ハードウェアと採取）

### 2a. 実機リモコン採取

- `tools/ir_dump` を焼き、次を採取して `docs/ir-captures.md` に日時・操作・18バイトを記録する
  - 静音（fan quiet）。byte 9 の fan値を規則の5と照合する
  - 暖房 20℃、風量4、風向low。§7.2 の4件目と照合する
  - 電源ONとOFFを含む複数設定。byte 10〜16 が `00 00 00 00 00 10 00` で固定できるか確認する
- 採取値と規則が異なれば、テストを通すために採取値を曲げず、`encoder.ts` と設計§7.1を採取値へ合わせる。変更内容は ADR-008 の結果へ追記する

### 2b. 回路組立と電気試験

- §8.2 の回路を組む。S8050 のピン順をデータシートまたはテスターで確認する
- `tools/ir_led_check` で発光をスマホのインカメラで確認する
- §8.3 の電気試験を実施し、待機中Base LOW、リセット中の消灯、各枝の電流、送信中の3.3Vを測って記録する

### 2c. シリアル試験スケッチ

- `firmware/ir_serial_test`: USBシリアルから1行を読み、36文字・大文字16進のみを受理して `IRsend::send(MITSUBISHI_AC, state, 18)` を呼ぶ。不正入力は捨てて `invalid_frame` を出す
- この検証と変換のコードは本番ファームへそのまま流用するので、関数として切り出す
- 予定設置位置から4件のテストベクトルを送り、エアコンが安定して反応することを確認する

ゲート: 採取と規則が一致（または規則を修正済み）、電気試験合格、設置位置から安定して反応する。

## 段階3. 機器接続（Worker、DO、ファームの骨格）

### 3a. Cloudflare

- `wrangler.toml`: Durable Object binding、`new_sqlite_classes` の migration、observability logs
- `wrangler secret put` で `DEVICE_TOKEN` と `APP_TOKEN` を登録する
- `index.ts`: `/device/ws` は Bearer を `auth.ts` で照合し、失敗は401、成功は `"home"` の DO へ転送する。その他のパスは段階4以降で足す
- `home.ts`: `acceptWebSocket(ws, ["device"])`。受け入れ前に `getWebSockets("device")` の既存接続を閉じる。`webSocketClose` / `webSocketError` で `device_disconnected` を出す。`webSocketMessage` は何もしない
- ログは §5.6 の JSON 1行形式に揃える

### 3b. CA bundle

- `curl.se/ca/cacert.pem` を取得し、取得日と SHA-256 を `firmware/ca_bundle/README.md` に記録する
- core 3.3.11 付属の `gen_crt_bundle.py --input cacert.pem` で `x509_crt_bundle` を生成し、`xxd -i` で `ca_bundle.h` にする

### 3c. ファームウェア

- `aircon_bridge.ino`: §4.1 の状態機械（BOOT → CONNECTING → ONLINE → TEARDOWN → OFF_WAIT）
  - BOOT: GPIO4 を LOW にしてから OUTPUT、`enableCore1WDT()`、`WiFi.persistent(false)`
  - CONNECTING: Wi-Fi 15秒 → 2024-01-01 未満なら NTP 10秒 → `setReconnectInterval(0)`、`beginSslWithBundle()`、`setExtraHeaders("Authorization: Bearer ...")`、最初の `loop()`、直後に `setReconnectInterval(30000)`。15秒で TEARDOWN
  - ONLINE: `enableHeartbeat(30000, 10000, 2)`。TEXT フレームは段階2cの検証関数を通して送信
  - TEARDOWN: `disconnect()` → `WiFi.mode(WIFI_OFF)` → 30秒待機（`loop()` を呼ばない）→ CONNECTING
  - bundle が null または size 0 なら起動時にエラーを出して接続しない
- ログは §4.8 の状態変化だけにする。試験中だけ `ws_connected` 行に free heap を付けるビルドフラグを用意する（本番では無効）

ゲート:

- Worker Logs に `device_connected` が出る
- 誤った DEVICE_TOKEN で 401 になり、ESP32 が30秒周期で再試行する
- 正しいホストで TLS 成功、誤ホスト・自己署名で失敗する
- DO を数分放置して hibernate させた後、`getWebSockets("device")` で接続を取得できる（段階4の `/command` を先に仮実装して確認してもよい）
- TLS 接続の内部ブロック時間と RAM ピークを記録する

## 段階4. 即時操作

作るもの:

- `index.ts`: `POST /command`。APP_TOKEN 照合 → `validate.ts` → DO へ転送
- `home.ts`: `encode()` → `getWebSockets("device")` → 接続なし・閉じている・`send()` 例外なら 503、成功なら 202。ログ `command_sent` / `command_offline`
- ストレージやコードの予期しない例外は 500 と `server_error`

試験（curl）:

- 正常設定で 202、実機が反応する
- 不正設定（範囲外、列挙外、欠落、型違い）で 400
- 誤 APP_TOKEN で 401
- ESP32 電源OFFから十分待った後で 503。直後は 202 になりうることを確認し、§9 の記述と一致することを見る
- 36文字以外を DO から送るデバッグ経路は作らない。不正入力の試験は段階2cのシリアルで済ませる

ゲート: 全 HTTP 結果を再現し、202 で実機が動く。

## 段階5. 障害系

試験:

- AP の電源OFF → ONLINE から heartbeat 不応答で TEARDOWN、AP 復帰後に自動再接続
- ルーター再起動、ISP 断（WAN ケーブル抜き）で同様
- 誤ホスト・誤証明書で接続失敗が30秒周期で続き、再起動しない
- 24時間の接続失敗試験（接続先を誤ホストにする）で heap が減り続けない。free heap 付きビルドで測る
- TLS 接続中に Task WDT が誤発火しない
- 赤外線送信中に AP を切っても送信が完了し、その後 TEARDOWN する

ゲート: 全試験に合格し、記録を `docs/test-log.md` に残す。

## 段階6. iOS アプリ

作るもの:

- 設定画面: Worker URL と APP_TOKEN を入力し、Keychain に保存する。UserDefaults には入れない
- 操作画面: 電源、モード、温度、風量、風向。設定値の正本を端末に保存し、操作ごとに全項目を `POST /command` へ送る
- 結果表示: 202 は「送信要求を受け付けました」。400/401/503/500 は §6 の表の文言
- 通知、ウィジェット、ローカルネットワーク権限は入れない

ゲート: アプリから実機を操作でき、ESP32 を切った状態で 503 の案内が出る。

## 段階7. 予約

作るもの:

- `index.ts`: `GET` / `PUT` / `DELETE /schedule`
- `home.ts`:
  - PUT: `validate.ts` で `executeAt` と設定を検証 → `encode()` → レコード保存 → `setAlarm(executeAt)`。ログ `schedule_set`
  - GET: レコードから `payload` を除いて返す。なければ `null`
  - DELETE: レコードと Alarm を削除。ログ `schedule_deleted`
  - `alarm()`: §5.2 の順序。読む → なければ終了 → 削除して await → 接続中なら1回 `send()` → 失敗は記録して正常終了。読み込み・削除の失敗だけ例外を投げる
- iOS: 予約画面。日時ピッカー → UTC・小数秒なしで送信。GET の表示、DELETE

試験:

- 過去時刻、小数秒付き、存在しない日時（2月30日）で 400 になり Alarm が変わらない
- 置換で古い Alarm が消える
- ESP32 オフラインで発火 → `schedule_fired_offline`、再試行なし
- 削除後・送信前、送信中に例外を注入しても二重送信しない（vitest の workers pool で `alarm()` を直接呼ぶ）

ゲート: 置換、取消、offline 破棄、二重送信なしをすべて確認する。

## 段階8. 設置

- 配線をはんだ付けまたは固定し、USBポートへ手が届く位置に置く
- 設置位置から §8.3 の到達試験を再実施する
- ルーターの電源断→復旧で自動再接続する
- iPhone → Cloudflare → ESP32 の通し操作と予約を各1回実施する
- `docs/test-log.md` に完了条件のチェック結果を残す

ゲート: 設計§10 の完了条件をすべて満たす。

## 進行表

| 段階 | 内容 | 状態 |
|---|---|---|
| 0 | 準備 | 完了（2026-09-13）。部材の到着と wrangler login は別途 |
| 1 | Encoder | 完了（2026-09-13）。25テスト全件一致、typecheck 通過 |
| 2a | 実機リモコン採取 | 記録テンプレートと照合スクリプト作成済み。採取は部材到着後 |
| 2b | 回路組立と電気試験 | 未着手 |
| 2c | シリアル試験スケッチ | スケッチ作成・コンパイル通過・ホストテスト通過。実機試験は部材到着後 |
| 3 | 機器接続 | 未着手 |
| 4 | 即時操作 | 未着手 |
| 5 | 障害系 | 未着手 |
| 6 | iOS | 未着手 |
| 7 | 予約 | 未着手 |
| 8 | 設置 | 未着手 |
