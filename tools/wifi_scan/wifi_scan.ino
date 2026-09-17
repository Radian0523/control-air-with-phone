// ---------------------------------------------------------------------------
//  wifi_scan.ino — ESP32 から見える Wi-Fi を一覧する（wifi_failed の切り分け用）
//
//  ESP32 は 2.4GHz だけを受信できる。ここに家の SSID が出なければ、
//  そのネットワークは 5GHz 専用か、SSID がステルスか、電波が届いていない。
//  暗号化方式が WPA3 のみ（WPA3-Personal）の場合も接続できない。
//  WPA2 または WPA2/WPA3 混在なら接続できる。
//
//  シリアルモニタ 115200。10秒ごとに再スキャンする。
// ---------------------------------------------------------------------------

#include <Arduino.h>
#include <WiFi.h>

const char *authName(wifi_auth_mode_t m) {
  switch (m) {
    case WIFI_AUTH_OPEN: return "OPEN";
    case WIFI_AUTH_WEP: return "WEP";
    case WIFI_AUTH_WPA_PSK: return "WPA";
    case WIFI_AUTH_WPA2_PSK: return "WPA2";
    case WIFI_AUTH_WPA_WPA2_PSK: return "WPA/WPA2";
    case WIFI_AUTH_WPA2_ENTERPRISE: return "WPA2-Enterprise";
    case WIFI_AUTH_WPA3_PSK: return "WPA3 only (ESP32 は不可)";
    case WIFI_AUTH_WPA2_WPA3_PSK: return "WPA2/WPA3";
    default: return "other";
  }
}

void setup() {
  Serial.begin(115200);
  WiFi.persistent(false);
  WiFi.mode(WIFI_STA);
  WiFi.disconnect();
  delay(200);
}

void loop() {
  Serial.println(F("--- scan ---"));
  const int n = WiFi.scanNetworks();
  if (n <= 0) {
    Serial.println(F("(何も見えない)"));
  }
  for (int i = 0; i < n; i++) {
    Serial.printf("%-32s ch%-3d %4d dBm  %s%s\n",
                  WiFi.SSID(i).c_str(), WiFi.channel(i), WiFi.RSSI(i),
                  authName(WiFi.encryptionType(i)),
                  WiFi.SSID(i).length() == 0 ? "  (ステルス)" : "");
  }
  WiFi.scanDelete();
  delay(10000);
}
