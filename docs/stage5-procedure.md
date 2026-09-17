# 段階5 障害系試験 手順書

対象: design.md §10 の障害系項目と、段階3から移管した4項目。結果は docs/test-log.md に転記する。
所要: 短時間の試験が6件（各5〜10分）と、24時間の放置試験が1件。

## 準備: 試験用ビルド

`firmware/aircon_bridge/aircon_bridge.ino` の22行目付近にある

```cpp
// #define AIRCON_DEBUG_HEAP
```

の `//` を外して書き込む。すると次のように変わる。

- `ws_connected` / `ws_failed` の行に `heap=`（現在の空き）、`min_heap=`（起動以来の最小空き）、`tls_ms=`（TCP+TLS 接続にかかった時間）が付く
- ONLINE 中は5分ごとに `heap=... min_heap=...` が出る

**全試験が終わったら `//` を戻して本番ビルドに書き換えること。** 本番では周期ログを出さない（§4.8）。

シリアルモニタは 115200 で開き、必要なら「出力を保存」でログを残す。

## 試験一覧

### T1. 正常接続の所要時間と RAM（5分）

1. 試験用ビルドを書き込み、`ws_connected heap=... min_heap=... tls_ms=...` の行を控える
2. EN を押して再接続し、同じ行をもう1回控える

見るもの: `tls_ms`（設計は「実機で測る」。数秒以内が目安）、`min_heap`（設計§4.9 の RAM ピーク見積もり約100KB使用 → 空き 220KB 前後が目安）。

### T2. 誤った DEVICE_TOKEN（5分）

1. `secrets.h` の `DEVICE_TOKEN` の末尾に1文字足して書き込む
2. `wifi_connected` → `ws_failed ...` → 約30秒後に再び `wifi_connected` → `ws_failed` が繰り返されることを確認する。再起動（`boot`）が混ざらないこと
3. 私が Cloudflare 側で 401 の記録を確認する

見るもの: 周期（15秒以内の失敗 + 30秒待機 ≒ 30〜45秒）、`heap` が回を重ねても減り続けないこと。

### T3. 誤ったホスト名（5分）

`secrets.h` の `WS_HOST` を `104.21.86.199`（Worker の IP のひとつ。証明書の名前と一致しない）に変えて書き込む。

期待: `ws_failed` を30秒周期で繰り返し、`ws_connected` にならない。`tls_ms` を控える（TLS 検証失敗までの時間）。

### T4. 未信頼の証明書（5分）

`WS_HOST` を `self-signed.badssl.com`、`WS_PORT` を `443`、`WS_PATH` を `/` に変えて書き込む。

期待: `ws_failed` を繰り返し、`ws_connected` にならない。終わったら `WS_HOST` / `WS_PORT` / `WS_PATH` / `DEVICE_TOKEN` を正しい値に戻す。

### T5. AP 断とルーター再起動（10分）

正しい設定で `ws_connected` にした状態で:

1. ルーターの Wi-Fi を切る（または電源を抜く）
2. heartbeat の不応答で `ws_disconnected` が出るまでの時間を控える（設計: 30秒 ping + 10秒待ち × 2回 ≒ 最長80秒）
3. ルーターを戻す
4. 手を触れずに `wifi_connected` → `ws_connected` へ戻ることを確認し、復帰までの時間を控える

### T6. 電源 OFF 後の 503 と、送信中の切断（10分）

1. ESP32 の USB を抜く
2. 直後（10秒以内）に curl で `POST /command` → 202 になることがある（§9 の「古い socket へ送った」ケース）
3. 2〜3分待って再度 curl → 503 `device_offline` になることを確認する
4. USB を戻して `ws_connected` を待つ
5. curl で `POST /command` を送り、`ir_sent` が出た直後にルーターの Wi-Fi を切る → `ir_sent` は完了し、その後 `ws_disconnected` → 復帰後に再接続することを確認する

### T7. 24時間の接続失敗試験（24時間放置）

1. T3 と同じく `WS_HOST` を `104.21.86.199` にして書き込む（毎回 TLS まで到達して失敗する、最も重い失敗パターン）
2. シリアルモニタで「出力を保存」を有効にし、24時間放置する
3. 終了後、ログの最初と最後の `ws_failed ... heap=... min_heap=...` を控える。`boot` が1回（最初）だけであることを確認する

合格条件（§10）: 再起動ループがない、`min_heap` が最初の数回以降は下がり続けない、二重送信がない（送信は行わないので該当なし）。

## 報告してほしいもの

- T1: `ws_connected` 行 2件
- T2〜T4: `ws_failed` 行を各3件と、`boot` が出ていないこと
- T5: 切断検知までの秒数、復帰までの秒数
- T6: 手順2と3の curl の HTTP ステータス、手順5のシリアル表示
- T7: 最初と最後の `ws_failed` 行、`boot` の回数

T7 は最後にまとめて実施し、その間に段階6の iOS アプリを進める。
