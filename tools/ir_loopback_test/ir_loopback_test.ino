// ---------------------------------------------------------------------------
//  ir_loopback_test.ino  —  送信した信号を自分で受信できるか確かめる
//
//  IR LED と受信モジュールを数cmの距離で向かい合わせにして実行する。
//  「★受信しました！」が出れば、送信側の回路とタイミングは正しい。
//
//  エアコンが反応しないのにこのテストが通る場合、原因は
//  「信号の中身」ではなく「光量不足（＝LEDに流れる電流が足りない）」。
//
//  配線:  受信モジュール Y → GPIO15 / R → 3.3V / G → GND
//         送信LED             → GPIO4 (S8050経由)
// ---------------------------------------------------------------------------

#include <Arduino.h>
#include <IRremoteESP8266.h>
#include <IRrecv.h>
#include <IRsend.h>
#include <IRutils.h>
#include <ir_Mitsubishi.h>

const uint16_t kRecvPin  = 15;
const uint16_t kIrLedPin = 4;

IRrecv irrecv(kRecvPin, 1024, 50, true);
IRMitsubishiAC ac(kIrLedPin);
decode_results results;

// 電源ON / ドライ / 24℃ / 風量自動 / 風向middle
uint8_t stateOn[18] = {0x23, 0xCB, 0x26, 0x01, 0x00, 0x20, 0x10, 0x08,
                       0x32, 0x58, 0x00, 0x00, 0x00, 0x00, 0x00, 0x10,
                       0x00, 0xE7};

void setup() {
  Serial.begin(115200);
  delay(1000);
  irrecv.enableIRIn();
  ac.begin();
  Serial.println("準備完了");
}

void loop() {
  Serial.println("--- 送信します ---");
  ac.setRaw(stateOn);
  ac.send();

  delay(200);

  if (irrecv.decode(&results)) {
    Serial.println("★受信しました！");
    Serial.println(resultToHumanReadableBasic(&results));
    irrecv.resume();
  } else {
    Serial.println("受信できず");
  }

  delay(5000);
}
