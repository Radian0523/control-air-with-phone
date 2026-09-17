// ---------------------------------------------------------------------------
//  ir_probe.ino — テスターの代わりに ESP32 の ADC で回路の電圧を測る（design.md §8.3）
//
//  GPIO4 を HIGH に固定して IR LED を連続点灯させたまま、2本のプローブ入力を 0.5 秒ごとに表示する。
//
//  プローブ:
//    A (GPIO34) 直結     : 0〜3.1V の点だけ。 ベース、コレクタ
//    B (GPIO35) 1/2 分圧 : 3.1V を超えうる点。 VIN、LED カソード（100Ω の上側）、3.3V ピン
//
//  B の分圧の作り方（同じ値の抵抗 2 本。1kΩ〜100kΩ が望ましい。無ければ 68Ω×2 でも短時間なら可）:
//
//        測りたい点 ──[R]──┬──[R]── GND
//                          │
//                        GPIO35
//
//    表示は分圧を 2 倍して元の電圧に戻してある。抵抗値がぴったり同じでなくても、
//    まず 3.3V ピンを B で測り、表示が 3.2〜3.4V になることで倍率を確認できる。
//
//  絶対に守ること:
//    - A（GPIO34）に 3.3V を超える点を触れさせない（VIN、LED カソードは B で測る）
//    - ESP32 の GND と回路の GND が共通であること（すでに共通なら追加配線は不要）
//    - LED を連続点灯させるので、測定は数分以内に終えて ir_serial_test に戻す
//
//  読み方（100Ω・LED 3 本の設計値）:
//    VIN 4.5〜5.0V / ベース 0.7〜0.9V / コレクタ 0.1〜0.3V / 3.3V ピン 3.2V 以上
//    LED カソード（100Ω 上側）とコレクタの差 = 100Ω の両端電圧。 3.0〜3.6V なら 30〜36mA
// ---------------------------------------------------------------------------

#include <Arduino.h>

namespace {

constexpr uint8_t kIrLedPin = 4;
constexpr uint8_t kProbeDirectPin = 34;   // A: 直結（ADC1_CH6、入力専用）
constexpr uint8_t kProbeDividedPin = 35;  // B: 1/2 分圧（ADC1_CH7、入力専用）
constexpr int kSamples = 32;

// 複数回読んで平均し、ノイズを抑える。analogReadMilliVolts は core 3.x の校正値を使う
uint32_t readMilliVolts(uint8_t pin) {
  uint32_t sum = 0;
  for (int i = 0; i < kSamples; i++) sum += analogReadMilliVolts(pin);
  return sum / kSamples;
}

}  // namespace

void setup() {
  Serial.begin(115200);
  pinMode(kIrLedPin, OUTPUT);
  digitalWrite(kIrLedPin, HIGH);  // LED 連続点灯（ir_led_check と同じ）

  analogSetAttenuation(ADC_11db);  // 0〜約3.1V を読む
  pinMode(kProbeDirectPin, INPUT);
  pinMode(kProbeDividedPin, INPUT);

  delay(300);
  Serial.println();
  Serial.println(F("=== 電圧プローブ（GPIO4 HIGH で LED 連続点灯中）==="));
  Serial.println(F("A=GPIO34 直結(<=3.1V)   B=GPIO35 1/2分圧(x2表示)"));
  Serial.println(F("何も触れていない入力の表示は不定。測りたい点にジャンパーを当てて読む"));
}

void loop() {
  const uint32_t a = readMilliVolts(kProbeDirectPin);
  const uint32_t b = readMilliVolts(kProbeDividedPin) * 2;

  Serial.printf("A: %u.%03u V    B: %u.%03u V%s\n",
                a / 1000, a % 1000, b / 1000, b % 1000,
                a >= 3050 ? "    [A 上限付近: この点は B で測る]" : "");
  delay(500);
}
