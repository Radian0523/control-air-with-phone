// ir_frame.h — 36文字の大文字16進テキストを18バイトへ変換する（design.md §4.3）
//
// 本番ファーム aircon_bridge でも同じ内容を使う。Arduino IDE はスケッチ外の
// ヘッダを参照できないため、段階3で aircon_bridge/ へコピーし、両方を同一に保つ。
// 変更するときは必ず両方を更新すること。
#pragma once

#include <stddef.h>
#include <stdint.h>

namespace ir_frame {

constexpr size_t kTextLength = 36;
constexpr size_t kStateLength = 18;

// '0'〜'9'、'A'〜'F' だけを受理する。小文字は不正入力（§4.3）。
inline bool hexValue(char c, uint8_t &out) {
  if (c >= '0' && c <= '9') { out = static_cast<uint8_t>(c - '0'); return true; }
  if (c >= 'A' && c <= 'F') { out = static_cast<uint8_t>(c - 'A' + 10); return true; }
  return false;
}

// text[0..len) を検査し、正しい36文字なら state[18] に書き込んで true を返す。
// 長さ違い、小文字、空白、改行、その他の文字はすべて false（送信しない）。
// state は失敗時に部分的に書き換わることがあるので、成功時だけ使うこと。
inline bool parse(const char *text, size_t len, uint8_t state[kStateLength]) {
  if (text == nullptr || len != kTextLength) return false;
  for (size_t i = 0; i < kStateLength; i++) {
    uint8_t hi, lo;
    if (!hexValue(text[2 * i], hi) || !hexValue(text[2 * i + 1], lo)) return false;
    state[i] = static_cast<uint8_t>((hi << 4) | lo);
  }
  return true;
}

}  // namespace ir_frame
