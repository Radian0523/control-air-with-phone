// ---------------------------------------------------------------------------
//  aircon_bridge.ino — 本番ファーム（design.md §4）
//
//  責務は3つだけ（§4.1）:
//    1. Wi-Fi へ接続する
//    2. Cloudflare との WebSocket over TLS 接続を維持する
//    3. 正しい36文字（エアコン）または8文字（照明）を赤外線で送信する
//
//  状態機械:
//    BOOT → CONNECTING（Wi-Fi 15s → 必要時だけ NTP 10s → WebSocket 15s）→ ONLINE
//    接続失敗 / WebSocket close / heartbeat 不応答 → TEARDOWN → OFF_WAIT（30s）→ CONNECTING
//    ONLINE に10分戻れない、または loop() が5分進まない → 診断記録を残して再起動（ADR-021）
//
//  ボード設定（§4.7）:
//    esp32:esp32 3.3.11 / IRremoteESP8266 2.9.0 / arduinoWebSockets 2.7.2
//    Partition: Huge APP (3MB No OTA/1MB SPIFFS) / Upload Speed 115200
//
//  試験用ビルド（段階5）:
//    下の AIRCON_DEBUG_HEAP のコメントを外すと、ws_connected / ws_failed 行に free heap と
//    TLS 接続にかかった時間を付け、ONLINE 中は5分ごとに heap を出す。本番ではコメントのままにする。
//
//  診断記録（§4.10）:
//    切断・自動再起動・起動の直近16件を NVS に残し、起動時に `diag ...` 行として出す。
//    USB アダプタで運用中に起きたことを、あとで Mac につないで読むためのもの。
// ---------------------------------------------------------------------------

// #define AIRCON_DEBUG_HEAP

#include <Arduino.h>
#include <WiFi.h>
#include <WebSocketsClient.h>
#include <IRremoteESP8266.h>
#include <IRsend.h>
#include <esp_task_wdt.h>
#include <esp_freertos_hooks.h>
#include <esp_timer.h>
#include <Preferences.h>
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
constexpr uint32_t kOfflineRestartMs = 600000;   // ONLINE 以外が10分続いたら再起動（ADR-021）
constexpr uint32_t kLoopStallRestartMs = 300000;  // loop() が5分進まなければ再起動。CONNECTING 最悪約160sより長い
constexpr uint64_t kStallCheckPeriodUs = 10000000;  // 10s
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
// 切断理由（ライブラリが渡す文字列。秘密情報は含まない）と Wi-Fi 切断理由。原因の切り分け用
char wsCloseReason[48] = "";
volatile int wifiLostReason = -1;

// オフライン期間の集計。診断記録の offline_restart 行に使う。ONLINE になったら0へ戻す
uint32_t offlineSince = 0;  // 起動直後もオフライン扱い
uint16_t wifiFails = 0;
uint16_t wsFails = 0;
uint16_t timeFails = 0;
uint8_t lastWifiStatus = 0;
uint8_t lastWifiReason = 0;
int8_t lastRssi = 0;

// loop() が最後に回った時刻。esp_timer から見張る
volatile uint32_t loopAliveAt = 0;

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

// ---- 診断記録（§4.10、ADR-021）-------------------------------------------------
// NVS に固定長のリングを1つだけ置く。業務データは置かない（§4.2）
namespace diag {

enum Code : uint8_t { kBoot = 1, kWsLost = 2, kOfflineRestart = 3, kLoopStall = 4 };

struct Event {
  uint32_t epoch;    // UTC 秒。時刻未同期なら0
  uint32_t uptimeS;
  uint8_t code;
  int8_t rssi;
  uint8_t a;         // kBoot: esp_reset_reason / kWsLost: WiFi.status / kOfflineRestart: 最後の WiFi.status / kLoopStall: State
  uint8_t b;         // kWsLost: 理由の種類 / kOfflineRestart: 最後の Wi-Fi 切断理由
  uint16_t c;        // kOfflineRestart: wifi_failed 回数
  uint16_t d;        // kOfflineRestart: ws_failed 回数
  uint16_t e;        // kOfflineRestart: time_failed 回数
  uint16_t reserved;
};

constexpr size_t kEvents = 16;

struct Ring {
  uint8_t next;
  uint8_t reserved[3];
  Event events[kEvents];
};

Preferences prefs;
Ring ring;

// loop 停止で再起動する時は esp_timer から NVS を書かず、RTC に印だけ残して起動時に記録する
constexpr uint32_t kStallMagic = 0x5354414c;  // "STAL"
struct StallMarker {
  uint32_t magic;
  uint32_t epoch;
  uint32_t uptimeS;
  uint8_t state;
};
RTC_NOINIT_ATTR StallMarker stallMarker;

uint32_t nowEpoch() {
  const time_t t = time(nullptr);
  return t >= kMinValidTime ? static_cast<uint32_t>(t) : 0;
}

void push(const Event &ev) {
  ring.events[ring.next] = ev;
  ring.next = (ring.next + 1) % kEvents;
  prefs.putBytes("ring", &ring, sizeof(ring));
}

void record(Code code, int8_t rssi, uint8_t a, uint8_t b = 0, uint16_t c = 0, uint16_t d = 0,
            uint16_t e = 0) {
  push(Event{nowEpoch(), millis() / 1000, code, rssi, a, b, c, d, e, 0});
}

const char *codeName(uint8_t code) {
  switch (code) {
    case kBoot: return "boot";
    case kWsLost: return "ws_lost";
    case kOfflineRestart: return "offline_restart";
    case kLoopStall: return "loop_stall";
    default: return "unknown";
  }
}

// 古い順に `diag ...` 行を出す
void dump() {
  for (size_t i = 0; i < kEvents; ++i) {
    const Event &ev = ring.events[(ring.next + i) % kEvents];
    if (ev.code == 0) continue;
    Serial.printf("diag epoch=%lu up=%lu %s rssi=%d a=%u b=%u c=%u d=%u e=%u\n",
                  static_cast<unsigned long>(ev.epoch), static_cast<unsigned long>(ev.uptimeS),
                  codeName(ev.code), ev.rssi, ev.a, ev.b, ev.c, ev.d, ev.e);
  }
}

void begin(int resetReason) {
  prefs.begin("diag", false);
  if (prefs.getBytes("ring", &ring, sizeof(ring)) != sizeof(ring)) memset(&ring, 0, sizeof(ring));
  ring.next %= kEvents;
  if (stallMarker.magic == kStallMagic) {
    push(Event{stallMarker.epoch, stallMarker.uptimeS, kLoopStall, 0, stallMarker.state, 0, 0, 0, 0, 0});
    stallMarker.magic = 0;
  }
  record(kBoot, 0, static_cast<uint8_t>(resetReason));
  dump();
}

}  // namespace diag

// esp_timer タスクから10秒ごとに呼ばれる。loop() が固まっていたら再起動する
void checkLoopStall(void *) {
  if (millis() - loopAliveAt < kLoopStallRestartMs) return;
  diag::stallMarker = {diag::kStallMagic, diag::nowEpoch(), millis() / 1000,
                       static_cast<uint8_t>(state)};
  esp_restart();
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
    case WStype_ERROR: {
      const size_t n = length < sizeof(wsCloseReason) - 1 ? length : sizeof(wsCloseReason) - 1;
      if (payload != nullptr) memcpy(wsCloseReason, payload, n);
      wsCloseReason[payload != nullptr ? n : 0] = '\0';
      wsClosedEvent = true;
      break;
    }

    case WStype_TEXT: {
      // §4.3 / §4.4: 正しい36文字（エアコン）か8文字（照明、ADR-022）だけを同期送信。応答は返さない
      if (length == ir_frame::kLightTextLength) {
        uint32_t code;
        if (!ir_frame::parseLight(reinterpret_cast<const char *>(payload), length, code)) {
          logEvent("invalid_frame");
          break;
        }
        irsend.sendNEC(code, kNECBits);
        logEvent("ir_sent");
        break;
      }
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
      Serial.printf("wifi_failed status=%d reason=%d\n", static_cast<int>(WiFi.status()),
                    wifiLostReason);
      ++wifiFails;
      lastWifiStatus = static_cast<uint8_t>(WiFi.status());
      lastWifiReason = static_cast<uint8_t>(wifiLostReason < 0 ? 0 : wifiLostReason);
      return false;
    }
    delay(50);
  }
  logEvent("wifi_connected");
  wifiLostReason = -1;  // 接続処理中の切断理由は捨て、ONLINE 中のものだけを出す
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
      ++timeFails;
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
      ++wsFails;
      lastRssi = static_cast<int8_t>(WiFi.RSSI());
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

  // Wi-Fi 切断理由（wifi_err_reason_t）を loop() で出す。イベントタスクでは記録だけ
  WiFi.onEvent(
      [](arduino_event_id_t, arduino_event_info_t info) {
        wifiLostReason = info.wifi_sta_disconnected.reason;
      },
      ARDUINO_EVENT_WIFI_STA_DISCONNECTED);

  // reset_reason: 1 POWERON, 3 SW, 4 PANIC, 5 INT_WDT, 6 TASK_WDT, 7 WDT, 9 BROWNOUT
  const int resetReason = static_cast<int>(esp_reset_reason());
  Serial.printf("boot reset_reason=%d\n", resetReason);
  diag::begin(resetReason);

  // loop() 停止の見張り（ADR-021）。Task WDT の5秒は IDLE1 用のまま変えない
  loopAliveAt = millis();
  const esp_timer_create_args_t stallTimerArgs = {
      .callback = checkLoopStall, .arg = nullptr, .dispatch_method = ESP_TIMER_TASK,
      .name = "loop_stall", .skip_unhandled_events = true};
  esp_timer_handle_t stallTimer;
  esp_timer_create(&stallTimerArgs, &stallTimer);
  esp_timer_start_periodic(stallTimer, kStallCheckPeriodUs);

  // §4.6: CA bundle が無ければ接続しない（null は検証なし接続になるため）
  if (ca_bundle == nullptr || ca_bundle_len == 0) {
    Serial.println(F("ca_bundle_missing"));
    for (;;) delay(1000);
  }
}

void loop() {
  loopAliveAt = millis();

  switch (state) {
    case State::Connecting:
      if (connectWifi() && syncTimeIfNeeded() && connectWebSocket()) {
        state = State::Online;
        wifiFails = wsFails = timeFails = 0;
      } else {
        state = State::Teardown;
      }
      break;

    case State::Online:
      webSocket.loop();
      if (wifiLostReason >= 0) {
        Serial.printf("wifi_lost reason=%d\n", wifiLostReason);
        wifiLostReason = -1;
      }
      if (wsClosedEvent) {
        const int wifiStatus = static_cast<int>(WiFi.status());
        Serial.printf("ws_disconnected reason=\"%s\" wifi=%d uptime_s=%lu\n", wsCloseReason,
                      wifiStatus, millis() / 1000);
        // 理由の種類: 0 なし（heartbeat 不応答など）/ 1 Connection lost / 2 その他
        const uint8_t kind = wsCloseReason[0] == '\0'                            ? 0
                             : strcmp(wsCloseReason, "Connection lost") == 0 ? 1
                                                                             : 2;
        diag::record(diag::kWsLost, static_cast<int8_t>(WiFi.RSSI()),
                     static_cast<uint8_t>(wifiStatus), kind);
        offlineSince = millis();
        state = State::Teardown;
      }
#ifdef AIRCON_DEBUG_HEAP
      if (millis() - lastHeapReportAt >= kHeapReportIntervalMs) {
        lastHeapReportAt = millis();
        Serial.printf("heap=%u min_heap=%u rssi=%d uptime_s=%lu\n",
                      static_cast<unsigned>(ESP.getFreeHeap()),
                      static_cast<unsigned>(ESP.getMinFreeHeap()), WiFi.RSSI(), millis() / 1000);
      }
#endif
      break;

    case State::Teardown:
      teardown();
      break;

    case State::OffWait:
      // OFF_WAIT 中は webSocket.loop() を呼ばない（§4.5）
      if (millis() - offlineSince >= kOfflineRestartMs) {
        // ADR-021: 自力で ONLINE に戻れない状態を放置しない
        Serial.printf("offline_restart wifi_fails=%u ws_fails=%u time_fails=%u\n", wifiFails,
                      wsFails, timeFails);
        diag::record(diag::kOfflineRestart, lastRssi, lastWifiStatus, lastWifiReason, wifiFails,
                     wsFails, timeFails);
        Serial.flush();
        ESP.restart();
      }
      if (millis() - offWaitStartedAt >= kOffWaitMs) state = State::Connecting;
      break;
  }

  delay(1);  // §4.4: IDLE1 へ譲る（Task WDT 3点セットの3つ目）
}
