# 開発の振り返り: iPhone から三菱エアコンを操作するまで

記事化の材料としてまとめた、開発の流れ・つまずきと原因・解決策の記録。
期間は 2026-09-13（設計レビュー開始）〜 2026-09-18（設置完了）、コミット 22 件。
実作業は 9/13 夜、9/16 朝、9/17 夜〜9/18 深夜の 3 セッションに集中している。

構成: iPhone (SwiftUI) → Cloudflare Worker + Durable Object → WebSocket/TLS → ESP32 → 赤外線 → 三菱エアコン

---

## 1. 全体の流れ

```
9/13  設計レビュー 2 回 → 実装計画（8 段階） → 回路図 → 段階0・1 → 段階2 赤外線採取（UNKNOWN で足止め）
9/16  追加採取 → リモコンの仕様を把握 → 設計・encoder に反映
9/17  赤外線が出ない → 再起動ループ → 回路測定 → 段階2 完了
      Worker/DO/ファーム → Wi-Fi 失敗 → curl でエアコンが動く（段階3・4）
      段階5 を省略する判断 → iOS アプリ（段階6）
9/18  予約（段階7） → 設置（段階8） → 完了
```

### 進め方の特徴

- **コードを書く前に設計を固めた**。`docs/design.md` と `docs/adr.md`（ADR 20 件）が正本で、レビューを 2 往復してから実装に入った
- **8 段階に分けて、各段階に「通過条件（gate）」を置いた**。段階ごとに `docs/test-log.md` へ結果を記録し、通らなければ次へ進まない
- **ハードは「最初にシリアルだけで動かす」**。Wi-Fi もクラウドも繋がない状態で赤外線が出るのを確認してから、ネットワーク層を積んだ
- **決定はすべて ADR に残した**。途中で変えた 3 件（風量列挙、WDT、障害系試験省略）も ADR として追記

---

## 2. 段階ごとの流れ

| 段階 | 内容 | 主なつまずき |
|---|---|---|
| 設計レビュー | 設計書・ADR・Notion 出力のレビュー 2 往復 | 「接続中」判定の弱さ、executeAt 検証未定義、CA bundle 出自 など 11 件 + 6 件 |
| 計画 | 8 段階の実装計画、回路の電流計算、CircuiTikZ 回路図 | LaTeX の standalone が切り抜けない |
| 0 | リポジトリ準備、.gitignore、雛形 | なし |
| 1 | エンコーダ（18 バイト生成）とバリデーションの純粋関数 + テスト | vitest 5 と pool-workers の非互換 |
| 2 | 赤外線: 採取 → 回路 → シリアル試験 | **UNKNOWN しか採れない / 赤外線が出ない / 5 秒ごとに再起動** |
| 3 | Worker/DO 骨格、CA bundle、本番ファーム、TLS 接続 | **wifi_failed（5GHz）** |
| 4 | POST /command → エアコンが動く | なし（curl 2 回とも成功） |
| 5 | 障害系試験（T1〜T7） | **省略を決定（ADR-020）** |
| 6 | iOS アプリ（設定・操作） | シミュレータ未起動、テストの epoch 定数ミス |
| 7 | 一発予約（schedule API、Alarm、iOS 予約画面） | Alarm テストの型 |
| 8 | 設置と通し確認 | なし |

---

## 3. つまずきと原因と解決（記事の本体候補）

重要度の高い順ではなく、発生順。★ は記事にすると面白そうなもの。

### ★ 3.1 赤外線を採取しても UNKNOWN しか出ない（段階2、9/13）

**症状**
`IRrecvDumpV2` 系のスケッチで三菱リモコンを受けると、`UNKNOWN` と 25〜292 bits の不揃いな値しか出ない。期待は `MITSUBISHI_AC` 144 bits。

**原因**
- 受光モジュールがリモコンを近づけすぎて飽和し、パルス幅が崩れていた
- ライブラリ既定の許容誤差（tolerance 25%）とノイズ閾値では、崩れた波形を規格に当てられなかった

**解決**
- `tools/ir_dump/ir_dump.ino` に tolerance +10、unknown 閾値 50 を設定
- UNKNOWN のときは生タイミング配列を出力するようにして、波形の崩れ方を目で見られるようにした
- リモコンを離して受光させると `MITSUBISHI_AC` として素直にデコードできた

**教訓**
デコーダが失敗したときに「生データを吐く」経路を最初から用意しておくと、原因が「回路」か「距離」か「ライブラリ設定」かを切り分けられる。

### ★ 3.2 リモコンの仕様が想定と違う（段階2a、9/13〜9/16）

**症状**
設計時に IRremoteESP8266 の仕様どおり「モード: 自動/冷房/除湿/暖房/送風、風量: 自動/静音/1〜4」を列挙していたが、実機のリモコンには自動モード・送風モード・静音・風量 4 が存在しなかった。代わりに「パワフル」ボタンがある。

**原因**
ライブラリの列挙はプロトコル全体の可能値で、個々のリモコンが出せる値の集合ではない。

**解決**
- 各ボタンを押して採取し、`docs/ir-captures.md` に 2 回分の採取表として記録
- 採取から分かった規則を設計 §7.1 に追記。特に
  - byte 9 = `0x40 | vane<<3 | fan`（bit6 は常に 1）
  - byte 15 は電源ボタン時だけ `10`、それ以外 `00`（エアコンはどちらも受理）
  - 風量/風向ボタン直後だけ byte 9 が `98` `81` などの別形になるが、全状態を送る電源ボタン系フレームは規則形
- 風量列挙を `auto/1/2/3` に絞り、パワフルは対象外とした（ADR-019）
- テストベクトルを「ライブラリから生成した値」ではなく「実機採取値」5 件に置き換えた（レビュー R-3 の反映）

**教訓**
「ライブラリが対応している」と「手元のリモコンが出す」は別。テストベクトルは実機から採る。

### 3.3 回路図が LaTeX で綺麗に出ない（計画段階、9/13）

**症状**
CircuiTikZ で描いた回路を `standalone` クラスで出力しても余白が残る。`above left=1pt and -2pt` で PGF エラー。ラベルが重なる。

**解決**
`pdflatex` → `pdfcrop --margin 10` → `pdftoppm` の 3 段パイプに変更。位置指定は単純な `above left` に戻し、重なるラベルは手で配置を変えた。成果物は `docs/circuit/ir_driver.{tex,pdf,png}`。

### ★ 3.4 回路どおりなのに赤外線が出ない → 実は 5 秒ごとに再起動していた（段階2c、9/17）

**症状**
シリアル試験スケッチに 36 文字を送ってもエアコンが反応しない。ユーザーは「回路図が間違っているのでは」と疑った。シリアルログの末尾を見ると `entry 0x400805b4` で始まるブートメッセージが繰り返されている。

**原因（2 段階あった）**

1. `loop()` が一度も CPU を譲らなかった。ESP32 Arduino core 3.3.11 は `CONFIG_ESP_TASK_WDT_PANIC=y`、タイムアウト 5 秒。`enableCore1WDT()` を呼んでいたため IDLE1 タスクが Task WDT の監視対象になり、`loop()` が busy loop で IDLE1 が走れず 5 秒で panic
2. `delay(1)` を入れて IDLE1 が走るようにしても直らなかった。**`enableCore1WDT()` は `esp_task_wdt_add(IDLE1)` をするだけで、IDLE1 から `esp_task_wdt_reset()` を呼ぶ idle hook を登録しない**。core 3.x では `CONFIG_ESP_TASK_WDT_CHECK_IDLE_TASK_CPU1` が無効なので IDF 側も hook を付けてくれない。IDLE1 は走っていたが誰も WDT を餌付けしていなかった

**解決（「3 点セット」として設計 §4.4 と ADR-006 に固定）**
```cpp
enableCore1WDT();
esp_register_freertos_idle_hook_for_cpu(feedTaskWdtFromIdle1, 1);  // 中で esp_task_wdt_reset()
// loop() 末尾で delay(1)
```

**ついでに見つかった別の罠**
起動直後に出力ラッチを LOW にする目的で `digitalWrite(4, LOW); pinMode(4, OUTPUT);` の順で書いていたが、core 3.x の `digitalWrite` は `pinMode` 前の未登録ピンでは何もしない（`esp32-hal-gpio.c` を読んで確認）。IDF の `gpio_set_level()` に置き換えた。

**教訓**
- 「赤外線が出ない」の前に「そもそもマイコンが生きているか」を疑う。ブートメッセージの繰り返しが最初の証拠だった
- core のバージョン差で API の意味が変わる。Arduino のラッパーではなく IDF の関数とソースを読むのが早い

### 3.5 シリアルモニタに入力が必要と分かっていなかった（段階2c、9/17）

**症状**
「36 文字を 1 行送り」という手順の意味が伝わっておらず、送信していなかった。

**解決**
Arduino IDE のシリアルモニタ上部の入力欄に 36 文字を貼り付けて Enter、と具体的に説明。送った直後に `ir_sent` が出てエアコンが反応した。

**教訓**
手順書の「送る」は、どのウィンドウのどの欄で何をするかまで書く。

### 3.6 テスターがない状態で回路の電圧を確かめたい（段階2c、9/17）

**解決**
ESP32 自身の ADC で測る `tools/ir_probe/ir_probe.ino` を作成。GPIO34 は直接、GPIO35 は 1/2 分圧で 5V 系を測れるようにし、ジャンパで測りたい点を持ってくる方式。LED 電流の計算値（約 36mA/個、ベース電流約 11.8mA）に対して、測定値は妥当な範囲だった。

### 3.7 npm / vitest 周りの環境問題（段階1・3）

| 症状 | 原因 | 解決 |
|---|---|---|
| `npm install` で ERESOLVE | vitest 5 が入り、`@cloudflare/vitest-pool-workers` の peer `^4.1.0` と衝突 | `vitest@^4.1.0` に固定 |
| workerd の postinstall が動かない | npm の allow-scripts 設定 | `npm approve-scripts workerd` して rebuild |
| `@cloudflare/vitest-pool-workers/config` が無い | 0.22 系で API 変更 | ルート export の `cloudflareTest` を Vite plugin として使う |
| `compatibility_date` エラー | 2026-09-01 が workerd の上限 2026-08-22 を超えていた | 2026-08-01 に下げる |
| `Env` の型が合わない | pool-workers の型は `Cloudflare.Env` を見る | `declare global { namespace Cloudflare { interface Env extends AppEnv {} } }` |
| `crypto.subtle.timingSafeEqual` が無い | Node には存在しない（Workers 独自） | 認証テストを workers プロジェクト側へ移動 |
| Upgrade 付き POST が 405 にならない | workerd が Upgrade リクエストを GET に正規化 | テストでは Upgrade ヘッダを付けずに POST |
| `stub.alarm()` が型エラー | RPC スタブに `alarm` は無い | `runInDurableObject(stub, i => i.alarm())` |

### ★ 3.8 wifi_failed（段階3、9/17）

**症状**
本番ファームを焼くと `wifi_failed` だけが繰り返し出る。

**調査**
ログに `WiFi.status()` の値を付けるよう改修（`wifi_failed status=1` = `WL_NO_SSID_AVAIL`）。同時に SSID 一覧を出す `tools/wifi_scan` を作った。

**原因**
接続先に指定していた SSID が 5GHz 帯だった。ESP32-WROOM-32 は 2.4GHz のみ。

**解決**
2.4GHz の SSID に変更 → `wifi_connected` → `time_synced` → `ws_connected` まで一発で通った。

**教訓**
「失敗した」だけのログは診断に使えない。理由コードを 1 つ添えるだけで一往復減る。

### 3.9 Cloudflare 側のログに謎の切断が出る（段階3、9/17）

**症状**
`device_disconnected code=1006` が `device_connected` の直後に出る。

**原因**
EN ボタンで ESP32 をリセットしたとき、古い WebSocket が残ったまま新規接続が来る。DO 側で古い `device` タグのソケットを `1000 "replaced"` で閉じるが、既に相手が消えているので 1006 として記録される。設計どおりの挙動で異常ではなかった。

### 3.10 iOS 周りの小さな問題（段階6・7）

- **シミュレータが起動していない** → `xcrun simctl boot 'iPhone 17 Pro'` してから attach/launch
- **テストの期待値ミス** → epoch 1789668000 は 2026-09-17T18:00:00Z。期待文字列を修正
- **macOS の sed** → `sed -i '1i\'` の構文が GNU と違い失敗。Python で挿入に変更

### ★ 3.11 段階5（障害系試験）を丸ごと省略した判断（9/17）

**経緯**
T1〜T7 の手順書と試験用ビルドの切り替え（heap/tls_ms ログ）まで用意した時点で、ユーザーから「一旦エアコンがつけばそれで良くないですか？」。最小セットを提案したが、「普段の動作でいいや。飛ばして OK」となった。

**どう処理したか**
ADR-020 として「省略する」ことと、**何が未検証のまま残っているか**を明記した。
- 不正な証明書を拒否するか
- ルーター再起動後に復帰するか
- 長時間運転でヒープが減り続けないか

代わりに通常運用で観察する項目を書き、手順書 `docs/stage5-procedure.md` は診断用に残した。実際、段階7 で電源断からの自動復帰は自然に確認できた。

**教訓**
試験を省くこと自体は問題ではない。「省いた」と「何を知らないままか」を記録しておくことが大事。

---

## 4. 設計レビューで実装前に直ったこと

書き始める前のレビュー 2 往復で 17 件を処理した。実装後に見つかっていたら手戻りが大きかったもの:

- **R-1 「接続中」判定**: WebSocket が accept された事実だけで 503/202 を決めていた。Hibernation 前提で `getWebSockets("device")` の有無で判定するよう明確化
- **R-2 executeAt の検証**: 形式・往復一致・未来であることを規則化。後の実装でそのままバリデータになった
- **R-3 テストベクトル**: 実機採取と分かるのが 1 件だけだった → 段階2 で 5 件採り直し
- **R-4 CA bundle の出自**: Mozilla `cacert.pem` の日付と sha256 を記録し、IDF の `gen_crt_bundle.py` で全証明書を含める手順を固定（Cloudflare のルート CA 変更に備えてフィルタしない）
- **R-5 arduinoWebSockets の自動再接続**: ライブラリの再接続と自前の状態機械が競合する。`setReconnectInterval(0)` → 最初の `loop()` → `setReconnectInterval(30000)` の「1 回の CONNECTING で 1 回だけ試行」に整理
- **R2-1**: 第 1 回反映で `setReconnectInterval(500)` になっており ADR-017（30 秒固定）と矛盾 → 修正
- **A-4 TLS 中の Task WDT**: 同期 TLS ハンドシェイクが数秒かかるので WDT との関係を設計に明記。段階2 の再起動ループはこの懸念が別の形で現実になったもの
- **A-6 GPIO15 はストラッピングピン**: 受光モジュールは解析専用にし、本番回路から外した

---

## 5. 記事にするなら

**タイトル案**
- 「ESP32 が 5 秒ごとに再起動する: `enableCore1WDT()` だけでは足りない話」
- 「三菱エアコンの赤外線を採ってみたら、ライブラリの列挙と現物が違った」
- 「コードを書く前に ADR を 20 本書いて、8 段階で組んだ IoT 個人開発」

**図にすると伝わりやすいもの**
- 全体構成図（iPhone → Cloudflare → ESP32 → エアコン）
- ESP32 の状態機械（CONNECTING → ONLINE → TEARDOWN → OFF_WAIT）
- 回路図（`docs/circuit/ir_driver.png` がそのまま使える）
- 18 バイトフレームのバイト配置表（設計 §7.1）

**数字**

| 項目 | 値 |
|---|---|
| 期間 | 6 日（実作業 3 セッション） |
| コミット | 22 |
| ADR | 20 件（実装中に追加 3 件） |
| レビュー指摘 | 17 件（2 往復） |
| Cloudflare テスト | 49 |
| iOS テスト | 12 |
| 赤外線採取 | 2 回 |

**書かないこと**
- Wi-Fi の SSID/パスワード、DEVICE_TOKEN、APP_TOKEN の値
- 36 文字ペイロードそのもの（採取表はリポジトリ内で完結させる）
- Worker の URL は必要なら伏せる

---

## 6. 参照

- 設計: `docs/design.md`、決定記録: `docs/adr.md`
- レビュー: `docs/review-2026-09-13.md`
- 計画と進行表: `docs/implementation-plan.md`
- 赤外線採取: `docs/ir-captures.md`
- 試験記録: `docs/test-log.md`
- 障害系手順（未実施、診断用）: `docs/stage5-procedure.md`
