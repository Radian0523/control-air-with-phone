# Architecture Decision Records

状態: Accepted  
基準日: 2026-09-13  
現行仕様: [設計](./design.md)  
原本: [Notionエクスポート](./notion-design-export.md)

このプロジェクトは小規模なため、設計判断を1ファイルにまとめる。各記録は「実装方法」ではなく、「何を選び、何を捨て、どの代償を受け入れたか」を残す。

## 判断原則

判断の優先順位は次のとおり。

1. 所有者が正常時、失敗時、復旧方法を理解し管理できる
2. 物理安全と通信の安全を守る
3. 現在の要件を満たす
4. ESP32の責務を小さくする
5. 複雑さが必要ならESP32よりクラウド、クラウドよりアプリへ置く

コンポーネント数だけでなく、所有者が覚える概念と分岐の数を最小化する。将来だけ必要な機能は、必要になった時に追加する。

## ADR-001: ESP32の責務を最小化する

状態: Accepted

### 文脈

ESP32は物理的にエアコンへ赤外線を送れる唯一の機器である。一方、設置後のファーム変更にはUSB接続が必要で、複雑なファームほど理解、検証、復旧が難しくなる。

### 決定

ESP32は接続維持、固定形式の検証、赤外線送信だけを担当する。将来機能を先回りして載せない。必要な変更はUSBで書き換える。

### 結果

- JSON、状態管理、タイマー、OTA、HTTPサーバーをESP32へ載せない
- エアコン設定の意味と18バイト生成はクラウドへ置く
- 設置場所からUSBへアクセスできる必要がある

## ADR-002: LAN直通経路を作らず、クラウド経由だけにする

状態: Accepted

### 文脈

外出先からの操作が必須である。LAN経路を追加すると、ローカル探索、別認証、経路選択、二重の障害判断が必要になる。

### 決定

iPhoneからの操作は常にCloudflareを経由する。LAN直通、Bonjour、ポート開放、DDNS、VPNを実装しない。

### 結果

- 家庭ルーターへ穴を開けない
- 家庭インターネットまたはCloudflareが停止中は操作できない
- アプリとESP32が管理する通信経路は1つになる

## ADR-003: Wi-Fi資格情報をファームウェアへ焼き込む

状態: Accepted

### 文脈

個人用の1台であり、ルーター変更はまれである。Wi-Fi設定画面やAPフォールバックはファーム、UI、認証、復旧手順を増やす。

### 決定

SSIDとパスワードをファームウェア定数にする。再設定機構を作らない。ルーター変更時はUSBで書き換える。

### 結果

- 初期設定と通常運用が単純になる
- ルーター変更時は物理アクセスが必要になる
- `WiFi.persistent(false)`を使い、ドライバによるNVSへの重複保存は行わない

## ADR-004: 予約時刻と業務時刻をクラウドが持つ

状態: Accepted

### 文脈

予約をESP32へ置くと、時計、タイムゾーン、永続化、仕様変更をファームが担当することになる。一方、TLS証明書検証にはESP32側にも概算UTCが必要である。

### 決定

予約と業務時刻はCloudflareが持つ。ESP32はTLS検証に必要な場合だけNTPで概算UTCを同期する。

### 結果

- ESP32は予約を保存、発火しない
- NTP失敗は接続失敗として共通の復旧経路へ入る
- ESP32の時刻はエアコン操作の判断には使わない

## ADR-005: 命令を自動再送しない

状態: Accepted

### 文脈

赤外線は片方向で、エアコンが受理したか確認できない。再送すると二重送信の可能性が生じ、再送回数、待機、履歴の状態が増える。

### 決定

即時命令と予約命令を自動再送しない。通信接続だけはADR-017に従って繰り返す。

### 結果

- 一時的な未達は許容する
- 利用者は必要なら一度だけ再操作する
- Alarmでは二重送信を避けるため、予約を削除してから送信する

## ADR-006: 物理安全はESP32と回路で担保する

状態: Accepted

### 文脈

単純化のために監視機能を減らしても、GPIO暴走、過電流、リセット中の誤点灯は機器の損傷につながりうる。

### 決定

安全に関係する処理と部品は削らない。GPIO出力ラッチの初期化、Task Watchdog、Baseプルダウン、LEDごとの電流制限抵抗、設置前の電流・電圧測定を必須とする。

### 結果

- 回路部品と試験項目は残る
- 到達距離より許容電流を優先する
- 100Ωで不足する場合だけ、測定しながら68Ωを試す
- Task WDTは`enableCore1WDT()`、core 1のidle hook登録、`loop()`末尾の`delay(1)`の3点セットで使う。2026-09-17の段階2c試験で、hookなし・譲らない`loop()`のどちらでも5秒ごとに再起動する事象を確認した。core 3.xの`enableCore1WDT()`はIDLE1を監視対象に追加するだけでhookを登録しない
- Base抵抗は220Ωを維持する。GPIOの約11.8mAは`pinMode`で使われる既定の駆動強度2における約20mAを下回り、約108mAのcollector電流に対してforced betaを低く取れる。最終判断は実測値を使う

## ADR-007: Cloudflare WorkersとDurable Objectsを使う

状態: Accepted

### 文脈

外出先から操作するため、ESP32の外向き接続を受けるクラウドが必要である。常時VMや家庭内の追加機器は管理対象を増やす。

### 決定

1つのCloudflare WorkerプロジェクトへWorker入口とDurable Objectクラスを同居させる。Durable Objectは`"home"`を1個だけ使う。

### 結果

- WebSocket保持、一発予約、Alarmを1サービスで扱える
- 想定利用量は現在の無料枠内だが、無料枠の将来継続は保証されない
- Cloudflare固有のHibernation APIとAlarmへ依存する

### 不採用案

- Azure IoT Hub: Functions用ストレージとSAS token管理が増える
- Oracle Cloud VM: OS運用とインスタンス管理が増える
- GitHub Actions cron: 実行遅延が予約用途に合わない

## ADR-008: 赤外線データをCloudflareで生成する

状態: Accepted

### 文脈

モードやビット配置は変更されやすい機器固有知識である。ESP32へ置くと、変換規則の修正ごとにUSB書き換えが必要になる。

### 決定

Cloudflareの純粋関数がアプリ設定を三菱エアコン用18バイトへ変換する。ESP32はその意味を解釈しない。

### 結果

- 変換規則をネットワークなしで単体テストできる
- ESP32は別のエアコン方式へ動的対応できない
- 機器変更時はCloudflareの変換と、必要ならESP32ファームを変更する
- 2026-09-13〜16 の実機採取で、byte 9 は電源ボタンのフルステートフレームでは常に `40 | vane<<3 | fan` の形であり、ボタン直後だけ現れる `98` / `81` の形は採用しない。byte 15 はリモコンでは `10` と `00` の両方が現れ、エアコンは両方を受理するため `10` 固定を維持する

## ADR-009: iOSネイティブアプリを使う

状態: Accepted

### 文脈

利用者は本人であり、将来通知を追加する可能性がある。現在は通知を必要としない。

### 決定

SwiftとSwiftUIでiOSネイティブアプリを作る。通知を実装するまでは通知用コードや権限を追加しない。

### 結果

- 設定値の正本を端末へ保存する
- 自分用配布はXcodeから行える
- 無料Apple IDでは7日ごとの再インストールが必要で、長期配布にはApple Developer Programが必要になる

## ADR-010: 機器プロトコルを36文字の一方向メッセージにする

状態: Accepted

### 文脈

当初案はJSONへ`id`、`op`、`proto`、`state`を入れ、ESP32が`ok`、`error`、`fw`、`up`を返すものだった。しかしESP32の送信完了を確認しても、エアコンの受理は確認できない。

JSONと応答を採用すると、ESP32の解析とエラー処理、タスク間完了通知、Cloudflareの`id`対応表、timeout、遅延応答、busy処理が必要になる。

### 決定

Cloudflareは18バイトを表す36文字の大文字16進テキストを1フレーム送る。方式は`MITSUBISHI_AC`固定とし、ESP32はアプリ用応答を返さない。

### 結果

- `id`、`op`、`proto`、JSON、`ok`、`error`、`v`、`fw`、`up`を廃止する
- HTTP 202はCloudflareがWebSocketで`send()`を呼んだことだけを示す
- 電源断直後などは古いsocketへの`send()`が成功扱いとなり、202でもESP32へ届かないことがある
- 遠隔からファームバージョンや稼働時間を取得できない
- 必要な診断はUSBシリアルで行う

## ADR-011: 予約を一発1件だけにする

状態: Accepted

### 文脈

利用者は繰り返し予約を使わない。複数予約や繰り返しは、ID、一覧、競合、タイムゾーン、編集規則を増やす。

### 決定

予約は最大1件の一発予約だけとする。新しい予約は古い予約を置き換える。

### 結果

- 永続データは予約1レコードだけになる
- APIは取得、置換、削除の3操作で済む
- 複数予約や曜日指定はできない
- `executeAt`はUTCを明示するRFC 3339だけを受理し、現在以前と不正日時は拒否する
- 未来側の独自上限は設けない
- 予約がなければAPIは`null`を返し、発火済みとキャンセル済みを区別する履歴は持たない

## ADR-012: エアコン受理の確認手段を載せない

状態: Accepted

### 文脈

赤外線送信後の確認候補には、エアコンの「ピッ」音を聞くマイク、自分の赤外線を受ける受信モジュール、温度センサーがある。それぞれ追加配線、解析、状態、誤検知を持ち込む。

### 決定

マイク、自己受信、温度センサーを製品構成へ載せない。ESP32のアプリ用応答も返さない。

### 結果

- Cloudflare以降の到達位置を遠隔から判定できない
- 202でもエアコンが動かないことがある
- 将来追加する場合は、センサー配線とESP32からCloudflareへの結果メッセージが必要になる

## ADR-013: 静的Bearer tokenを2つ使う

状態: Accepted

### 文脈

個人用の1ユーザー、1デバイスであり、ユーザー管理やCloudflare Accessは過剰である。一方、アプリ用資格情報と機器用資格情報は漏洩時の交換方法が異なる。

### 決定

`APP_TOKEN`と`DEVICE_TOKEN`を別々のWorker secretとして持ち、Authorization Bearerで照合する。Workerでは両方をSHA-256へ変換してから`crypto.subtle.timingSafeEqual`で比較する。APP_TOKENはiOSの設定画面から一度入力し、Keychainへ保存する。

### 結果

- アプリ側tokenの交換ではESP32を書き換えなくてよい
- DEVICE_TOKENの交換にはUSB書き換えが必要になる
- tokenをログへ出力しない
- 複数ユーザー、失効一覧、権限レベルは持たない
- APP_TOKENをUserDefaults、ソースコード、リポジトリへ保存しない

参考: [Cloudflare Workers — timingSafeEqual](https://developers.cloudflare.com/workers/examples/protect-against-timing-attacks/)

## ADR-014: ESP32のWebSocketライブラリにarduinoWebSocketsを使う

状態: Accepted

### 文脈

CA bundleとheartbeatを使えるライブラリが必要である。再接続方針と安全なTLS設定までライブラリ既定値へ任せることはできない。

### 決定

Links2004のarduinoWebSockets 2.7.2を使う。再接続状態はファーム側で管理し、1回の`CONNECTING`につき接続試行を1回だけにする。CA bundleのポインタと実サイズを明示する。CA bundleはMozilla NSS root store由来のfull bundleとする。

### 結果

- `beginSslWithBundle()`と`enableHeartbeat()`を使える
- CA bundleがnullまたはsize 0なら接続を拒否する必要がある
- full bundleがFlashを約77.2KB使うことを受け入れる
- Cloudflareの証明書発行元変更には広く対応できるが、root store更新時はUSBでファームを書き換える
- TLS handshakeが内部で最大120秒程度ブロックしうる制約を受け入れ、実機で測る
- この制約を受け入れる限り、ライブラリをforkしない
- `CONNECTING`開始時は再接続間隔0で最初の試行を直ちに開始し、その直後に30秒へ変更して同一サイクル内の再試行を防ぐ
- OFF_WAIT中は`loop()`を呼ばない

参考:

- [arduinoWebSockets 2.7.2 WebSocketsClient.cpp](https://github.com/Links2004/arduinoWebSockets/blob/2.7.2/src/WebSocketsClient.cpp)
- [arduino-esp32 3.3.11 NetworkClientSecure.cpp](https://github.com/espressif/arduino-esp32/blob/3.3.11/libraries/NetworkClientSecure/src/NetworkClientSecure.cpp)
- [ESP-IDF 5.5 — ESP x509 Certificate Bundle](https://docs.espressif.com/projects/esp-idf/en/v5.5/esp32/api-reference/protocols/esp_crt_bundle.html)

## ADR-015: エアコン状態の正本をiOSアプリに置く

状態: Accepted

### 文脈

エアコンは状態を返さないため、クラウドが状態を持っても推測値でしかない。差分命令には現在状態が必要だが、三菱の赤外線は毎回フル状態を送れる。

### 決定

iOSアプリを設定値の正本とし、操作ごとにフル設定を送る。Durable Objectはエアコンの現在状態を保存しない。

### 結果

- 差分計算とクラウド状態同期が不要になる
- 複数端末間で設定値は同期されない
- 実際のエアコン状態とアプリ表示がずれる可能性を受け入れる
- 予約は状態ではなく、実行時刻と送信payloadを持つ命令として保存する

## ADR-016: OTAを実装しない

状態: Accepted

### 文脈

OTAはファーム変更を容易にするが、最もありそうな変更理由であるSSIDやパスワード変更時にはESP32がオフラインで使えない。また、二重app slot、ロールバック、完全性検証、更新確定処理が必要になる。

OTAを導入すると、焼き込みtoken漏洩の影響が「エアコン操作」から「家庭内機器への任意コード投入」へ拡大する。

### 決定

OTAと遠隔ファーム更新を実装しない。すべての変更をUSBで行う。eFuseによるflash encryptionとsecure bootも使わない。

### 結果

- `Update`、OTA用HTTPクライアント、二重app slot、ロールバック処理を削除できる
- パーティションは`Huge APP (3MB No OTA/1MB SPIFFS)`を使える
- ファーム変更には必ず物理アクセスが必要になる
- USBへ手が届くことを設置要件とする
- USBで再書き込みできるため、事前に永久固定される設計値はない

## ADR-017: 再接続待機を30秒固定にする

状態: Accepted

### 文脈

指数バックオフ、ジッタ、10秒から60秒へ切り替える方式は回復速度や大規模同時接続に利点がある。しかし対象は1台であり、段階、切替時刻、リセット条件が増える。

### 決定

1回の接続サイクルでWebSocket接続を1回だけ試す。接続失敗または切断後はWebSocketを後始末し、Wi-FiをOFFにし、毎回30秒待ってWi-Fi接続からやり直す。

### 結果

- 所有者が覚える再接続規則が1つになる
- 1日中失敗して毎回Cloudflareまで到達しても最大約2,880回/日となる
- 30秒以内の高速回復を捨てる
- 30秒は試行開始周期ではなく、TLS内部処理などの試行時間が別に加わる
- 1台なのでジッタは使用しない

## ADR-018: 常時接続をWebSocketとHibernationで実現する

状態: Accepted

### 文脈

外出先からの即時操作にはCloudflareからESP32へ命令を届ける経路が必要である。短いポーリングは遅延とTLS handshakeの反復を生み、ロングポーリングは待機中の実行時間を消費する。

常時接続では、家庭ルーターのNAT維持と、無言で切れたTCP接続の検出が必要になる。

### 決定

ESP32からDurable ObjectへWebSocketを張り、Durable Object側はHibernation APIを使う。ESP32は30秒ping、10秒pong待ち、2回不応答で切断とする。

Cloudflareから見た最終生存時刻を得るためのアプリケーション用PING/PONGは追加しない。503と202を完全には区別できないことより、機器プロトコルを一方向1種類に保つことを優先する。

### 結果

- 即時操作を可能にしつつ、アイドル中のDurable Object実行を停止できる
- Cloudflare runtimeのprotocol ping自動pongへ依存する
- Hibernation復帰後は通常のJavaScript変数でなく`ctx.getWebSockets("device")`から接続を再取得する
- 503は未接続が判明している場合だけを示し、202はESP32の生存を保証しない

参考: [Cloudflare Durable Objects — WebSocket Hibernation](https://developers.cloudflare.com/durable-objects/best-practices/websockets/)

## ADR-019: 設定の列挙値は対象リモコンに存在するものだけにする

状態: Accepted

### 文脈

設計当初の風量は IRremoteESP8266 の定義を借りて `auto / quiet / 1 / 2 / 3 / 4` としていた。実機リモコンの採取で、風量ボタンの巡回は 1 → 2 → 3 → 自動 の4段で、静音と4段目は存在しないことが分かった。エアコン本体が値 4 や 5 を受理するかは確認手段がない。リモコンには「パワフル」ボタンがあるが、その符号化は採取していない。

### 決定

風量は `auto / 1 / 2 / 3` だけとする。リモコンで採取できない値はアプリの選択肢に載せない。パワフルは現在の要件に含めず、必要になった時に採取してから追加する。

### 結果

- `quiet` と `4` を設計、encoder、検証、アプリから外す
- mode の `auto` と `fan` はリモコンに存在せず採取できないが、IRremoteESP8266 の値を保持する。アプリの選択肢に載せるかは段階6で判断する
- パワフルを使いたくなった場合は、リモコンから採取して encoder の規則を拡張する

## その他の不採用案

| 案 | 不採用理由 |
|---|---|
| BLE | 外出先から操作できず、到達距離も短い |
| Tailscale / VPN | 家にsubnet routerとなる別機器が必要 |
| HomeKit hub / Home Assistant | 家に別機器が必要 |
| ポート開放 + DDNS | 家庭ルーターを外部公開する |
| ESP32内蔵Web UI | LAN直通経路がなく、ESP32は設定の意味を持たない |
| APフォールバック | まれなルーター変更のために通常ファームを複雑化する |
| `ir_raw` | 現在は`MITSUBISHI_AC`の18バイト形式だけで足りる |
| アプリのプリセットキャッシュ | 家庭ネット停止中にも操作するという未要求の要件を生む |
| Durable Objectの状態保存 | 実機から確認できない推測状態が増える |

## 判断を見直す条件

次のいずれかが実際の要件になった時だけ、対応するADRを見直す。

- 家にESP32以外の常設機器を置く
- 複数ユーザーまたは複数端末で状態を共有する
- 複数台のエアコンを操作する
- 繰り返し予約または複数予約が必要になる
- エアコン受理の遠隔確認が必要になる
- USBで触れない場所へ設置する
- Cloudflareの料金または提供機能がこの運用に合わなくなる
