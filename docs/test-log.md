# 試験記録

設計 §8.3 / §10 の試験結果を段階ごとに残す。数値は実測値、判定は所有者の確認による。

## 段階2. 赤外線（2026-09-17）

環境: ideaspark ESP32 / esp32 core 3.3.11 / IRremoteESP8266 2.9.0 / 回路は docs/circuit/ir_driver（100Ω ×3、220Ω、10kΩ、S8050）。電源は USB。

### 2c 送信試験（`firmware/ir_serial_test`）

| 項目 | 結果 |
|---|---|
| 起動後15秒以上再起動しない（Task WDT 3点セット） | 合格 |
| 36文字送信で `ir_sent` が出る | 合格 |
| §7.2 の5ベクトルすべてにエアコンが反応 | 合格 |
| 電源以外の変更（byte 15 = `10` 固定）にも反応 | 合格 |
| 設置予定位置から安定して反応 | 合格 |

### 2b 電気試験（`tools/ir_probe`、ESP32 ADC による測定）

テスターが無いため ESP32 の ADC で測定。B チャネルは 1/2 分圧、A チャネルは直結。3.3V ピンで倍率を確認したうえで測定した。所有者の申告は「全項目が期待範囲内」。個別の数値は記録していない。

| 測定点 | 期待範囲 | 結果 |
|---|---|---|
| 3.3V ピン（B） | 3.2〜3.4V | 範囲内 |
| VIN（B） | 4.5〜5.0V | 範囲内 |
| LED カソード = 100Ω 上側（B） | 3.3〜3.8V | 範囲内 |
| ベース（A、LED 点灯中） | 0.7〜0.9V | 範囲内 |
| コレクタ（A、LED 点灯中） | 0.1〜0.3V | 範囲内 |

導出: 100Ω 両端 = カソード − コレクタ ≈ 3.0〜3.6V → 1本あたり 30〜36mA、3本合計 90〜108mA。設計値と一致。68Ω への変更は不要。

### 途中で見つかった問題と対処

| 事象 | 原因 | 対処 | コミット |
|---|---|---|---|
| `ir_dump` が UNKNOWN ばかり返す | 受信モジュールの飽和と許容誤差 | 許容 35%、ノイズ閾値 50 bit、生タイミング出力を追加 | 49b714f |
| `boot` の約5秒後に再起動を繰り返す | `enableCore1WDT()` が IDLE1 を監視対象に追加するだけで idle hook を登録しない。さらに `loop()` が IDLE1 に譲らない | Task WDT を「add / idle hook / delay(1)」の3点セットに変更。設計 §4.1 §4.4、ADR-006 へ反映 | 0cb7fd2, 250b481 |
| `digitalWrite()` を `pinMode()` 前に呼ぶ手順が無効 | core 3.x は周辺管理に未登録のピンへの `digitalWrite()` を無視する | `gpio_set_level()` で出力レジスタを先に 0 にする | 0cb7fd2 |

### 判定

段階2のゲート（採取と規則の一致、電気試験合格、設置位置からの安定動作）をすべて満たす。段階3へ進む。

## 段階3・4. 機器接続と即時操作（2026-09-17）

環境: Worker `aircon`（https://aircon.aircon-worker.workers.dev）、arduinoWebSockets 2.7.2、CA bundle 2026-08-13 版（55,587B）。ESP32 は 2.4GHz SSID に接続。

### 接続（段階3）

| 項目 | 結果 |
|---|---|
| `boot` → `wifi_connected` → `time_synced` → `ws_connected` | 合格 |
| EN リセット後、時刻が残っているため `time_synced` を省略して `ws_connected` | 合格（§4.5 の NTP 省略） |
| Cloudflare に `device_connected` が記録される | 合格（23:32:50） |
| 新接続で古い接続が閉じられる | 合格。古い接続は相手不在のため code 1006 で `device_disconnected` |
| Wi-Fi 失敗時に再起動せず約45秒周期（15s 試行 + 30s 待機）で再試行 | 合格（5GHz SSID 指定時に `wifi_failed status=1` を繰り返した） |
| TLS チェーン | Let's Encrypt → ISRG Root X2。root は bundle に含まれる |
| 誤 DEVICE_TOKEN で 401 と 30秒周期の再試行 | 未実施（段階5で実施） |
| 誤ホスト・未信頼証明書で TLS 失敗 | 未実施（段階5で実施） |
| hibernate 後の `getWebSockets("device")` 再取得 | 段階4の curl が接続から数分後に成功しており、実質的に確認。明示的な長時間放置試験は段階5で実施 |
| TLS 接続の内部ブロック時間、RAM ピーク | 未実施（段階5、AIRCON_DEBUG_HEAP ビルドで実施） |

観察: 23:33:09 に `device_disconnected`（1006）が1件追加で記録されたが、ESP32 側に `ws_disconnected` は出ておらず、その後5分間に再接続も無い。EN リセット前の古い接続の後始末と判断する。

### 即時操作（段階4）

| 項目 | 結果 |
|---|---|
| 統合テスト（401 / 400 / 405 / 202 で36文字到達 / 503） | 合格（workers pool、40テスト） |
| 本番: トークン無しの `/device/ws` → 401、未知パス → 404 | 合格 |
| 本番: `POST /command` 冷房26℃ON → 202、`ir_sent`、エアコン動作 | 合格 |
| 本番: `POST /command` 電源OFF → 202、`ir_sent`、エアコン停止 | 合格 |
| 本番: ESP32 電源OFF後の 503 | 未実施（段階5で実施） |

### 途中で見つかった問題と対処

| 事象 | 原因 | 対処 | コミット |
|---|---|---|---|
| `wifi_failed` を繰り返す | 5GHz SSID を指定していた。ESP32 は 2.4GHz のみ | 2.4GHz SSID へ変更。`wifi_failed` に status コードを付与し、`tools/wifi_scan` を追加 | 6b6260d |
| vitest 5 と pool-workers の peer 衝突 | pool-workers 0.22 は vitest 4 系のみ | vitest を 4 系に固定 | 4f99bb1 |
| `crypto.subtle.timingSafeEqual` が Node に無い | Cloudflare 固有 API | auth のテストを workers プロジェクトへ移動 | 63a5298 |

### 判定

段階4のゲート「全 HTTP 結果を再現し、202 で実機が動く」を満たす。段階3の未実施項目は障害系の性質が強いため段階5へ移し、まとめて実施する。
