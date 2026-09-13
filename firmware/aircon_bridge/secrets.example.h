// secrets.example.h — このファイルを secrets.h にコピーして値を埋める。
// secrets.h は .gitignore 済み。コミットしないこと。
#pragma once

// 家庭 Wi-Fi（design.md ADR-003: ファームウェア定数として焼き込む）
#define WIFI_SSID      "your-ssid"
#define WIFI_PASSWORD  "your-password"

// Cloudflare Worker（design.md §4.5 / §4.6）
#define WS_HOST        "aircon.example.workers.dev"
#define WS_PORT        443
#define WS_PATH        "/device/ws"

// Worker secret DEVICE_TOKEN と同じ値（design.md §5.3）
#define DEVICE_TOKEN   "replace-with-device-token"
