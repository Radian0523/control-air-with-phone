// ---------------------------------------------------------------------------
//  aircon_bridge.ino — 本番ファーム（design.md §4）
//
//  責務は3つだけ（§4.1）:
//    1. Wi-Fi へ接続する
//    2. Cloudflare との WebSocket over TLS 接続を維持する
//    3. 正しい36文字を18バイトへ変換し、赤外線で送信する
//
//  状態機械:
//    BOOT → CONNECTING（Wi-Fi 15s → 必要時だけ NTP 10s → WebSocket 15s）→ ONLINE
//    接続失敗 / WebSocket close / heartbeat 不応答 → TEARDOWN → OFF_WAIT（30s）→ CONNECTING
//
//  ボード設定（§4.7）:
//    esp32:esp32 3.3.11 / IRremoteESP8266 2.9.0 / arduinoWebSockets 2.7.2
//    Partition: Huge APP (3MB No OTA/1MB SPIFFS) / Upload Speed 115200
//
//  試験用ビルド（段階5）:
//    下の AIRCON_DEBUG_HEAP のコメントを外すと、ws_connected / ws_failed 行に free heap と
//    TLS 接続にかかった時間を付け、ONLINE 中は5分ごとに heap を出す。本番ではコメントのままにする。
// ---------------------------------------------------------------------------

// #define AIRCON_DEBUG_HEAP

#include <Arduino.h>
#include <WiFi.h>
#include <WebSocketsClient.h>
#include <IRremoteESP8266.h>
#include <IRsend.h>
#include <esp_task_wdt.h>
#include <esp_freertos_hooks.h>
#include <driver/gpio.h>
#include <time.h>

#include "ir_frame.h"
#include "secrets.h"     // WIFI_SSID, WIFI_PASSWORD, WS_HOST, WS_PORT, WS_PATH, DEVICE_TOKEN
#include "ca_bundle.h"   // ca_bundle[], ca_bundle_len（Mozilla full bundle）

namespace {

// ---- 定数（§4.5、§8.1）------------------------------------------------------
constexpr uint8_t kIrLedPin = 4;
constexpr uint32_t kWifiTimeoutMs = 15000;
constexpr uint32_t kNtpTimeoutMs = 10000;
constexpr uint32_t kWsTimeoutMs = 15000;
constexpr uint32_t kOffWaitMs = 30000;
constexpr uint32_t kWsInnerRetryMs = 30000;  // CONNECTING 中の内部再試行を止める（15s より長い値）
constexpr time_t kMinValidTime = 1704067200;  // 2024-01-01T00:00:00Z
constexpr uint32_t kHeartbeatIntervalMs = 30000;
constexpr uint32_t kHeartbeatPongTimeoutMs = 10000;
constexpr uint8_t kHeartbeatFailures = 2;
#ifdef AIRCON_DEBUG_HEAP
constexpr uint32_t kHeapReportIntervalMs = 300000;  // 5分
uint32_t lastHeapReportAt = 0;
#endif

enum class State { Connecting, Online, Teardown, OffWait };

State state = State::Connecting;
uint32_t offWaitStartedAt = 0;

// WebSocket イベントから loop() へ渡すフラグ。イベント内では状態遷移を直接行わない
volatile bool wsConnectedEvent = false;
volatile bool wsClosedEvent = false;

WebSocketsClient webSocket;
IRsend irsend(kIrLedPin);

// ---- ログ（§4.8: 状態変化だけ。秘密情報と payload は出さない）------------------
void logEvent(const char *event) { Serial.println(event); }

// 接続結果の行。試験用ビルドでは heap と TLS 所要時間を付ける
void logWsResult(const char *event, uint32_t tlsMs) {
#ifdef AIRCON_DEBUG_HEAP
  Serial.printf("%s heap=%u min_heap=%u tls_ms=%u\n", event,
                static_cast<unsigned>(ESP.getFreeHeap()),
                static_cast<unsigned>(ESP.getMinFreeHeap()),
                static_cast<unsigned>(tlsMs));
#else
  (void)tlsMs;
  logEvent(event);
#endif
}

// ---- Task WDT（§4.4: add / idle hook / delay(1) の3点セット）-------------------
bool feedTaskWdtFromIdle1() {
  esp_task_wdt_reset();
  return true;
}

// ---- WebSocket イベント ----------------------------------------------------------
void onWebSocketEvent(WStype_t type, uint8_t *payload, size_t length) {
  switch (type) {
    case WStype_CONNECTED:
      wsConnectedEvent = true;
      break;

    case WStype_DISCONNECTED:
    case WStype_ERROR:
      wsClosedEvent = true;
      break;

    case WStype_TEXT: {
      // §4.3 / §4.4: 正しい36文字だけを同期送信。応答は返さない
      uint8_t stateBytes[ir_frame::kStateLength];
      if (!ir_frame::parse(reinterpret_cast<const char *>(payload), length, stateBytes)) {
        logEvent("invalid_frame");
        break;
      }
      irsend.send(MITSUBISHI_AC, stateBytes, ir_frame::kStateLength);
      logEvent("ir_sent");
      break;
    }

    case WStype_BIN:
      logEvent("invalid_frame");
      break;

    default:
      // PING/PONG、フラグメント等はライブラリに任せる（§4.3）
      break;
  }
}

// ---- CONNECTING の各段階 --------------------------------------------------------
bool connectWifi() {
  WiFi.mode(WIFI_STA);
  WiFi.setAutoReconnect(false);  // 再接続の規則はこのファームが1つだけ持つ（ADR-017）
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  const uint32_t start = millis();
  while (WiFi.status() != WL_CONNECTED) {
    if (millis() - start >= kWifiTimeoutMs) {
      // status は原因の切り分け用（秘密情報ではない）。
      //   1 NO_SSID_AVAIL: SSID が見えない（綴り違い、5GHz 専用、ステルス）
      //   4 CONNECT_FAILED: 認証失敗（パスワード違い、WPA3 専用）
      //   6 DISCONNECTED / 0 IDLE: 接続処理が進んでいない（電波が弱い、DHCP 失敗）
      Serial.printf("wifi_failed status=%d\n", static_cast<int>(WiFi.status()));
      return false;
    }
    delay(50);
  }
  logEvent("wifi_connected");
  return true;
}

bool haveValidTime() { return time(nullptr) >= kMinValidTime; }

bool syncTimeIfNeeded() {
  if (haveValidTime()) return true;  // 有効な時刻があれば NTP を省略する（§4.5）
  configTime(0, 0, "time.cloudflare.com", "time.google.com", "pool.ntp.org");
  const uint32_t start = millis();
  while (!haveValidTime()) {
    if (millis() - start >= kNtpTimeoutMs) {
      logEvent("time_failed");
      return false;
    }
    delay(50);
  }
  logEvent("time_synced");
  return true;
}

bool connectWebSocket() {
  wsConnectedEvent = false;
  wsClosedEvent = false;

  static char authHeader[] = "Authorization: Bearer " DEVICE_TOKEN;
  webSocket.setExtraHeaders(authHeader);
  webSocket.onEvent(onWebSocketEvent);
  webSocket.enableHeartbeat(kHeartbeatIntervalMs, kHeartbeatPongTimeoutMs, kHeartbeatFailures);

  // §4.5: 1回の CONNECTING につき接続試行は1回だけ。
  // 間隔 0 で最初の loop() を呼んで直ちに試行を始め、直後に 30s へ変更して同一サイクル内の再試行を止める。
  // 最初の loop() の中で TCP と TLS の接続が同期的に完了する（内部ブロックは最大120秒程度）。
  webSocket.setReconnectInterval(0);
  // protocol を空にすると Sec-WebSocket-Protocol ヘッダを送らない
  webSocket.beginSslWithBundle(WS_HOST, WS_PORT, WS_PATH, ca_bundle, ca_bundle_len, "");
  const uint32_t start = millis();
  webSocket.loop();  // ここで TCP と TLS handshake が同期的に走る
  const uint32_t tlsMs = millis() - start;
  webSocket.setReconnectInterval(kWsInnerRetryMs);

  while (!wsConnectedEvent) {
    if (wsClosedEvent || millis() - start >= kWsTimeoutMs) {
      logWsResult("ws_failed", tlsMs);
      return false;
    }
    webSocket.loop();
    delay(1);
  }
  logWsResult("ws_connected", tlsMs);
  return true;
}

// ---- TEARDOWN（§4.5: 後始末 → Wi-Fi OFF → 30秒待機）----------------------------
void teardown() {
  webSocket.disconnect();
  WiFi.disconnect(true, false);
  WiFi.mode(WIFI_OFF);
  offWaitStartedAt = millis();
  state = State::OffWait;
}

}  // namespace

void setup() {
  // §4.1 BOOT: 出力レジスタを LOW にしてから OUTPUT 化（core 3.x は pinMode 前の digitalWrite を無視する）
  gpio_set_level(static_cast<gpio_num_t>(kIrLedPin), 0);
  pinMode(kIrLedPin, OUTPUT);
  digitalWrite(kIrLedPin, LOW);

  // §4.4 Task WDT 3点セット（3つ目は loop() 末尾の delay(1)）
  enableCore1WDT();
  esp_register_freertos_idle_hook_for_cpu(feedTaskWdtFromIdle1, 1);

  Serial.begin(115200);
  irsend.begin();

  // ADR-003: Wi-Fi ドライバによる資格情報の NVS 保存を無効にする。WiFi.mode/begin より前に1回
  WiFi.persistent(false);

  logEvent("boot");

  // §4.6: CA bundle が無ければ接続しない（null は検証なし接続になるため）
  if (ca_bundle == nullptr || ca_bundle_len == 0) {
    Serial.println(F("ca_bundle_missing"));
    for (;;) delay(1000);
  }
}

void loop() {
  switch (state) {
    case State::Connecting:
      if (connectWifi() && syncTimeIfNeeded() && connectWebSocket()) {
        state = State::Online;
      } else {
        state = State::Teardown;
      }
      break;

    case State::Online:
      webSocket.loop();
      if (wsClosedEvent) {
        logEvent("ws_disconnected");
        state = State::Teardown;
      }
#ifdef AIRCON_DEBUG_HEAP
      if (millis() - lastHeapReportAt >= kHeapReportIntervalMs) {
        lastHeapReportAt = millis();
        Serial.printf("heap=%u min_heap=%u\n", static_cast<unsigned>(ESP.getFreeHeap()),
                      static_cast<unsigned>(ESP.getMinFreeHeap()));
      }
#endif
      break;

    case State::Teardown:
      teardown();
      break;

    case State::OffWait:
      // OFF_WAIT 中は webSocket.loop() を呼ばない（§4.5）
      if (millis() - offWaitStartedAt >= kOffWaitMs) state = State::Connecting;
      break;
  }

  delay(1);  // §4.4: IDLE1 へ譲る（Task WDT 3点セットの3つ目）
}
