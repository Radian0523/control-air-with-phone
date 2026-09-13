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
