# エアコン遠隔操作 — 設計

状態: 実装前  
基準日: 2026-09-13  
原本: [Notionエクスポート](./notion-design-export.md)  
設計判断: [ADR](./adr.md)

この文書は、実装が従う現在の仕様だけを記載する。判断理由や不採用案はADRに分離する。

## 1. 目的とスコープ

### 実装するもの

- iPhoneからエアコンを即時操作する
- 外出先から操作する
- 電源、モード、温度、風量、風向を指定する
- 一発予約を1件だけ設定・確認・取消する

### 実装しないもの

- 通知、音声操作、ウィジェット、Apple Watch
- LAN直通経路、ポート開放、VPN
- 繰り返し予約
- エアコンが命令を受理したことの検出
- OTA、遠隔ファーム更新
- Wi-Fi再設定画面やAPフォールバック

## 2. 制約

- 家に常設する機器はESP32だけとする
- エアコンの赤外線通信は片方向で、エアコンは状態を返さない
- 赤外線を送信できるのはESP32だけとする
- ファームウェア変更時はUSBでESP32を書き換える
- 設置後もESP32のUSBポートへ手が届くようにする

## 3. 全体構成

```text
iPhone（SwiftUI）
   │ HTTPS
   ▼
Cloudflare Worker（認証・API）
   │
   ▼
Durable Object "home"（1個）
   ├ 18バイトの赤外線データを生成
   ├ 一発予約を1件保持
   └ ESP32のWebSocketを1本保持
   │ WebSocket over TLS
   │ 36文字の大文字16進テキスト
   ▼
ESP32
   │ GPIO4から赤外線送信
   ▼
三菱電機エアコン
```

家庭のルーターには受信用ポートを開けない。ESP32からCloudflareへ外向きの接続を張る。

### 責務

| 要素 | 持つもの | 持たないもの |
|---|---|---|
| ESP32 | 接続維持、入力検証、赤外線送信、TLS検証用の概算UTC | エアコン状態、予約、設定の意味 |
| Durable Object | WebSocket、エンコード、一発予約、時刻 | エアコンの現在状態 |
| Worker | 認証境界、外部API | エアコン状態 |
| iOSアプリ | UI、設定値の正本 | 赤外線形式 |

## 4. ESP32

### 4.1 動作

```text
BOOT
  → gpio_set_level(GPIO4, 0) で出力レジスタをLOWにしてからOUTPUT化
  → enableCore1WDT() と core 1 の idle hook 登録
  → WiFi.persistent(false)
  → CONNECTING（Wi-Fi → 必要時だけNTP → WebSocket）
  → ONLINE（36文字を受信したら同期的に赤外線送信）

接続失敗 / WebSocket close / heartbeat不応答
  → TEARDOWN
  → Wi-Fi OFF
  → 30秒待機
  → CONNECTING
```

ESP32の責務は次の3つだけとする。

1. Wi-Fiへ接続する
2. CloudflareとのWebSocket over TLS接続を維持する
3. 正しい36文字を18バイトへ変換し、赤外線で送信する

### 4.2 持たない機能

- アプリ独自のNVS永続データ
- JSONパーサー
- コマンドID、アプリ用応答、エラーコード
- アプリケーションキュー、再送、busyフラグ
- 独自FreeRTOSタスク、タスク間キュー
- タイマー、タイムゾーン、繰り返し規則
- HTTPサーバー、HTTPクライアント、mDNS
- OTA

Wi-Fi資格情報、Cloudflare接続先、DEVICE_TOKEN、CA bundleはファームウェア定数とする。`WiFi.mode()`または`WiFi.begin()`を初めて呼ぶ前に`WiFi.persistent(false)`を1回呼び、Wi-Fiドライバによる資格情報のNVS保存を無効にする。

### 4.3 機器向けメッセージ

CloudflareからESP32へ送るアプリケーションメッセージは、WebSocketのテキストフレーム1種類だけとする。

```text
23CB260100201008325800000000001000E7
```

| 規則 | 値 |
|---|---|
| 長さ | 36文字ちょうど（18バイト） |
| 文字 | ASCII `0`〜`9`、`A`〜`F`のみ |
| 赤外線方式 | `MITSUBISHI_AC`固定 |
| アプリ用応答 | なし |
| 不正入力 | 赤外線送信せず、応答せず捨てる |

小文字、空白、改行、長さ違い、binary frameは不正入力とする。固定長`uint8_t state[18]`へ変換し、`IRsend::send(MITSUBISHI_AC, state, 18)`を呼ぶ。

WebSocketプロトコルのpongはライブラリへ任せる。これはアプリケーションメッセージには数えない。

### 4.4 赤外線送信

- Arduinoの通常の`loop()`から呼ばれたWebSocket受信コールバック内で同期送信する
- 送信中は約0.5秒`webSocket.loop()`が進まないことを許容する
- 独自タスクや独自キューへ渡さない
- 複数フレームは1フレームの処理完了後に次を処理する
- 割り込みを禁止しない
- 歪みや未達を検知せず、命令を自動再送しない
- 起動時にTask WDTを次の3点セットで有効にする。どれか1つ欠けると5秒で再起動する
  1. `enableCore1WDT()` でIDLE1を監視対象に追加する
  2. `esp_register_freertos_idle_hook_for_cpu(hook, 1)` で、IDLE1が走るたびに`esp_task_wdt_reset()`を呼ぶhookを登録する
  3. `loop()`の末尾で`delay(1)`を呼び、IDLE1へCPUを譲る

core 3.3.11は`CONFIG_ESP_TASK_WDT_PANIC=y`、timeout 5秒、`CONFIG_ESP_TASK_WDT_CHECK_IDLE_TASK_CPU1`無効である。このため`enableCore1WDT()`はIDLE1を監視対象に追加するだけで、ESP-IDFが本来IDLEタスクへ仕込むidle hookを登録しない。hookがないとIDLE1は永久にリセットできない。またArduinoの`loopTask`は`loop()`を休みなく呼び続けるため、`loop()`が譲らないとIDLE1自体が走れない。赤外線送信の約0.5秒とTLS handshakeのソケット待ちはこの5秒に収まる。

core 3.xの`digitalWrite()`は`pinMode()`より前に呼ぶと周辺管理に未登録のため何もしない。起動時の出力ラッチ初期化にはIDFの`gpio_set_level()`を使う。

赤外線送信中にWebSocketが切れた場合は送信を完了し、その後TEARDOWNへ進む。

### 4.5 ネットワーク

接続順序とアプリ側の期限は次のとおり。

1. Wi-Fi接続: 15秒
2. システム時刻が2024-01-01 UTC未満の場合だけNTP同期: 10秒
3. WebSocket over TLS接続: 15秒

NTPサーバーは次の3つを使う。

- `time.cloudflare.com`
- `time.google.com`
- `pool.ntp.org`

arduino-esp32 3.3.11のTLS handshakeは同期処理で、内部呼び出しが既定120秒まで停止しうる。この間は上記15秒を強制できないため、実機で停止時間を測る。

接続失敗、WebSocket close、heartbeat不応答はすべて同じ処理とする。

1. `webSocket.disconnect()`とクライアントの後始末
2. `WiFi.mode(WIFI_OFF)`
3. 30秒待機
4. Wi-Fi接続から再実行

`CONNECTING`と`ONLINE`の間だけ`webSocket.loop()`を呼び、`OFF_WAIT`中は呼ばない。TEARDOWNでは`webSocket.disconnect()`を先に呼んでからWi-FiをOFFにする。これにより、arduinoWebSockets自身の再接続処理はOFF_WAIT中に動かない。通信失敗ではESP32を再起動しない。

WebSocket接続は1回の`CONNECTING`につき1回だけ試す。`CONNECTING`へ入ったら`setReconnectInterval(0)`として最初の`webSocket.loop()`を1回呼び、接続試行を直ちに開始する。その直後に`setReconnectInterval(30000)`へ変更し、以後も`webSocket.loop()`を呼んで開始済みのhandshakeを進める。最初の試行が失敗しても、15秒の`CONNECTING`中にライブラリ内部の再接続は起こさない。接続完了前に15秒を過ぎたらTEARDOWNへ移る。ただし、TLS内部呼び出しがブロックしている間は15秒を超えうる。

ONLINEでは`enableHeartbeat(30000, 10000, 2)`を使う。30秒ごとにpingし、pongを10秒待ち、2回連続で応答がなければ切断処理へ進む。

### 4.6 TLSと認証

- WebSocket接続時に`Authorization: Bearer <DEVICE_TOKEN>`を送る
- `beginSslWithBundle()`へCA bundleの非nullポインタと実サイズを渡す
- CA bundleがnullまたはsize 0なら初期化失敗として接続しない
- 正しいホスト名は成功し、誤ったホスト名と未信頼証明書は失敗することを実機試験する

CA bundleは、単一CAやcommon CAだけへ絞らず、Mozilla NSS root store由来のfull bundleを使う。arduinoWebSocketsの説明上はFlash約77.2KBを使用するが、現在の3MB app領域では許容する。Cloudflareの証明書発行元変更へ追従するため、ファームを書き換える時はbundleも再生成する。

生成手順:

1. [curlが配布するMozilla由来の`cacert.pem`](https://curl.se/ca/cacert.pem)を取得し、取得日とSHA-256を記録する
2. esp32 core 3.3.11付属の`tools/gen_crt_bundle.py --input cacert.pem`を実行し、`x509_crt_bundle`を生成する。`--filter`は指定しない
3. `xxd -i x509_crt_bundle`でC配列へ変換し、配列を`const`としてファームへ組み込む
4. 配列ポインタと生成された実サイズを`beginSslWithBundle()`へ渡す

生成元PEM、取得日、SHA-256、生成済みheaderはファーム実装と一緒にリポジトリへ保存する。秘密情報は含まれない。

### 4.7 パーティションと依存バージョン

- Arduino IDE 2.x
- `esp32:esp32` 3.3.11
- IRremoteESP8266 2.9.0
- arduinoWebSockets 2.7.2
- パーティション: `Huge APP (3MB No OTA/1MB SPIFFS)`
- Upload Speed: 115200
- シリアルモニタ: 115200 bps

### 4.8 USBシリアルログ

状態変化だけを出力する。

- `boot`
- `wifi_connected` / `wifi_failed status=<WiFi.status()の数値>`
- `time_synced` / `time_failed`
- `ws_connected` / `ws_failed` / `ws_disconnected`
- `ir_sent` / `invalid_frame`

SSID、パスワード、Bearer token、36文字payload、heartbeat成功、待機中の繰り返しログは出力しない。

### 4.9 メモリ目安

| 項目 | 見積もり |
|---|---:|
| Flash | 約1.2MB / 3MB |
| RAM静的 | 約49KB |
| TLS handshake一時ピーク | 30〜45KB |
| RAMピーク | 約100KB / 320KB |

TLS接続中のRAMピークは実測する。

## 5. Cloudflare

### 5.1 構成

- Worker入口とDurable Objectクラスを1つのWorkerプロジェクトへ置く
- Durable Objectは`"home"`という名前の1個だけとする
- Durable ObjectはESP32のdevice WebSocketを最大1本持つ
- 新しいdevice接続が来たら古い接続を閉じ、新しい接続だけを正とする
- WebSocket Hibernation APIで接続を受け入れ、タグ`"device"`を付ける
- 操作時は`ctx.getWebSockets("device")`で接続を取得する
- 通常のJavaScript変数へ接続を保存した前提にしない
- ESP32からアプリ用メッセージは来ないため、`webSocketMessage()`に業務処理を置かない
- WebSocketプロトコルpingへのpongはCloudflare runtimeへ任せる

### 5.2 永続データと一発予約

永続化する業務データは予約1件だけとする。

```json
{
  "executeAt": "2026-09-13T18:00:00Z",
  "setting": {
    "power": true,
    "mode": "cool",
    "temp": 26,
    "fan": "auto",
    "vane": "auto"
  },
  "payload": "23CB26010020180A364000000000001000DD"
}
```

- `executeAt`はUTCの絶対時刻とする
- `payload`は予約受付時に生成して保存する
- 新しい予約は古い予約を置き換える
- キャンセル時は予約レコードとAlarmを削除する
- エアコンの現在状態、命令履歴、キューは保存しない

`PUT /schedule`の`executeAt`は、UTCの正規形`YYYY-MM-DDTHH:mm:ssZ`だけを受理する。形式一致後に日時としてパースし、各UTC成分が入力と一致することを確認する。形式不一致、パース不能、存在しない日時、または検証時点のCloudflare時刻以下ならHTTP 400 `bad_request`とし、Alarmを作成・変更しない。未来側の独自上限は設けない。

Alarm handlerの順序を次に固定する。

```text
予約を読む
→ 予約がなければ終了
→ 予約をストレージから削除し、削除完了を待つ
→ ESP32が接続中ならpayloadを1回だけsend()
→ 未接続またはsend()例外はログに記録し、例外を外へ投げず終了
```

読み込みまたは削除が失敗し、まだ送信していない場合だけ例外を投げてAlarmの再試行に任せる。削除完了後は送信に失敗しても再試行させない。削除後・送信前に処理が停止して命令が失われる可能性は許容する。

### 5.3 認証

| 区間 | 方式 |
|---|---|
| ESP32 → Worker | `Authorization: Bearer <DEVICE_TOKEN>` |
| iPhone → Worker | `Authorization: Bearer <APP_TOKEN>` |

`DEVICE_TOKEN`と`APP_TOKEN`はWorker secretとして保存する。Bearer tokenをログへ出力しない。Workerでは入力値とsecretをそれぞれSHA-256へ変換し、同じ長さのdigest同士を`crypto.subtle.timingSafeEqual`で比較する。

### 5.4 エアコン設定

iOSアプリは操作ごとに全項目を送る。

```json
{
  "power": true,
  "mode": "cool",
  "temp": 26,
  "fan": "auto",
  "vane": "auto"
}
```

| 項目 | 受理する値 |
|---|---|
| `power` | `true` / `false` |
| `mode` | `auto` / `cool` / `dry` / `heat` / `fan` |
| `temp` | 16〜31の整数。電源OFFでも必須 |
| `fan` | `auto` / `1` / `2` / `3` |
| `vane` | `auto` / `highest` / `high` / `middle` / `low` / `lowest` / `swing` |

未知フィールドは無視する。必須項目、型、範囲、列挙値が不正ならHTTP 400を返す。

### 5.5 API

| 入口 | 呼出元 | 動作 |
|---|---|---|
| `GET /device/ws` | ESP32 | WebSocket upgrade。認証成功で101。新接続を正とする |
| `POST /command` | iPhone | 即時操作。設定を36文字へ変換してdevice socketへ書く |
| `GET /schedule` | iPhone | 予約1件または`null`を返す |
| `PUT /schedule` | iPhone | 予約を作成または置換する |
| `DELETE /schedule` | iPhone | 予約とAlarmを削除する |

`GET /schedule`の200 responseは、予約がある場合だけ次の形式とする。内部送信用の`payload`は返さない。

```json
{
  "executeAt": "2026-09-13T18:00:00Z",
  "setting": {
    "power": true,
    "mode": "cool",
    "temp": 26,
    "fan": "auto",
    "vane": "auto"
  }
}
```

予約がなければ200 `null`を返す。`null`は「現在有効な予約がない」ことだけを表し、発火済みとキャンセル済みを区別しない。予約履歴は保存しない。

`POST /command`の結果は次のとおり。

| HTTP | 意味 |
|---|---|
| 202 `{ "ok": true }` | Cloudflareが保持中のWebSocketで`send()`を呼び、同期的な例外が出なかった |
| 400 `bad_request` | エアコン設定が不正 |
| 401 `unauthorized` | APP_TOKENが不一致 |
| 503 `device_offline` | device socketがない、切断済みと判定された、または`send()`が同期的に例外 |
| 500 `server_error` | Cloudflareコードまたはストレージの予期しない失敗 |

HTTP 202はESP32の処理完了やエアコンの受理を意味しない。ESP32が突然電源断した直後などは、Cloudflareが古いsocketをまだ接続中と扱い、202を返すことがある。アプリケーション用PING/PONGは追加せず、この不確実性を許容する。

### 5.6 運用ログ

各行をJSONとし、`time`と`event`だけを必須にする。

- `device_connected` / `device_disconnected`
- `command_sent` / `command_offline`
- `schedule_set` / `schedule_deleted`
- `schedule_fired_sent` / `schedule_fired_offline`
- `server_error`

Bearer token、36文字payload、エアコン設定、heartbeat成功、通常待機は記録しない。

## 6. iOSアプリ

- SwiftとSwiftUIを使う
- URLSessionでCloudflareのHTTPS APIだけを呼ぶ
- 設定値の正本を端末へローカル保存する
- 操作ごとに全設定を送る
- 202は「送信要求を受け付けました」と表示し、「エアコンが動きました」と表示しない
- 予約画面はGET、PUT、DELETEの3操作だけとする
- 予約は最大1件で、新規保存は既存予約を置き換える
- `executeAt`はUTCへ変換し、小数秒なしの`YYYY-MM-DDTHH:mm:ssZ`で送る
- LAN探索、Bonjour、ローカルネットワーク権限を使わない
- APP_TOKENはアプリの設定画面で一度入力し、Keychainへ保存する。UserDefaults、ソースコード、リポジトリへ保存しない

エラーの扱い:

| HTTP | アプリでの扱い |
|---|---|
| 400 | アプリの入力生成の不具合 |
| 401 | APP_TOKEN設定不一致 |
| 503 | ESP32の電源、家庭Wi-Fi、接続を確認 |
| 500 | Cloudflareログを確認 |

## 7. 赤外線データ生成

Cloudflare側に、外部状態を参照しない純粋関数`encode(setting) -> 36文字`として実装する。

### 7.1 18バイト形式

| byte | 値または生成規則 |
|---:|---|
| 0〜4 | `23 CB 26 01 00` |
| 5 | `power=true`なら`20`、falseなら`00` |
| 6 | `auto=20`、`cool=18`、`dry=10`、`heat=08`、`fan=38` |
| 7 | `temp - 16`。16℃=`00`、31℃=`0F` |
| 8 | `auto=30`、`cool=36`、`dry=32`、`heat=30`、`fan=37` |
| 9 | `40 OR (vane値 << 3) OR fan値` |
| 10〜14 | `00 00 00 00 00` |
| 15〜16 | `10 00` |
| 17 | byte 0〜16の合計の下位8bit |

byte 8の上位4bitは`3`とし、水平風向を中央へ固定する。

`fan値`:

| 設定 | 値 |
|---|---:|
| `auto` | 0 |
| `1` | 1 |
| `2` | 2 |
| `3` | 3 |

対象リモコンの風量は自動と3段のみで、静音と4段目は存在しない（ADR-019）。

`vane値`:

| 設定 | 値 |
|---|---:|
| `auto` | 0 |
| `highest` | 1 |
| `high` | 2 |
| `middle` | 3 |
| `low` | 4 |
| `lowest` | 5 |
| `swing` | 7 |

実機リモコンに合わせ、byte 9のbit 7（IRremoteESP8266の`FanAuto`）は常に0、bit 6は常に1とする。リモコンは風量ボタンや風向ボタンで「自動」を選んだ直後のフレームだけ bit 7=1、bit 6=0 の形（`98`、`81`）を送るが、電源ボタンのフルステートフレームでは自動も `40 | vane<<3 | fan` の形（`40`、`41`、`58`）になる。encoder は後者に従う（[採取記録](./ir-captures.md)）。

byte 15はリモコンでは電源ボタンのフレームで `10`、他のボタンでは `00` になる。power の値とは独立で、エアコンは両方を受理する。encoder は `10` に固定する。

### 7.2 必須テストベクトル

| 設定 | 根拠 | 期待する36文字 |
|---|---|---|
| ON / dry / 24℃ / auto / middle | 実機リモコン採取 | `23CB260100201008325800000000001000E7` |
| ON / cool / 26℃ / auto / middle | 実機リモコン採取（電源ボタン） | `23CB26010020180A365800000000001000F5` |
| OFF / cool / 26℃ / auto / middle | 実機リモコン採取（電源ボタン） | `23CB26010000180A365800000000001000D5` |
| ON / cool / 26℃ / 1 / auto | 実機リモコン採取（電源ボタン） | `23CB26010020180A364100000000001000DE` |
| ON / heat / 26℃ / 1 / lowest | 採取値の byte 15 を `10` に正規化 | `23CB26010020080A306900000000001000F0` |

5件が一致するまでネットワーク処理へ組み込まない。5件目は温度ボタン直後の採取値（byte 15=`00`）を電源ボタン形式へ正規化したもので、mode=heat と vane=lowest の値は採取で確認済みである。

採取の経過と規則との照合は[採取記録](./ir-captures.md)に残す。cool・dry・heat の byte 6/8、temp、vane 0〜5 と 7、fan 0〜3、byte 10〜14 と 16 の固定部、チェックサムは採取で確認済み。mode の `auto` と `fan` はリモコンに存在せず未採取のため、IRremoteESP8266 の値を採用する。

## 8. ハードウェア

### 8.1 使用機器とピン

- ideaspark ESP32開発ボード、ESP32-WROOM-32、4MB Flash、Micro-USB
- 赤外線送信: GPIO4（D4）
- 赤外線受信モジュール: GPIO15（D15、解析時だけ）。GPIO15は起動時のU0TXD出力を決めるstrapping pinなので、受信モジュールは通常運用では外し、解析時もアイドルHIGHであることを確認する
- GPIO21とGPIO22はオンボードOLEDが使うため使用しない

### 8.2 赤外線送信回路

NPNトランジスタS8050のローサイドスイッチとし、IR LEDの電流はUSB由来のVIN 5Vから取る。

```text
VIN 5V ──┬──▶| LED1 ──[100Ω]──┐
         ├──▶| LED2 ──[100Ω]──┤── Collector
         └──▶| LED3 ──[100Ω]──┘   S8050

GPIO4 ──[220Ω]── Base
                    │
                  [10kΩ]
                    │
                   GND
Emitter ─────────── GND
```

- 各LEDへ専用の100Ω直列抵抗を1本ずつ入れる
- GPIO4とBaseの間に220Ωを入れる
- BaseとGNDの間に10kΩのプルダウンを入れる
- ESP32、VIN電源、トランジスタのGNDを共通にする
- S8050のピン順は手元部品のデータシートまたはテスターで確認する
- 透明な940nm送信用IR LEDを使う
- 100Ωで到達しない場合だけLEDの許容パルス電流を確認し、各68Ωを試す
- 47Ωから開始しない

100Ω時の目安は、IR LEDの順方向電圧1.2V、トランジスタ降下0.2Vとして約36mA/本、合計約108mA。実測値を優先する。

### 8.3 設置前の電気試験

| 試験 | 合格条件 |
|---|---|
| 待機中 | IR LEDが消灯し、BaseがLOW |
| リセット中 | IR LEDが点灯し続けず、10kΩプルダウンが働く |
| 送信中のLED電流 | 各枝がLEDの許容パルス電流以下 |
| 送信中の3.3V | 大きく降下せず、再起動・文字化け・Wi-Fi切断がない |
| 到達 | 予定設置位置からエアコンが安定して反応する |

100Ωで届かなければ、LEDの向き、S8050のピン順、スマホカメラでの発光、設置角度を先に確認する。68Ωへ変更した場合は電流、電圧、トランジスタ温度を再測定する。

## 9. 障害判断

| 見えていること | 意味 | 最初にすること |
|---|---|---|
| アプリが400 | 不正な設定を送った | アプリの入力生成を確認 |
| アプリが401 | APP_TOKEN不一致 | Worker secretとアプリ設定を合わせる |
| アプリが503 | Cloudflareが利用可能なESP32接続を持っていない | ESP32電源、家庭Wi-Fi、ルーターを順に確認 |
| アプリが500 | Cloudflare側の失敗 | Worker Logsを確認。ESP32は再起動しない |
| 202だがエアコンが動かない | 古いsocketへ送った、ESP32未処理、赤外線未達、エアコン未受理のいずれか | ESP32の再接続を最大「現在の接続試行時間＋30秒程度」待ち、一度だけ再操作する。続くなら電源、IR LED、USBシリアルを確認 |
| Wi-Fi接続ログは出るがWebSocket失敗が続く | 接続先、DEVICE_TOKEN、時刻、証明書、CA bundleのいずれか | シリアルログとbundleの生成元・取得日を確認する |
| 送信時にESP32が再起動 | 電源または過電流の可能性 | 5V、3.3V、各LED電流を測る |
| 予約だけ動かない | 予約、Alarm、発火時接続のいずれか | `GET /schedule`、次に予約発火ログを確認 |

管理対象は、Workerプロジェクト1つ、Durable Object 1個、secret 2つ、予約1件、ESP32ファーム1つ、iOSアプリ1つだけとする。

## 10. 検証と完了条件

### 実装前・設置前に確認すること

- 正しい36文字だけを送信し、短い・長い・小文字・空白・binary frameを無視する
- ESP32がアプリ用WebSocketメッセージを一切返さない
- 複数フレームを独自キューなしで順番に同期送信する
- Wi-Fi 15秒、NTP 10秒の期限が働く
- 有効な時刻があればNTPを省略する
- TLSの内部ブロック時間を測る
- TLS接続中にTask WDTが誤発火しないことを確認する
- ONLINEで待機中（`loop()`が即時に返る状態）に5秒以上経ってもTask WDTが発火しない
- 正しいホストはTLS成功、誤ホスト・未信頼証明書は失敗する
- heartbeatでAP切断、ルーター再起動、ISP断を検知する
- 接続失敗時は1サイクル1回だけ接続を試し、必ず後始末、Wi-Fi OFF、30秒待機、再接続となる
- 24時間の接続失敗でheapが減り続けない
- 新しいdevice WebSocketが古い接続を置き換える
- APIが仕様どおり202、400、401、503、500を返す
- Durable Objectのhibernate後もdevice socketを再取得できる
- Alarmの各段階へ例外を入れても二重送信しない
- iOSが`executeAt`をUTC・小数秒なしの正規形で生成する
- `executeAt`の不正形式、存在しない日時、現在以前が400になり、Alarmを変更しない
- `GET /schedule`がpayloadを返さず、予約なしでは`null`になる
- 電気試験に合格する

### 完了条件

- 上記試験がすべて通る
- iPhone、Cloudflare、ESP32を通して実機を操作できる
- ルーター電源断から復旧後、手動操作なしで再接続する
- 24時間の切断試験で再起動ループ、heap減少、二重送信がない
- USBポートへ手が届く状態で恒久設置できる

## 11. 実装順序

| 段階 | 作るもの | 完了条件 |
|---|---|---|
| 1. Encoder | 純粋関数と4件のunit test | ネットワークなしで全テスト一致 |
| 2. 赤外線 | 回路、実機リモコン採取、USBシリアルから36文字を受ける試験コード | 自動・暖房・固定部を採取確認し、実機が安定して反応して電気試験合格 |
| 3. 機器接続 | device WebSocket、認証、Hibernation、30秒再接続 | 接続ログが出て、hibernate後もsocket取得可能 |
| 4. 即時操作 | `POST /command`をcurl等で呼ぶ | 全HTTP結果を再現し、202で実機動作 |
| 5. 障害系 | AP断、ルーター再起動、誤証明書、長時間失敗 | ネットワーク試験と24時間heap試験合格 |
| 6. iOS | フル設定、即時操作、エラー表示 | アプリから実機操作可能 |
| 7. 予約 | schedule APIとAlarm | 置換、取消、offline破棄、二重送信なし |
| 8. 設置 | 配線固定、USBアクセス、通し試験 | 全完了条件を満たす |

各段階が終わるまで次へ進まない。問題発生時は、その段階で新しく加えた境界から調べる。
