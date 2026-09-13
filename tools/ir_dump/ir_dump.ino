// ---------------------------------------------------------------------------
//  ir_dump.ino  —  リモコンの赤外線信号を採取して、そのまま貼れる形で出力する
//
//  使い方:
//    1. 受信モジュールを接続する (Y → GPIO15 / R → 3.3V / G → GND)
//    2. これを書き込み、シリアルモニタ (115200) を開く
//    3. 受信モジュールにリモコンを向けてボタンを押す
//    4. 出力された uint8_t の配列をそのままスケッチに貼り付けられる
//
//  ※ 本番のESP32は受信や設定値の組み立てを行わない。
//     Cloudflare側のencoderが生成する18バイトを実機リモコンと照合するため、
//     このスケッチで必要な設定の生パケットを採取する。
//     GPIO15はstrapping pinなので、受信モジュールは解析時だけ接続する。
// ---------------------------------------------------------------------------

#include <Arduino.h>
#include <IRremoteESP8266.h>
#include <IRrecv.h>
#include <IRac.h>
#include <IRutils.h>

const uint16_t kRecvPin = 15;

// エアコンのリモコンは信号が長いので、バッファは大きめに取る
IRrecv irrecv(kRecvPin, 1024, 50, true);
decode_results results;

void setup() {
  Serial.begin(115200);
  delay(500);
  irrecv.enableIRIn();
  Serial.println();
  Serial.println(F("=== IR ダンプ ==="));
  Serial.println(F("受信モジュールにリモコンを向けてボタンを押してください"));
}

void loop() {
  if (!irrecv.decode(&results)) return;

  Serial.println();
  Serial.print(F("プロトコル : "));
  Serial.println(typeToString(results.decode_type, results.repeat));
  Serial.print(F("ビット数   : "));
  Serial.println(results.bits);

  if (hasACState(results.decode_type)) {
    const uint16_t len = results.bits / 8;

    Serial.println();
    Serial.println(F("--- ここから下をスケッチに貼り付けられます ---"));
    Serial.printf("uint8_t state[%u] = {", len);
    for (uint16_t i = 0; i < len; i++) {
      if (i % 9 == 0) Serial.print(F("\n    "));
      Serial.printf("0x%02X", results.state[i]);
      if (i != len - 1) Serial.print(F(", "));
    }
    Serial.println(F("};"));
    Serial.println(F("---------------------------------------------"));

    String desc = IRAcUtils::resultAcToString(&results);
    if (desc.length()) {
      Serial.println();
      Serial.println(F("デコード結果:"));
      Serial.println(desc);
    }
  } else {
    Serial.println(resultToHumanReadableBasic(&results));
  }

  yield();
  irrecv.resume();
}
