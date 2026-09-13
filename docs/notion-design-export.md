# エアコン遠隔操作 — 設計
**状態**: 設計中（実装前）　/　**最終更新**: 2026-09-13
---
## 0. 優先順位
この設計は次の順で守る。
1. **所有者が理解・管理できること** — 正常時の流れ、失敗時の結果、復旧方法を自分の言葉で説明できる
2. **物理安全と通信の安全** — 発熱・過電流・認証・TLS は単純さのために削らない
3. **現在の要件を満たすこと** — 将来だけの用途は現在のコードへ入れない
4. **ESP32 の責務を小さくすること** — 変更は USB 再書き込みでよい
5. インフラ、アプリの順に複雑さを置く
判断に迷ったら次の順に問う。
- **今の要件に必要か。** いいえなら入れない
- **失敗すると危険か。** はいならESP32側でも防ぐ
- **故障時の判断手順を1つにできるか。** できなければ構成を減らす
- **将来だけ必要か。** その時にUSBで焼き直す
> コンポーネント数ではなく、**所有者が覚える概念と分岐の数**を最小にする。
---
## 1. スコープ
### やること
- スマホからエアコンをリアルタイムに操作（電源・モード・温度・風量・風向）
- 外出先からも操作できる
- タイマー（「18時につける」「5分後につける」）
### やらないこと
- 通知 / メッセージング（将来やる可能性あり。設計で道を塞がない）
- 音声操作、ウィジェット、Apple Watch
- リモコンにない機能
- LAN 直通経路（初期実装では作らない）
- **OTA / 遠隔ファーム更新**（D16）
---
## 2. 制約と決定
### 制約（動かせない）
<table header-row="true">
<tr>
<td></td>
<td>内容</td>
<td>出どころ</td>
</tr>
<tr>
<td>C1</td>
<td>家に常設するのは ESP32 のみ</td>
<td>本人</td>
</tr>
<tr>
<td>C2</td>
<td>外出先からの操作が最初から必要</td>
<td>本人</td>
</tr>
<tr>
<td>C3</td>
<td>エアコンは状態を返さない（赤外線は片方向）</td>
<td>物理</td>
</tr>
<tr>
<td>C4</td>
<td>赤外線を出せるのは ESP32 だけ</td>
<td>物理</td>
</tr>
</table>
C1 の影響が大きい。Tailscale（subnet router が要る）・HomeKit ハブ・Home Assistant はすべて選択肢から消える。
### 決定
<table header-row="true">
<tr>
<td></td>
<td>内容</td>
<td>理由</td>
</tr>
<tr>
<td>D1</td>
<td>ESP32 の責任を最小にする。将来機能を先回りして載せない</td>
<td>本人（最優先）。必要な変更はUSBで焼き直す</td>
</tr>
<tr>
<td>D2</td>
<td>LAN 直通経路は作らない。クラウド経由のみ</td>
<td>実装がシンプル</td>
</tr>
<tr>
<td>D3</td>
<td>Wi-Fi 資格情報は焼き込み。再設定機構なし</td>
<td>本人（無視でOK）</td>
</tr>
<tr>
<td>D4</td>
<td>予約・業務時刻はクラウドが持つ。ESP32 は TLS 証明書検証用の概算 UTC だけを同期し、指示を待つ</td>
<td>本人</td>
</tr>
<tr>
<td>D5</td>
<td>命令の失敗は無視し、命令を再送しない。通信接続だけはD17に従って繰り返す</td>
<td>本人</td>
</tr>
<tr>
<td>D6</td>
<td>暴走してハードを壊さないことだけは ESP32 側で担保</td>
<td>本人</td>
</tr>
<tr>
<td>D7</td>
<td>クラウドは **Cloudflare Workers + Durable Objects**</td>
<td>想定利用量が現在の無料枠内で、ESP32 の責務が減る</td>
</tr>
<tr>
<td>D8</td>
<td>赤外線パケットの組み立てはクラウド側</td>
<td>D1</td>
</tr>
<tr>
<td>D9</td>
<td>iOS ネイティブアプリ</td>
<td>将来の通知</td>
</tr>
<tr>
<td>D10</td>
<td>ESP32向けメッセージは **18バイトを表す36文字の16進テキストだけ**。`MITSUBISHI_AC` 固定。応答なし</td>
<td>`id`・`op`・`proto`・JSON・`ok/error`・`v/fw/up` は現在の送信結果を変えず、クラウドとファームの状態を増やすため載せない</td>
</tr>
<tr>
<td>D11</td>
<td>タイマーは**一発のみ**。繰り返しは実装しない</td>
<td>本人（絶対使わない）</td>
</tr>
<tr>
<td>D12</td>
<td>「届いたか」の確認手段（マイク・自己受信・温度センサー）は載せない</td>
<td>最小構成を優先</td>
</tr>
<tr>
<td>D13</td>
<td>認証は静的 Bearer トークン。ESP32 用とアプリ用を分ける</td>
<td>最も簡単で無料</td>
</tr>
<tr>
<td>D14</td>
<td>WebSocket ライブラリは **WebSockets（Links2004 / arduinoWebSockets）**</td>
<td>CA バンドル・heartbeat API が使える。再接続の時刻管理はライブラリではなく状態機械が持つ。§4.6 / §11.2</td>
</tr>
<tr>
<td>D15</td>
<td>**Durable Object はエアコンの状態を持たない。** 設定値の正本はアプリ。アプリは毎回フル状態を送る</td>
<td>状態が必要な場面が存在しなかった。予約は「状態」ではなく「命令」として持てば足りる</td>
</tr>
<tr>
<td>D16</td>
<td>**OTA を実装しない。** ファーム変更は USB ケーブルによる物理アクセスで行う</td>
<td>最有力の変更理由（ルーター交換）に OTA は効かない。残る用途は机上の調整期に消化される。§11.4</td>
</tr>
<tr>
<td>D17</td>
<td>接続失敗・切断後は後始末して無線を切り、**毎回30秒待って**最初から接続する</td>
<td>1つの定数で説明・実装・確認できる。指数バックオフ、ジッタ、2段切替は使わない。§4.6</td>
</tr>
</table>
---
## 3. 全体構成
```javascript
iPhone（SwiftUI）
   │ HTTPS
   ▼
Cloudflare Worker（認証・命令受付）
   │
   ▼
Durable Object（1個）
   ├ 赤外線パケットを18バイトに組み立てる
   ├ 予約された命令を保持し Alarm で発火
   └ ESP32 との WebSocket を保持（Hibernation）
   │
   │ WebSocket over TLS（Cloudflare → ESP32 は36文字の16進だけ）
   ▼
ESP32
   └ 赤外線送信（GPIO4）
   │
   │ 赤外線
   ▼
エアコン
```
家のルーターに穴を一切開けない。ESP32 は外から見えず、外向きの接続を1本張るだけ。
### 責務の分配
<table header-row="true">
<tr>
<td></td>
<td>持つ</td>
<td>持たない</td>
</tr>
<tr>
<td>ESP32</td>
<td>接続を維持し、赤外線を出す。TLS検証に必要な場合だけ概算UTCを同期する</td>
<td>エアコン状態・予約時刻・設定の意味</td>
</tr>
<tr>
<td>Durable Object</td>
<td>接続保持・パケット組み立て・予約・時計</td>
<td>**エアコンの状態**（D15）</td>
</tr>
<tr>
<td>Worker</td>
<td>認証境界・API 整形</td>
<td>状態</td>
</tr>
<tr>
<td>iOS アプリ</td>
<td>UI ＋ **設定値の正本**（ローカル保存）</td>
<td>—</td>
</tr>
</table>
---
## 4. ESP32 設計
### 4.1 動作
```javascript
起動 → Wi-Fi → 必要ならNTP → WebSocket接続 → 待機
                                              ↓
              36文字の16進データを受信 → 赤外線送信 → 待機
                                              ↓
       切断・接続失敗 → 後始末 → 無線OFF → 30秒待つ → 接続
```
ESP32 は **「36文字を受け取ったら三菱エアコンの赤外線として出す」** だけを行う。アプリ用の応答メッセージは返さない。
### 4.2 責務（これだけ）
1. Wi-Fi に繋ぐ
2. Cloudflare に WebSocket over TLS で繋ぎ続ける
3. 36文字の固定形式を検証し、赤外線を出す
### 4.3 持たないもの
- **永続状態（アプリ独自の NVS 書き込みゼロ）**
- エアコンの意味（「冷房」「26℃」を知らない）
- エアコンの状態（D15。正本はアプリ）
- タイマー・タイムゾーン・繰り返し規則
- 再送・リトライ・アプリケーションキュー
- **OTA・HTTP クライアント**（D16）
- HTTP サーバー・mDNS
- JSON パーサー
- コマンドID、応答、エラーコード
- 独自 FreeRTOS タスク、タスク間キュー、busy フラグ
Wi-Fi 資格情報の正本は D3 のとおりファームウェア定数として flash に焼く。ただし Wi-Fi ドライバによる **NVS への重複保存はさせない**。起動時、最初の `WiFi.mode()` / `WiFi.begin()` より前に `WiFi.persistent(false)` を1回呼ぶ。
再起動しても失うものがない。設定値が今どうなっているかはアプリが覚えている。
### 4.4 機器向けメッセージ契約
Cloudflare → ESP32 のアプリケーションメッセージは、**WebSocketテキストフレーム1種類だけ**。
```plain text
23CB260100201008325800000000001000E7
```
<table header-row="true">
<tr>
<td>規則</td>
<td>値</td>
</tr>
<tr>
<td>長さ</td>
<td>**36文字ちょうど**（18バイト）</td>
</tr>
<tr>
<td>文字</td>
<td>ASCII の `0`〜`9`、`A`〜`F` のみ。小文字・空白・改行は不可</td>
</tr>
<tr>
<td>赤外線方式</td>
<td>**`MITSUBISHI_AC`**** 固定**</td>
</tr>
<tr>
<td>応答</td>
<td>**なし**。WebSocket制御フレームのpongはライブラリが返すが、アプリ用メッセージは送らない</td>
</tr>
<tr>
<td>不正入力</td>
<td>送信せず捨てる。応答しない</td>
</tr>
</table>
実装は固定長 `uint8_t state[18]` へ変換し、`IRsend::send(MITSUBISHI_AC, state, 18)` を呼ぶだけ。JSON解析・可変長確保・文字列フィールド検索は行わない。
**削ったもの**: `id`、`op`、`proto`、`v`、`fw`、`up`、`ok`、`error`。現在の要件ではどれも送信結果を変えないため。
### 4.5 赤外線送信
赤外線送信は **WebSocket受信コールバック内で同期的に実行する**。独自タスクへ渡さない。
<table header-row="true">
<tr>
<td>項目</td>
<td>設計</td>
<td>理由</td>
</tr>
<tr>
<td>実行場所</td>
<td>Arduino の通常の `loop()` から呼ばれた WebSocket コールバック</td>
<td>タスク間受け渡し、固定バッファ共有、完了通知をすべて消せる</td>
</tr>
<tr>
<td>所要時間</td>
<td>約0.5秒。その間 `webSocket.loop()` は進まない</td>
<td>heartbeat の秒数より十分短く、Wi-Fiのシステム処理は別coreで動く</td>
</tr>
<tr>
<td>WDT</td>
<td>起動時に `enableCore1WDT()`</td>
<td>core 1 が5秒以上CPUを占有し IDLE を止める異常を回収する。正常な約0.5秒送信では発火しない</td>
</tr>
<tr>
<td>キュー / busy</td>
<td>**実装しない**</td>
<td>1フレームを処理し終えてから次のフレームを処理する。TCPやライブラリ内部の受信待ちはあるが、ファーム独自の保留領域は作らない</td>
</tr>
<tr>
<td>割り込み禁止</td>
<td>**しない**</td>
<td>Wi-Fi動作を壊さない</td>
</tr>
<tr>
<td>歪み・未達</td>
<td>**検知しない。再送しない**</td>
<td>C3 / D5。三菱は毎回フル状態を送るので、ユーザーが再操作しても危険なトグルにならない</td>
</tr>
</table>
### 4.6 ネットワーク
#### 所有者が覚える規則
> **接続できたら待つ。切れたら全部片づけ、無線を切って30秒待ち、最初から接続する。通信失敗では再起動しない。**
再接続の所有者はライブラリではなくESP32の状態機械。`CONNECTING` と `ONLINE` の時だけ `webSocket.loop()` を呼び、`OFF_WAIT` では呼ばない。
#### 接続の順序と期限
1. Wi-Fi接続 — 15秒で打ち切る
2. システム時刻が 2024-01-01 UTC 未満ならNTP同期 — 10秒で打ち切る
3. WebSocket over TLS接続 — アプリ側の期限は15秒
NTPサーバーは `time.cloudflare.com`、`time.google.com`、`pool.ntp.org` の3つ。同期済みなら再接続のたびに取り直さない。
arduino-esp32 3.3.11 のTLS handshakeは同期処理で、1回の内部呼び出しが既定120秒まで止まりうる。この間はアプリ側の15秒期限を強制できない。ライブラリをforkしない代償として受け入れ、実機で測る。
#### 切断時
接続失敗、WebSocket close、heartbeat不応答はすべて同じ処理。
1. `webSocket.disconnect()` とクライアント後始末
2. `WiFi.mode(WIFI_OFF)`
3. **30秒待つ**
4. Wi-Fi接続からやり直す
指数バックオフ、ジッタ、10秒段、切断回数の記録は使わない。
#### 生存確認
ONLINEでは `enableHeartbeat(30000, 10000, 2)` を使う。30秒ごとにping、pongを10秒待ち、2回連続不応答なら切断処理へ進む。CloudflareはWebSocketプロトコルpingへ自動pongする。
#### TLS・認証
- WebSocket接続時にESP32用の静的Bearerトークンを送る
- `beginSslWithBundle()` へCAバンドルの非nullポインタと実サイズを渡す
- null / size 0 は検証なし接続になるため、初期化失敗として接続しない
- 実機で「正しいホストは成功」「誤ったホスト名・未信頼証明書は失敗」を確認する
### 4.7 パーティション
Arduino IDEで **`Huge APP (3MB No OTA/1MB SPIFFS)`** を選ぶ。OTAを採らない（D16）ためappスロットは1つ。
実体の [`huge_app.csv`](https://github.com/espressif/arduino-esp32/blob/3.3.11/tools/partitions/huge_app.csv) には app 3MB、NVS 20KB、otadata 8KB、SPIFFS 896KiB、coredump 64KB がある。ファイルシステムは使わないが、カスタムパーティションを管理しない単純さを優先する。
IRremoteESP8266は既定設定のまま使うが、v1が呼ぶ送信方式は `MITSUBISHI_AC` の18バイト形式だけ。他方式への交換時はUSBでファームを書き換える。
### 4.8 起動・常時接続シーケンス
```javascript
BOOT
  → GPIO4 の出力ラッチを LOW → OUTPUT化
  → enableCore1WDT()
  → WiFi.persistent(false)
  → CONNECTING（Wi-Fi → 必要な時だけNTP → WebSocket）
  → ONLINE（受信した36文字を同期送信）

接続失敗 / WebSocket close / heartbeat不応答
  → TEARDOWN
  → Wi-Fi OFF
  → 30秒待つ
  → CONNECTING
```
<table header-row="true">
<tr>
<td>段</td>
<td>規則</td>
</tr>
<tr>
<td>GPIO4</td>
<td>LOWを出力ラッチに設定してからOUTPUTにする。リセット中はソフトで保証できないため、外付けベースプルダウン抵抗を必須とする（§8.4）</td>
</tr>
<tr>
<td>Wi-Fi永続化</td>
<td>最初のWi-Fi初期化より前に `WiFi.persistent(false)` を1回呼ぶ</td>
</tr>
<tr>
<td>CONNECTING</td>
<td>Wi-Fi、条件付きNTP、TLSの順。どこで失敗しても同じTEARDOWNへ進む</td>
</tr>
<tr>
<td>ONLINE</td>
<td>WebSocketを維持し、正しい36文字を受けた時だけ同期的に赤外線送信する</td>
</tr>
<tr>
<td>TEARDOWN</td>
<td>WebSocketを先に後始末し、次にWi-FiをOFF、最後に30秒待つ</td>
</tr>
</table>
### 4.9 失敗時の振る舞い
<table header-row="true">
<tr>
<td>事象</td>
<td>振る舞い</td>
</tr>
<tr>
<td>Wi-Fi / NTP / WebSocketが成立しない</td>
<td>後始末 → 無線OFF → 30秒待機。**再起動しない**</td>
</tr>
<tr>
<td>ONLINE中にWebSocketが閉じる / heartbeat不応答</td>
<td>同じ復帰経路へ入る</td>
</tr>
<tr>
<td>36文字でない / 16進大文字でない / binary frame</td>
<td>**捨てる。応答しない。落ちない**</td>
</tr>
<tr>
<td>赤外線送信中に接続が切れる</td>
<td>赤外線送信は完了させ、その後に切断処理へ進む。再送しない</td>
</tr>
<tr>
<td>赤外線が歪む / エアコンが受け取らない</td>
<td>**検知しない。何もしない**</td>
</tr>
<tr>
<td>core 1がCPUを5秒以上占有し IDLE を止める</td>
<td>Task Watchdogが再起動する。CPUを占有しない停止まで検出する保証はない</td>
</tr>
</table>
> **通信失敗は30秒待って再接続。コードがCPUを固めた時だけWDT再起動。**
#### USBシリアルログ
遠隔診断フィールドを持たない代わりに、115200bpsで状態変化だけを出す。
- `boot`
- `wifi_connected` / `wifi_failed`
- `time_synced` / `time_failed`
- `ws_connected` / `ws_disconnected`
- `ir_sent` / `invalid_frame`
SSID、パスワード、Bearer token、36文字payloadは出力しない。heartbeat成功や30秒待機中の繰り返しログも出さない。
### 4.10 予算
<table header-row="true">
<tr>
<td></td>
<td>見積もり</td>
</tr>
<tr>
<td>Flash</td>
<td>TLS/WebSocket 込みで概ね 1.2MB 前後 / スロット **3MB**（約40%）</td>
</tr>
<tr>
<td>RAM 静的</td>
<td>49KB</td>
</tr>
<tr>
<td>RAM TLS ハンドシェイク（一時ピーク）</td>
<td>30〜45KB</td>
</tr>
<tr>
<td>**RAM ピーク**</td>
<td>**約 100KB / 320KB**</td>
</tr>
</table>
Flash の見積もりは旧プロトタイプ（Web サーバー・HTML・NVS・mDNS 入りで990KB）からの外挿なので粗い。ただし枠が 1.94MB → 3MB に増え、`HTTPClient` と `Update` も消えたため、**逼迫する見込みはなくなった**。
ソフトウェアのメモリ予算では、TLSのRAMピークを実測する。電気試験など他の確認事項は§8.4 / §11.7に分ける。
### 4.11 「後で変えられるか」
D1 に対する答え。**OTA を採らない（D16）ので、分類は1つしかない。**
> **すべて「USB ケーブルを挿して焼き直せば変えられる」。** パーティション表も例外ではない。eFuse（flash encryption / secure boot）は使わないので、**焼く前に決めきらないと二度と直せない項目はゼロ。**
かつては「層1＝OTA でも変えられない」「層2＝間違えると OTA が届かない」「層3＝OTA で変えられる」の3層に分けていた。この区分は OTA の存在を前提にしていたので、D16 とともに消滅した。
代わりに意識すべきは**物理アクセスのコスト**であり、これはソフトではなくハードの問題になる。
- **USBポートに手が届く場所へ設置すること**（§8.3のVIN 5V回路と併せて決める）
- 間違えると動かなくなる焼き込み項目は、Wi-Fi 資格情報（D3）・Cloudflare の接続先とトークン・CA バンドル
---
## 5. クラウド設計（Cloudflare）
### 5.1 なぜ Cloudflare か
- 現在のWorkers Free枠で運用できる。通常利用は十分小さく、30秒再接続が24時間続く極端な場合でもリクエスト枠に約35倍の余裕がある
- **ESP32 の責務が Azure より小さくなる**（SAS トークンの生成・期限管理が不要）── D1 に直接効く
- Durable Object の「接続 ＋ 予約 ＋ タイマー」が、1台のエアコンにそのまま当てはまる
- ストレージアカウントのような「本体と関係ない必須コンポーネント」がない
Azure IoT Hub でも成立するが、Functions が必須とするストレージアカウントが永久無料の対象外で、月¥10〜150 が残る。また SAS トークンの分だけファームが重くなる。
### 5.2 所有者が覚えるCloudflareの役割
> **Cloudflareは、スマホの設定を36文字へ変換し、接続中のESP32へ渡す。さらに予約を1件だけ覚える。**
Cloudflare上では **1つのWorkerプロジェクト**にWorker入口とDurable Objectクラスを同居させる。Durable Objectも `"home"` という名前の1個だけ。運用上は1サービスとして扱う。
Durable Objectの責務は次の4つだけ。
1. ESP32とのWebSocketを1本保持する
2. スマホのフル設定から三菱エアコン用18バイトを作る
3. 接続中なら36文字として送る。未接続ならアプリへ `device_offline` を返す
4. 一発予約を最大1件保存し、時刻になったら一度だけ同じ送信を試す
**持たないもの**:
- エアコンの現在状態
- ESP32からの応答待ち
- `id` と待機中HTTPリクエストの対応表
- コマンドキュー、再送回数、履歴
#### WebSocketの扱い
- Hibernation APIで受け入れ、タグ `"device"` を付ける
- 操作時は `ctx.getWebSockets("device")` で現在の接続を取得する。**通常のJavaScript変数は睡眠時に消えるため、接続をメモリ変数へ保存した前提で書かない**
- 新しいESP32接続が来たら古いdevice接続を閉じ、**新しい接続1本だけを正**とする
- ESP32はアプリ用メッセージを返さないため、`webSocketMessage()` に業務処理は置かない
- WebSocketプロトコルpingへのpongはCloudflare runtimeに任せる
Cloudflareは、Hibernation中もWebSocketを維持し、プロトコルpingへ自動pongする。[公式: WebSocket Hibernation](https://developers.cloudflare.com/durable-objects/best-practices/websockets/)
### 5.3 無料枠
<table header-row="true">
<tr>
<td>項目</td>
<td>Workers Freeの枠</td>
<td>この構成</td>
</tr>
<tr>
<td>DOリクエスト</td>
<td>100,000 / 日</td>
<td>通常は操作回数程度。接続障害が24時間続き、30秒待機後に毎回Cloudflareまで到達しても最大約2,880回 / 日</td>
</tr>
<tr>
<td>DO実行時間</td>
<td>13,000 GB-s / 日</td>
<td>アイドル中はHibernationするため、主に操作・接続・Alarm処理中だけ</td>
</tr>
<tr>
<td>SQLite書き込み</td>
<td>100,000行 / 日</td>
<td>予約の作成・削除だけ</td>
</tr>
<tr>
<td>SQLite保存</td>
<td>5GB</td>
<td>予約1件だけ</td>
</tr>
</table>
この規模で枠を意識した動的制御は入れない。無料枠超過時はその操作が失敗し、UTC 00:00のリセットまで待つ。[公式: Durable Objects pricing](https://developers.cloudflare.com/durable-objects/platform/pricing/)
### 5.4 一発予約
Durable Objectが永続保存する業務データは、次の**1レコードだけ**。
```json
{
  "executeAt": "2026-09-13T18:00:00Z",
  "setting": { "power":true, "mode":"cool", "temp":26, "fan":"auto", "vane":"auto" },
  "payload": "23CB260100201008325800000000001000E7"
}
```
- 新しい予約は古い予約を置き換える
- `executeAt` はUTCの絶対時刻
- `payload` は予約受付時に生成して保存する。後日のコード変更で予約内容が変わらないため
- キャンセルはレコードとAlarmを削除する
Cloudflare Alarmは少なくとも1回実行され、handlerが例外終了すると自動再試行される。そのため、alarm handlerは次の順序に固定する。[公式: Alarms](https://developers.cloudflare.com/durable-objects/api/alarms/)
```javascript
予約を読む
→ 予約がなければ終了
→ 予約を永続ストレージから削除し、完了を待つ
→ ESP32が接続中なら payload を1回だけ send()
→ 未接続・送信例外は記録せず、正常終了
```
**削除してから送る。** 読み込み・削除が失敗した時点ではまだ送っていないので、例外を投げてAlarmの再試行に任せてよい。削除が完了した後は、`send()` が失敗しても例外を外へ投げない。再実行されても予約が存在せず、二重送信しない。
削除後・送信前にCloudflareが停止した場合は命令が失われるが、D5の「再送しない」を優先して受け入れる。
### 5.5 認証
<table header-row="true">
<tr>
<td>区間</td>
<td>方式</td>
</tr>
<tr>
<td>ESP32 → Worker</td>
<td>`Authorization: Bearer <DEVICE_TOKEN>`</td>
</tr>
<tr>
<td>iPhone → Worker</td>
<td>`Authorization: Bearer <APP_TOKEN>`</td>
</tr>
</table>
トークンはCloudflare Workerのsecretとして `DEVICE_TOKEN` と `APP_TOKEN` の2つだけ持つ。2つを分けることで、アプリ側のトークンが漏れてもESP32を焼き直さず交換できる。
Cloudflare Accessやユーザー管理は入れない。個人用アプリなので、漏洩時はWorker secretを更新する。ESP32用トークンを変えた時だけUSB再書き込みが必要。
### 5.6 外部API
#### 共通のエアコン設定
アプリは毎回フル設定を送る。
```json
{
  "power": true,
  "mode": "cool",
  "temp": 26,
  "fan": "auto",
  "vane": "auto"
}
```
<table header-row="true">
<tr>
<td>項目</td>
<td>受理する値</td>
</tr>
<tr>
<td>`power`</td>
<td>`true` / `false`</td>
</tr>
<tr>
<td>`mode`</td>
<td>`auto` / `cool` / `dry` / `heat` / `fan`</td>
</tr>
<tr>
<td>`temp`</td>
<td>16〜31の整数。電源OFFでも必須</td>
</tr>
<tr>
<td>`fan`</td>
<td>`auto` / `quiet` / `1` / `2` / `3` / `4`</td>
</tr>
<tr>
<td>`vane`</td>
<td>`auto` / `highest` / `high` / `middle` / `low` / `lowest` / `swing`</td>
</tr>
</table>
未知フィールドは無視し、必須項目・型・範囲・列挙値が不正ならHTTP 400。三菱実機固有の「fan auto時はbyte9 bit7を0にする」補正を含む変換規則は§13に固定し、Cloudflareのencoderだけに置く。
#### 入口は5つだけ
<table header-row="true">
<tr>
<td>入口</td>
<td>呼ぶ人</td>
<td>意味</td>
</tr>
<tr>
<td>`GET /device/ws`</td>
<td>ESP32</td>
<td>WebSocket upgrade。認証成功で101。新接続を正として旧接続を閉じる</td>
</tr>
<tr>
<td>`POST /command`</td>
<td>iPhone</td>
<td>即時操作。設定を36文字へ変換して接続中のdevice socketへ書く</td>
</tr>
<tr>
<td>`GET /schedule`</td>
<td>iPhone</td>
<td>予約1件または `null` を返す</td>
</tr>
<tr>
<td>`PUT /schedule`</td>
<td>iPhone</td>
<td>予約を作成または置換する</td>
</tr>
<tr>
<td>`DELETE /schedule`</td>
<td>iPhone</td>
<td>予約とAlarmを削除する</td>
</tr>
</table>
#### `POST /command` の結果
<table header-row="true">
<tr>
<td>HTTP</td>
<td>アプリの意味</td>
</tr>
<tr>
<td>202 `{ "ok":true }`</td>
<td>Cloudflareが接続中のWebSocketへ `send()` した。**ESP32の処理完了やエアコン受理は意味しない**</td>
</tr>
<tr>
<td>400 `bad_request`</td>
<td>アプリが送った設定が不正</td>
</tr>
<tr>
<td>401 `unauthorized`</td>
<td>APP_TOKENが不一致</td>
</tr>
<tr>
<td>503 `device_offline`</td>
<td>device socketが無い、閉じている、または `send()` が例外になった</td>
</tr>
<tr>
<td>500 `server_error`</td>
<td>Cloudflareコードまたはストレージの予期しない失敗</td>
</tr>
</table>
DOはESP32の返事を待たないので、HTTPリクエストを保持するtimeout、`id`対応表、遅延応答処理は存在しない。
### 5.7 運用ログ
ログは障害判断に必要な出来事だけを1行JSONで出す。heartbeat成功や通常待機は記録しない。
<table header-row="true">
<tr>
<td>event</td>
<td>意味</td>
</tr>
<tr>
<td>`device_connected` / `device_disconnected`</td>
<td>ESP32接続の開始・終了</td>
</tr>
<tr>
<td>`command_sent` / `command_offline`</td>
<td>即時操作をsocketへ書いた / 接続がなかった</td>
</tr>
<tr>
<td>`schedule_set` / `schedule_deleted`</td>
<td>予約の作成・置換 / 削除</td>
</tr>
<tr>
<td>`schedule_fired_sent` / `schedule_fired_offline`</td>
<td>予約時刻に送った / 接続がなく捨てた</td>
</tr>
<tr>
<td>`server_error`</td>
<td>予期しないCloudflare側エラー</td>
</tr>
</table>
各行は `time` と `event` だけを必須にする。Bearer tokenは絶対に記録しない。36文字payloadとエアコン設定も通常は記録しない。
---
## 6. アプリ設計（iOS）
- Swift + SwiftUI。URLSessionで§5.6のHTTPS APIだけを呼ぶ
- **設定値の正本**をローカル保存し、操作のたびにフル設定を送る
- 202の表示は「送信要求を受け付けました」。**「エアコンが動きました」とは表示しない**
- 400はアプリの不具合、401はトークン設定、503はESP32の電源・Wi-Fi・接続、500はCloudflareログを確認する
- 予約画面はGET / PUT / DELETEの3操作だけ。予約は1件で、新規保存は置換
- LAN探索、Bonjour、ローカルネットワーク権限は使わない
- 配布: 自分用ならXcodeから直接。無料Apple IDは7日ごと再インストール、Apple Developer Program（年\$99）なら1年
ネイティブを選ぶ理由は将来の通知。通知を実装するまで、通知用のコードや権限は入れない。
---
## 7. コスト
<table header-row="true">
<tr>
<td>要素</td>
<td>月額</td>
</tr>
<tr>
<td>Cloudflare Workers + Durable Objects</td>
<td>**¥0**（現在の無料枠内。極端な連続再接続でも約35倍の余裕）</td>
</tr>
<tr>
<td>iOS アプリ</td>
<td>¥0（7日ごと再インストール）/ 年 \$99 で1年有効</td>
</tr>
<tr>
<td>**合計**</td>
<td>**¥0 / 月**</td>
</tr>
</table>
ただし**無料枠は契約ではない**。Heroku は無料枠を廃止したし、Durable Objects の無料枠は2025年4月に始まったばかり。将来変わるリスクを負っている。
---
## 8. ハードウェア構成
### 8.1 マイコン
**ideaspark ESP32 開発ボード（0.96インチ OLED 搭載）** — Amazon ASIN B0GZTFRDD2（¥1,199）
- ESP32-WROOM-32（240MHz デュアルコア / 4MB Flash）、CH340、**Micro-USB**
- チップ: ESP32-D0WD-V3 (rev v3.1) / MAC `f0:24:f9:ee:44:c0`
- ピン印字は DevKit V1 互換（D15 = GPIO15。番号のズレなし）
- 技適マークあり
### 8.2 使用ピン
<table header-row="true">
<tr>
<td>用途</td>
<td>ピン</td>
</tr>
<tr>
<td>赤外線 **送信** LED 駆動</td>
<td>GPIO4 (D4)</td>
</tr>
<tr>
<td>赤外線 **受信**モジュール 信号線</td>
<td>GPIO15 (D15) ※解析時のみ</td>
</tr>
<tr>
<td>（オンボードOLEDが占有）</td>
<td>GPIO21 (SDA) / GPIO22 (SCL)</td>
</tr>
</table>
**GPIO21 / GPIO22 は使わないこと。**
### 8.3 赤外線送信回路 — 採用版
NPNトランジスタ **S8050** のローサイドスイッチ。IR LED電流をESP32の3.3Vレギュレータから取らず、USB由来のVIN 5Vから取る。
```javascript
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
**組み立て規則**:
- LEDは3本を並列にするが、**各LEDに専用の直列抵抗を1本ずつ**入れる
- 最初は各100Ω。IR LEDの順方向電圧を約1.2V、トランジスタ降下を約0.2Vと置くと約36mA / 本、合計約108mAの目安
- 到達距離が不足した場合だけ、IR LEDの許容パルス電流を確認し、各68Ωへ下げて再測定する。47Ωから始めない
- GPIO4からBaseは220Ω。目安約11mAで駆動する
- Base–GNDの10kΩは必須。ESP32のリセット中にトランジスタが勝手にONになるのを防ぐ
- ESP32、VIN電源、トランジスタのGNDは共通にする
- S8050はメーカーやパッケージでピン順が異なりうる。**「刻印面からE-B-C」と決め打ちせず、手元部品のデータシートまたはテスターで確認する**
- IR LEDは透明な送信用940nm。黒い受信素子と取り違えない
100Ωで届かない場合は、抵抗を下げる前にLEDの向き、トランジスタのピン順、スマホカメラでの発光、設置角度を確認する。
### 8.4 設置前の電気試験
§8.3を組み、次を測るまで恒久設置しない。
<table header-row="true">
<tr>
<td>測るもの</td>
<td>合格条件</td>
</tr>
<tr>
<td>待機中</td>
<td>IR LEDが消灯し、トランジスタBaseがLOW</td>
</tr>
<tr>
<td>リセット中</td>
<td>IR LEDが点灯し続けない。10kΩプルダウンが効く</td>
</tr>
<tr>
<td>送信中のLED電流</td>
<td>各枝の実測値がIR LEDの許容パルス電流以下</td>
</tr>
<tr>
<td>送信中の3.3V</td>
<td>大きく降下せず、ESP32が再起動・文字化け・Wi-Fi切断しない</td>
</tr>
<tr>
<td>到達</td>
<td>予定設置位置からエアコンが安定して反応する</td>
</tr>
</table>
100Ωで到達すればそのまま採用する。届かない場合のみ68Ωを試し、電流・電圧・トランジスタ温度を再測定する。
**症状の見分け方**: 送信のたびにESP32が再起動する / シリアルが文字化けする / Wi-Fi切断が頻発する場合は、ソフトより先に電源・配線・電流を疑う。
**設置場所**: D16によりファーム変更はUSB作業なので、USBポートへ手が届くことを要件とする。
### 8.5 開発環境
- macOS / Arduino IDE 2.x
- ボード定義 esp32:esp32 **3.3.11** / ライブラリ IRremoteESP8266 **2.9.0**
- シリアルポート /dev/cu.usbserial-130、シリアルモニタ 115200
- **Upload Speed は 115200 に下げること**（921600 では CH340 の個体差で書き込みに失敗する）
- パーティションスキーム **Huge APP (3MB No OTA/1MB SPIFFS)**（§4.7）
### 8.6 手持ちの部材
**新規購入**
- ideaspark ESP32 開発ボード（OLED付き）× 1
- 赤外線 LED（940nm、送信用）× 10（DAOKAI セット）
- 赤外線受信モジュール × 10（同セットに同梱）
- ブレッドボード 400穴 × 5（サムコス）
- USB-C to Micro-USB ケーブル（データ転送対応）
**ELEGOO Mega2560 スタータキットから流用**
- NPNトランジスタ S8050 / PN2222 × 10
- 抵抗各種、ジャンパワイヤ
- §8.3用の100Ω × 3、220Ω × 1、10kΩ × 1を確保する。不足時は購入
- 赤外線受信モジュール、リモコン
- Mega2560 本体（IRremoteESP8266 は ESP32/ESP8266 専用のため本プロジェクトでは未使用）
### 8.7 リポジトリに残してあるもの
tools/ の3つのスケッチ（旧設計に依存しない実験ツール）だけ。
- ir_led_check — 赤外線 LED が光っているかを見る（スマホのインカメラ越しに見る）
- ir_loopback_test — 送信した信号を自分で受信できるか。赤外線送信が動いたときのコード
- ir_dump — リモコンの信号を採取し、貼り付け可能な形で出力
---
## 9. 実装の根拠として確定した事実
### 赤外線 / ライブラリ
- 対象は三菱電機製。`MITSUBISHI_AC`、144 bits / 18バイト
- v1は `IRsend::send(MITSUBISHI_AC, const uint8_t*, 18)` だけを使う
- 38kHz搬送波はソフトウェアのビジーウェイトで、送信は約0.5秒
- 対象機は設定全体を毎回送る方式。再操作しても危険なトグルにならず、最後に届いたフル設定になる
- 電源OFFも18バイトのフル設定として生成できる
- 風量`auto`はライブラリ既定値ではなく、実機に合わせ byte9 bit7を0に補正する
- IRremoteESP8266自体は多数の方式を持つが、**v1の機器契約は三菱18バイトだけ**。将来互換性の根拠には使わない
### ESP32 / プラットフォーム
- ESP32 core 3.3.11、IRremoteESP8266 2.9.0に固定
- `CONFIG_ESP_TASK_WDT_CHECK_IDLE_TASK_CPU1` は既定で未設定。実装で `enableCore1WDT()` を呼び、core 1のIDLE監視を有効にする。標準timeoutは5秒
- `CONFIG_MBEDTLS_CERTIFICATE_BUNDLE=y`。CA bundle APIは使えるが、実ポインタとサイズが必要。nullは検証なし接続になる
- Arduino WiFiは既定で資格情報をNVSへ永続化するため、最初のWi-Fi初期化前に `WiFi.persistent(false)` が必要
- `Huge APP (3MB No OTA/1MB SPIFFS)` はapp 3MB × 1。未使用のSPIFFS 896KiBとNVS / otadata / coredump領域も残る
### Cloudflare
- Workers FreeでSQLite-backed Durable Objects、WebSocket Hibernation、Alarmが使える
- Hibernation中は通常のJavaScriptメモリが消えるが、WebSocketはCloudflare runtimeが保持し、`ctx.getWebSockets()` で再取得できる
- WebSocketプロトコルpingにはruntimeが自動pongし、Durable Objectを起こさない
- Alarmは少なくとも1回実行され、handlerが例外終了すると最大6回自動再試行される。したがって§5.4の「予約を先に削除」が必要
---
## 10. 破棄した案と理由
同じ検討を繰り返さないための記録。
<table header-row="true">
<tr>
<td>案</td>
<td>破棄理由</td>
</tr>
<tr>
<td>BLE</td>
<td>到達距離が10〜30m と短い</td>
</tr>
<tr>
<td>Tailscale / VPN</td>
<td>ESP32 に載らない。家に subnet router 役の機械が要る。C1 に反する</td>
</tr>
<tr>
<td>HomeKit ハブ / Home Assistant</td>
<td>家に別の機械が要る。C1 に反する</td>
</tr>
<tr>
<td>ポート開放 + DDNS</td>
<td>家のルーターに穴を開ける</td>
</tr>
<tr>
<td>ESP32 がパケットを組み立てる</td>
<td>一番変わりやすい知識。ビット修正やモード追加のたびに焼き直しになる（D8）</td>
</tr>
<tr>
<td>ESP32 がタイマーを発火</td>
<td>曜日・繰り返し・タイムゾーンは仕様が動く（D4）</td>
</tr>
<tr>
<td>LAN 直通経路</td>
<td>実装が複雑になる。クラウド経由でリアルタイム要件は満たせる（D2）</td>
</tr>
<tr>
<td>アプリのプリセットキャッシュ / encode と command の分離</td>
<td>**「家のネットが落ちても操作できるべき」という要件を勝手に作ったため**。家の Wi-Fi が死んでいるならそちらを直すべき</td>
</tr>
<tr>
<td>ESP32 内蔵 Web UI（リモコン画面）</td>
<td>D8 で ESP32 が意味を知らなくなったので描けない。D2 で経路もない</td>
</tr>
<tr>
<td>Wi-Fi の AP フォールバック / プロビジョニング</td>
<td>D3。ルーター交換は数年に1度。その時だけケーブルを挿す</td>
</tr>
<tr>
<td>ir_raw（生タイミング送信）</td>
<td>現在の三菱エアコンは固定18バイトの `MITSUBISHI_AC` 送信で足りる。照明・テレビは今回の範囲外</td>
</tr>
<tr>
<td>**OTA（遠隔ファーム更新）**</td>
<td>**最有力の変更理由（ルーター交換＝オフライン）に効かない。** 残る用途は机上の調整期に消化される。ロールバック機構・SHA256 検証は OTA 自身が持ち込んだリスクへの対策でしかない。焼き込みトークンの漏洩リスクも一段上がる（D16 / §11.4）</td>
</tr>
<tr>
<td>`id / op / proto`、JSON、ESP32の応答</td>
<td>応答を待ってもエアコン受理は確認できず、ESP32のタスク間通信とCloudflareの待機表が増える。36文字固定・応答なしへ変更（D10 / §11.5）</td>
</tr>
<tr>
<td>`v / fw / up / info / ota`</td>
<td>現在の送信結果を変えない。遠隔診断・OTAを採らないため、必要時はUSBとシリアルログを使う</td>
</tr>
<tr>
<td>指数バックオフ / ジッタ / 2段待機</td>
<td>1台ではジッタ不要。2段方式の回復速度差より、**失敗後は毎回30秒**という1規則を優先（D17 / §11.6）</td>
</tr>
<tr>
<td>Durable Object がエアコンの状態を保持</td>
<td>必要な場面がなかった。アプリが毎回フル状態を送れば差分計算は不要。予約は「18時にこのバイト列」と命令として持てばよく、その方が挙動も明確。そもそも C3 によりどこに置いても推測値でしかない（D15）</td>
</tr>
<tr>
<td>Azure IoT Hub</td>
<td>成立するが、Functions が必須とするストレージが永久無料外。また SAS トークンの分 ESP32 のファームが重くなる</td>
</tr>
<tr>
<td>Oracle Cloud Always Free の VM</td>
<td>Linux の運用が発生。ARM は在庫が取れない。アイドルだと回収される</td>
</tr>
<tr>
<td>GitHub Actions の cron をスケジューラに</td>
<td>スケジュール実行が大きく遅延しうる。「18時につける」に使えない</td>
</tr>
</table>
---
## 11. 決定の記録と未決事項
### 11.1 「届いたか」を確かめる手段 — **載せない（決定・D12）**
最小構成を優先し、確認手段は一切載せない。C3（エアコンは状態を返さない）は割り切る。**ESP32からのアプリ用応答も廃止した。** HTTP 202が意味するのはCloudflareが接続中のWebSocketへ書き込んだところまで。
**後から入れるには配線のやり直しが要る**（マイクも受信モジュールも物理追加）。それを承知で最小構成を採る。
検討した選択肢の記録:
<table header-row="true">
<tr>
<td>手段</td>
<td>確認できること</td>
<td>分からないこと</td>
<td>速さ</td>
<td>コスト</td>
</tr>
<tr>
<td>**「ピッ」音を聞く**</td>
<td>**エアコンが受理した**</td>
<td>実際に効いたか</td>
<td>約1秒</td>
<td>マイク ¥300〜800</td>
</tr>
<tr>
<td>自分の赤外線を自分で受信</td>
<td>LED が正しい波形で光った。搬送波の歪みも捕まる</td>
<td>エアコンに届いたか</td>
<td>即時</td>
<td>**部品は手元にある**</td>
</tr>
<tr>
<td>温度センサー</td>
<td>実際に効いた</td>
<td>遅い</td>
<td>数分〜</td>
<td>¥500〜1500</td>
</tr>
</table>
将来これらを入れる場合は、ESP32からCloudflareへの新しい結果メッセージが必要になる。現在は**最小構成を優先して採らない**。
将来入れる場合のメモ: 「ピッ」音は振幅ではなく**周波数で見る**こと（Goertzel アルゴリズム。FFT 不要）。事前にスマホで録音して、周波数・長さ・同じ設定を2回送っても2回目も鳴るかを実測する。
### 11.2 WebSocket ライブラリ — **WebSockets（Links2004）に決定（D14）**
WebSockets（Links2004 / arduinoWebSockets）を使う。ただし、ライブラリに再接続ポリシーや安全な TLS 既定値まで委ねる設計ではない。
<table header-row="true">
<tr>
<td>確認項目</td>
<td>結論</td>
</tr>
<tr>
<td>CA バンドル</td>
<td>`beginSslWithBundle(host, port, url, CA_bundle, size, protocol)` が ESP32 向けにある。**非 null ポインタと実サイズを渡すことが必須**</td>
</tr>
<tr>
<td>再接続制御</td>
<td>接続処理は `loop()` 内で起きる。したがって `loop()` を呼ぶ状態をESP32側の状態機械が制限し、30秒の待機中は呼ばない</td>
</tr>
<tr>
<td>heartbeat</td>
<td>`enableHeartbeat(pingInterval, pongTimeout, disconnectCount)` がある。§4.6 の 30秒 / 10秒 / 2回を使う</td>
</tr>
</table>
実装上の注意:
- CA bundle が null の場合、ライブラリは `setInsecure()` に落ちる。**null / size 0 を初期化エラーとして拒否する**
- `webSocket.disconnect()` を呼んでから Wi-Fi を OFF にする
- arduino-esp32 3.3.11 の TLS handshake 既定値は120秒で、同期接続中はアプリ側の15秒期限を越えてブロックしうる。30秒は hard interval ではない
- この制約を受け入れる限り、パッチ・fork・自前クライアントは不要
根拠: [WebSocketsClient.cpp](https://github.com/Links2004/arduinoWebSockets/blob/master/src/WebSocketsClient.cpp)、[NetworkClientSecure.cpp（arduino-esp32 3.3.11）](https://github.com/espressif/arduino-esp32/blob/3.3.11/libraries/NetworkClientSecure/src/NetworkClientSecure.cpp)
### 11.3 キープアライブ
キープアライブが要るのは **WebSocket だからではなく、常時接続を選んだから**。役割は次の2つ。
1. 家庭用ルーターなどの NAT エントリを維持する
2. **TCP が無言で切れたゾンビ接続を検出する**
初期値は `enableHeartbeat(30000, 10000, 2)`。30秒ごとに WebSocket ping を送り、pong を10秒待ち、2回連続で返らなければ切断として §4.8 の `TEARDOWN` へ遷移する。Cloudflare Durable Objects はプロトコル ping に自動 pong できるため、この生存確認で Hibernation を解除しない。
ポーリングでなく常時接続を選んだ理由:
<table header-row="true">
<tr>
<td></td>
<td>短いポーリング</td>
<td>ロングポーリング</td>
<td>**WebSocket + Hibernation**</td>
</tr>
<tr>
<td>即時性</td>
<td>✗ 5〜10秒遅れる</td>
<td>✓</td>
<td>**✓**</td>
</tr>
<tr>
<td>アイドル時の課金</td>
<td>少ない</td>
<td>**✗ 待っている時間が実行時間として課金される**</td>
<td>**✓ ゼロ**</td>
</tr>
<tr>
<td>ESP32 の負荷</td>
<td>**✗ TLS handshake を繰り返す**</td>
<td>中</td>
<td>**✓ 接続確立・障害復旧時だけ**</td>
</tr>
</table>
初期値は仕様として固定するが、経路上の NAT とライブラリ挙動は §11.7 で実測する。根拠: [Cloudflare Durable Objects — WebSocket Hibernation](https://developers.cloudflare.com/durable-objects/best-practices/websockets/)
### 11.4 OTA — **実装しない（決定・D16）**
「D1 のコストを払う方法は2つある（ファームを変えなくて済むほど小さくする / 変えること自体を安くする）」という発想で入れていたが、後者はこの構成では成立しなかった。
<table header-row="true">
<tr>
<td>検証</td>
<td>結果</td>
</tr>
<tr>
<td>最有力の変更理由に効くか</td>
<td>**効かない。** ルーター交換＝SSID/パスワード変更（D3）の時、ESP32 はオフラインなので OTA では絶対に直せない</td>
</tr>
<tr>
<td>残る用途は何か</td>
<td>30秒の待機値は机上試験中に決める。新機器・別プロトコル対応はUSB再書き込みでよい。現在の三菱エアコンには固定18バイト送信だけで足りる</td>
</tr>
<tr>
<td>OTA 自体のコスト</td>
<td>app スロットが2つ要る。ロールバック機構・SHA256 検証・「接続できて初めて確定」のロジックは、**すべて OTA 自身が持ち込んだリスクへの対策**</td>
</tr>
<tr>
<td>セキュリティ</td>
<td>ローテーションできない焼き込みトークンの漏洩が、「エアコンを操作される」から**「家庭内ネットワークの機器に任意のコードを流し込まれる」**に跳ね上がる（§5.5）</td>
</tr>
</table>
**代償**: 今後あらゆるファーム変更に物理アクセスが必要。対策はソフトではなくハード側 — **USB ポートに手が届く場所に設置する**（§8.4）。
**得たもの**: §4.11 の三層分類が消滅し、「焼く前に決めきらないと二度と直せない項目」がゼロになった。パーティション選択すら焼き直しで変えられる。
### 11.5 機器プロトコル — 36文字だけ（D10）
当初はJSONに `id / op / proto / state` を入れ、ESP32から `ok / error / fw / up` を返す案だった。これは「ESP32の送信処理まで完了した」と確認できる一方、次の状態と分岐を増やす。
- ESP32のJSON解析と複数エラー
- IR送信タスクへの受け渡しと完了通知
- Cloudflareの `id → 待機中HTTP` 対応表とtimeout
- 遅れて届いた応答、切断中の応答、busyの処理
しかし応答があっても、C3によりエアコンが受理したかは分からない。所有者が管理する複雑さに対して確認できる範囲が狭いため、**中間確認ごと廃止した**。
v1の契約は次の1文で完結する。
> **Cloudflareは36文字の大文字16進を1フレーム送る。ESP32は18バイトのMITSUBISHI_ACとして送信し、何も返さない。**
`v / fw / up` も遠隔診断には使えるが、現在の動作判断には使わない。必要になったらUSB接続とシリアルログで調べる。
### 11.6 再接続 — 30秒固定（D17）
再接続は障害を直す処理ではなく、回復したかを確認する処理。以前の10秒→60秒の2段方式にも小さな利点はあったが、切断開始時刻・段の切替・ONLINE後のリセットという状態が増える。
現在は次の1規則だけ。
> **接続試行が終わったら後始末して無線を切り、30秒待って最初からやり直す。**
- 1日中失敗し、毎回Cloudflareまで到達しても最大約2,880回 / 日で、100,000 req / 日を大きく下回る
- 待機中はWi-FiをOFFにするので、連続スキャンを避けられる
- 30秒は試行開始周期ではない。TLS内部処理など、試行にかかった時間は別に加わる
- 30秒以内の回復速度と60秒方式の省電力差より、所有者が覚える規則を1つにする方を優先する
### 11.7 実装前・設置前の確認項目
- 36文字の大文字16進だけで赤外線送信し、短い・長い・小文字・空白・binary frameは無視すること
- ESP32がアプリ用WebSocketメッセージを一切返さないこと
- 連続する複数フレームを独自キューなしで順番に同期送信できること
- Wi-Fi 15秒、NTP 10秒の期限が働くこと。時刻が2024-01-01 UTC以上ならNTPを省略すること
- TLS接続不能時の内部ブロック時間を測り、CA bundleの正しいホストは成功、誤ホスト・未信頼証明書は失敗すること
- heartbeat 30秒 / pong 10秒 / 2回で、AP切断・ルーター再起動・ISP断を検知すること
- すべての接続失敗で WebSocket後始末 → Wi-Fi OFF → 30秒待機 → 再接続になること
- 接続失敗を24時間繰り返してもheapが減り続けないこと
- 新しいESP32 WebSocketが古い接続を置き換え、同じ命令を2台へ送らないこと
- `POST /command` が202 / 400 / 401 / 503 / 500を§5.6どおり返すこと
- Durable Objectが実際にhibernateした後も `ctx.getWebSockets("device")` で接続を取得できること
- Alarm処理の各行で例外を注入し、予約が二重送信されないこと
- §8.4の5V給電、ベースプルダウン、送信中電圧・電流を実測すること
### 11.8 実装後の完了条件
- 上記試験がすべて通る
- iPhone、Cloudflare、ESP32の3つを通して実機エアコンが操作できる
- ルーター電源断から復旧後、手動操作なしで再接続する
- 24時間の切断試験で再起動ループ・heap減少・二重送信がない
- USBポートへ手が届く状態で恒久設置できる
---
## 12. 所有者向けの障害判断
<table header-row="true">
<tr>
<td>見えていること</td>
<td>意味</td>
<td>最初にすること</td>
</tr>
<tr>
<td>アプリが400</td>
<td>アプリが不正な設定を送った</td>
<td>アプリの入力生成を確認する</td>
</tr>
<tr>
<td>アプリが401</td>
<td>APP_TOKENがCloudflareと一致しない</td>
<td>Worker secretとアプリ設定を合わせる</td>
</tr>
<tr>
<td>アプリが503</td>
<td>Cloudflareから見てESP32の接続がない</td>
<td>ESP32の電源 → 家のWi-Fi → ルーターの順に確認する。復旧後は最大「現在の試行時間＋30秒程度」待つ</td>
</tr>
<tr>
<td>アプリが500</td>
<td>Cloudflareコードまたはストレージの失敗</td>
<td>Worker Logsを見る。ESP32を再起動しない</td>
</tr>
<tr>
<td>アプリが202、エアコンが動かない</td>
<td>Cloudflareは送ったが、ESP32完了・赤外線到達・エアコン受理のどこかは分からない</td>
<td>一度だけ再操作する。続くならESP32の電源とIR LEDを確認し、必要ならUSBシリアルを見る</td>
</tr>
<tr>
<td>送信時にESP32が再起動する</td>
<td>ソフトより電源・過電流の可能性が高い</td>
<td>§8.4の5V / 3.3V電圧とLED電流を測る</td>
</tr>
<tr>
<td>予約だけ動かない</td>
<td>予約レコード、Alarm、発火時のESP32接続のどれか</td>
<td>`GET /schedule` → Worker Logsの `schedule_fired_sent` / `schedule_fired_offline` の順に確認する</td>
</tr>
</table>
### 管理するものはこれだけ
- Cloudflare Workerプロジェクト1つ
- Durable Object `"home"` 1個
- secrets 2つ（APP_TOKEN / DEVICE_TOKEN）
- 永続データは予約1件
- ESP32ファーム1つ
- iOSアプリ1つ
これ以外のサーバー、DB管理画面、メッセージブローカー、証明書更新ジョブは持たない。
---
## 13. Cloudflareの18バイト生成
この章は赤外線形式の付録。ネットワーク処理から独立した **`encode(setting) -> 36文字`**** の純粋関数**として実装する。
### 13.1 固定部分
<table header-row="true">
<tr>
<td>byte</td>
<td>値</td>
<td>意味</td>
</tr>
<tr>
<td>0〜4</td>
<td>`23 CB 26 01 00`</td>
<td>MITSUBISHI_ACの固定signature</td>
</tr>
<tr>
<td>10〜14</td>
<td>`00 00 00 00 00`</td>
<td>エアコン内蔵タイマーを使わない</td>
</tr>
<tr>
<td>15〜16</td>
<td>`10 00`</td>
<td>実機リモコンから取得した固定値</td>
</tr>
<tr>
<td>17</td>
<td>byte 0〜16の合計の下位8bit</td>
<td>checksum</td>
</tr>
</table>
### 13.2 可変部分
<table header-row="true">
<tr>
<td>byte</td>
<td>作り方</td>
</tr>
<tr>
<td>5</td>
<td>`power=true`なら`20`、falseなら`00`</td>
</tr>
<tr>
<td>6</td>
<td>`auto=20`、`cool=18`、`dry=10`、`heat=08`、`fan=38`</td>
</tr>
<tr>
<td>7</td>
<td>`temp - 16`。16℃=`00`、31℃=`0F`</td>
</tr>
<tr>
<td>8</td>
<td>`auto=30`、`cool=36`、`dry=32`、`heat=30`、`fan=37`。上位4bitの`3`で水平風向を中央固定</td>
</tr>
<tr>
<td>9</td>
<td>`40 OR (vane値 << 3) OR fan値`</td>
</tr>
</table>
`fan値`: `auto=0`、`quiet=5`、`1=1`、`2=2`、`3=3`、`4=4`。
`vane値`: `auto=0`、`highest=1`、`high=2`、`middle=3`、`low=4`、`lowest=5`、`swing=7`。
実機リモコンに合わせ、byte 9のbit7（IRremoteESP8266の`FanAuto`）は常に0。上の式にはbit7を立てる処理を入れない。
### 13.3 必須テストベクトル
<table header-row="true">
<tr>
<td>設定</td>
<td>期待する36文字</td>
</tr>
<tr>
<td>ON / dry / 24℃ / auto / middle（実機取得済み）</td>
<td>`23CB260100201008325800000000001000E7`</td>
</tr>
<tr>
<td>ON / cool / 26℃ / auto / auto</td>
<td>`23CB26010020180A364000000000001000DD`</td>
</tr>
<tr>
<td>OFF / cool / 26℃ / auto / auto</td>
<td>`23CB26010000180A364000000000001000BD`</td>
</tr>
<tr>
<td>ON / heat / 20℃ / 4 / low</td>
<td>`23CB260100200804306400000000001000E5`</td>
</tr>
</table>
4件が一致するまでネットワーク処理へ組み込まない。encoderは現在時刻・保存状態・Cloudflare APIを参照しない。
---
## 14. 実装順序
一度に1つの境界だけを増やす。
<table header-row="true">
<tr>
<td>段階</td>
<td>作るもの</td>
<td>完了条件</td>
</tr>
<tr>
<td>1. Encoder</td>
<td>Cloudflareの純粋関数と§13.3のunit test</td>
<td>4テストが一致。ネットワークなし</td>
</tr>
<tr>
<td>2. 赤外線</td>
<td>§8.3の回路と、USBシリアルから36文字を受けて送信するESP32試験コード</td>
<td>実機エアコンが予定位置から安定して反応し、§8.4の電気試験に合格</td>
</tr>
<tr>
<td>3. 機器接続</td>
<td>`GET /device/ws`、認証、Hibernation、ESP32の接続・30秒再接続</td>
<td>`device_connected`が出て、hibernate後もsocketを再取得できる</td>
</tr>
<tr>
<td>4. 即時操作</td>
<td>`POST /command`。最初はcurl等で呼ぶ</td>
<td>202 / 400 / 401 / 503 / 500を再現し、202で実機が動く</td>
</tr>
<tr>
<td>5. 障害系</td>
<td>AP断、ルーター再起動、誤証明書、長時間接続失敗</td>
<td>§11.7のネットワーク試験と24時間heap試験に合格</td>
</tr>
<tr>
<td>6. iOS</td>
<td>フル設定、即時操作、§12のエラー表示</td>
<td>アプリから実機操作でき、202を「動作確認」と表示しない</td>
</tr>
<tr>
<td>7. 予約</td>
<td>GET / PUT / DELETE scheduleとAlarm</td>
<td>置換・取消・offline時破棄・例外時の二重送信なしを確認</td>
</tr>
<tr>
<td>8. 設置</td>
<td>配線固定、USBアクセス確保、最終通し試験</td>
<td>§11.8をすべて満たす</td>
</tr>
</table>
各段階が終わるまで次へ進まない。問題が起きた時は、その段階で新しく加えた境界だけを調べる。
