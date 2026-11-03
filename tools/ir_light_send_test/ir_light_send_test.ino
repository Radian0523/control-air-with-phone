// ---------------------------------------------------------------------------
//  ir_light_send_test.ino — 照明リモコン（オーデリック NRL-3321）の4ボタンを
//                            USBシリアルから送る試験スケッチ
//
//  目的:
//    docs/ir-captures.md「照明リモコン採取」で採った NEC コードを、
//    本番と同じ GPIO4 の赤外線 LED 回路から送り、照明が反応するかを確かめる
//
//  使い方:
//    1. 書き込み後、シリアルモニタ (115200) を開く。改行は「LF」または「CR+LF」
//    2. 次のどれかを1行で送る: eco / on / mame / off
//    3. `sent <名前> 0x........` が出れば送信済み。照明が反応するかを見る
//
//  ボード設定（design.md §4.7）:
//    esp32:esp32 3.3.11 / IRremoteESP8266 2.9.0
//    Partition: Huge APP (3MB No OTA/1MB SPIFFS) / Upload Speed 115200
// ---------------------------------------------------------------------------

#include <Arduino.h>
#include <IRremoteESP8266.h>
#include <IRsend.h>
#include <driver/gpio.h>

namespace {

constexpr uint8_t kIrLedPin = 4;  // GPIO4 (D4)

struct Button {
  const char *name;
  uint64_t code;
};

// 2026-11-03 採取。アドレス 0x01A3 共通、NEC 32 bit
constexpr Button kButtons[] = {
    {"eco", 0x01A3748B},
    {"on", 0x01A359A6},
    {"mame", 0x01A354AB},
    {"off", 0x01A310EF},
};

IRsend irsend(kIrLedPin);
String line;

void handleLine(String cmd) {
  cmd.trim();
  cmd.toLowerCase();
  if (cmd.isEmpty()) return;
  for (const Button &b : kButtons) {
    if (cmd == b.name) {
      irsend.sendNEC(b.code, kNECBits);
      Serial.printf("sent %s 0x%08llX\n", b.name, static_cast<unsigned long long>(b.code));
      return;
    }
  }
  Serial.printf("unknown \"%s\" (eco / on / mame / off)\n", cmd.c_str());
}

}  // namespace

void setup() {
  // 出力レジスタを LOW にしてから OUTPUT 化（本番ファームと同じ。design.md §4.1）
  gpio_set_level(static_cast<gpio_num_t>(kIrLedPin), 0);
  pinMode(kIrLedPin, OUTPUT);
  digitalWrite(kIrLedPin, LOW);

  Serial.begin(115200);
  irsend.begin();
  Serial.println();
  Serial.println(F("=== 照明 送信試験 === eco / on / mame / off を1行で送ってください"));
}

void loop() {
  while (Serial.available()) {
    const char c = static_cast<char>(Serial.read());
    if (c == '\n') {
      handleLine(line);
      line = "";
    } else if (line.length() < 16) {
      line += c;
    }
  }
  delay(1);
}
