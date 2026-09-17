// ---------------------------------------------------------------------------
//  ir_serial_test.ino — USBシリアルから36文字を受けて赤外線送信する試験スケッチ
//                        （実装計画 段階2c）
//
//  目的:
//    - design.md §8.2 の回路と §8.3 の電気試験
//    - 設置位置からエアコンが安定して反応することの確認
//    - §4.3 の入力検証と送信コード（ir_frame.h）を本番の前に実機で通す
//
//  使い方:
//    1. 書き込み後、シリアルモニタ (115200) を開く。改行は「LF」または「CR+LF」
//    2. 36文字の大文字16進を1行で送る。design.md §7.2 のテストベクトル:
//         23CB260100201008325800000000001000E7   (ON / dry / 24℃ / auto / middle)
//         23CB26010020180A365800000000001000F5   (ON / cool / 26℃ / auto / middle)
//         23CB26010000180A365800000000001000D5   (OFF / cool / 26℃ / auto / middle)
//         23CB26010020180A364100000000001000DE   (ON / cool / 26℃ / 1 / auto)
//         23CB26010020080A306900000000001000F0   (ON / heat / 26℃ / 1 / lowest)
//       電源以外の変更（温度など）にも byte 15 = 10 固定で反応することを確認する
//    3. `ir_sent` が出れば送信済み。`invalid_frame` は捨てた入力
//
//  シリアル特有の扱い:
//    行末の LF は区切りとして消費する。その直前の CR 1個も区切りの一部として捨てる。
//    これは USBシリアルの搬送に属する処理で、本番の WebSocket では行わない
//    （WebSocket はフレーム境界を持つため、CR/LF はそのまま不正入力）。
//
//  ボード設定（design.md §4.7）:
//    esp32:esp32 3.3.11 / IRremoteESP8266 2.9.0
//    Partition: Huge APP (3MB No OTA/1MB SPIFFS) / Upload Speed 115200
// ---------------------------------------------------------------------------

#include <Arduino.h>
#include <IRremoteESP8266.h>
#include <IRsend.h>
#include <esp_task_wdt.h>
#include <esp_freertos_hooks.h>
#include <driver/gpio.h>

#include "ir_frame.h"

namespace {

constexpr uint8_t kIrLedPin = 4;  // GPIO4 (D4)

// 1行の最大長。36文字 + CR を超えた入力は不正としてまとめて捨てる
constexpr size_t kLineCapacity = 64;

IRsend irsend(kIrLedPin);

char line[kLineCapacity];
size_t lineLen = 0;
bool lineOverflow = false;

// core 1 の IDLE タスクから Task WDT へ餌を与える idle hook。
// ESP-IDF は CONFIG_ESP_TASK_WDT_CHECK_IDLE_TASK_CPU1 が有効なときだけこの hook を自動登録するが、
// arduino-esp32 3.x の既定設定では無効で、enableCore1WDT() は IDLE1 を監視対象に「追加するだけ」。
// hook がないと IDLE1 は永久にリセットできず、5秒で必ずパニックする（2026-09-17 実機で確認）。
bool feedTaskWdtFromIdle1() {
  esp_task_wdt_reset();
  return true;
}

void handleLine(const char *text, size_t len) {
  // 搬送上の CR を1個だけ落とす（上記コメント参照）
  if (len > 0 && text[len - 1] == '\r') len--;

  uint8_t state[ir_frame::kStateLength];
  if (!ir_frame::parse(text, len, state)) {
    Serial.println(F("invalid_frame"));
    return;
  }

  // 同期送信。約0.5秒ブロックする（§4.4）。
  irsend.send(MITSUBISHI_AC, state, ir_frame::kStateLength);
  Serial.println(F("ir_sent"));
}

}  // namespace

void setup() {
  // §4.1 BOOT: 出力ラッチを LOW にしてから OUTPUT 化し、起動時の誤点灯を防ぐ。
  // core 3.x の digitalWrite() は pinMode() 前だと何もしない（周辺管理の登録前）ので、
  // IDF の gpio_set_level() で出力レジスタを直接 0 にしてから OUTPUT にする。
  gpio_set_level(static_cast<gpio_num_t>(kIrLedPin), 0);
  pinMode(kIrLedPin, OUTPUT);
  digitalWrite(kIrLedPin, LOW);

  // §4.4: Task Watchdog を core 1 で有効にする（本番と同じ起動手順を踏む）。
  // 次の3つは必ずセットで使う。どれか欠けると5秒で再起動する。
  //   1. enableCore1WDT()                       IDLE1 を監視対象に追加
  //   2. esp_register_freertos_idle_hook_for_cpu IDLE1 が走るたびに WDT をリセット
  //   3. loop() 末尾の delay(1)                  IDLE1 に CPU を譲る
  enableCore1WDT();
  esp_register_freertos_idle_hook_for_cpu(feedTaskWdtFromIdle1, 1);

  Serial.begin(115200);
  irsend.begin();
  Serial.println(F("boot"));
}

void loop() {
  while (Serial.available() > 0) {
    const int c = Serial.read();
    if (c < 0) break;

    if (c == '\n') {
      if (lineOverflow) {
        Serial.println(F("invalid_frame"));
      } else {
        handleLine(line, lineLen);
      }
      lineLen = 0;
      lineOverflow = false;
      continue;
    }

    if (lineLen < kLineCapacity) {
      line[lineLen++] = static_cast<char>(c);
    } else {
      lineOverflow = true;
    }
  }

  // §4.4: core 1 の IDLE タスクへ毎周期 CPU を譲る（setup() の WDT 設定と対）。
  // Arduino の loopTask は loop() を休みなく呼び続けるため、ここで譲らないと IDLE1 が走れない。
  delay(1);
}
