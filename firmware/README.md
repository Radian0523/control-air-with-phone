# firmware

| ディレクトリ | 用途 | 段階 |
|---|---|---|
| `ir_serial_test/` | USBシリアルから36文字を受けて赤外線送信する試験スケッチ | 2c |
| `aircon_bridge/` | 本番ファーム（Wi-Fi、WebSocket over TLS、赤外線送信） | 3 |
| `ca_bundle/` | CA bundle の生成元と記録 | 3b |

ビルド環境（design.md §4.7）:

- Arduino IDE 2.x
- esp32:esp32 3.3.11
- IRremoteESP8266 2.9.0
- arduinoWebSockets 2.7.2（Links2004。段階3までにライブラリマネージャで導入）
- パーティション: Huge APP (3MB No OTA/1MB SPIFFS)
- Upload Speed: 115200

初回は `aircon_bridge/secrets.example.h` を `secrets.h` にコピーして値を埋める。

## 診断記録を読む（design.md §4.10）

USB アダプタで運用中に「ESP32 が接続されていません」が続いた時は、ESP32 を Mac へつなぎ、
115200 bps でシリアルモニタを開く。起動時に直近16件の `diag ...` 行が古い順に出る。

```
diag epoch=1793683048 up=90 offline_restart rssi=-52 a=0 b=0 c=0 d=3 e=0
diag epoch=1793683049 up=0 boot rssi=0 a=3 b=0 c=0 d=0 e=0
```

- `boot a=9` が並ぶ: brownout。アダプタ、ケーブル、5V/3.3V を確認
- `loop_stall`: loop() が5分止まった。`a` が止まった時の状態
- `offline_restart`: 10分戻れなかった。`c`/`d`/`e` が Wi-Fi / WebSocket / NTP の失敗回数
- `ws_lost`: 切断。`b=1` は Connection lost、`a` は WiFi.status()
