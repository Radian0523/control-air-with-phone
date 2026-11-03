// ir_frame.h のホスト側テスト（Arduino 不要）。
//   cd firmware/ir_serial_test/host_test && c++ -std=c++17 -Wall -Wextra -o ir_frame_test ir_frame_test.cpp && ./ir_frame_test
#include <cstdio>
#include <cstring>
#include "../ir_frame.h"

static int failures = 0;

static void check(bool cond, const char *name) {
  std::printf("%s %s\n", cond ? "ok  " : "FAIL", name);
  if (!cond) failures++;
}

static bool parses(const char *s) {
  uint8_t st[18];
  return ir_frame::parse(s, std::strlen(s), st);
}

int main() {
  const char *good = "23CB260100201008325800000000001000E7";
  uint8_t st[18];
  check(ir_frame::parse(good, 36, st), "36文字の大文字16進を受理");
  const uint8_t expect[18] = {0x23, 0xCB, 0x26, 0x01, 0x00, 0x20, 0x10, 0x08, 0x32,
                              0x58, 0x00, 0x00, 0x00, 0x00, 0x00, 0x10, 0x00, 0xE7};
  check(std::memcmp(st, expect, 18) == 0, "18バイトへ正しく変換");

  check(!parses("23cb260100201008325800000000001000e7"), "小文字は拒否");
  check(!parses("23CB260100201008325800000000001000E"), "35文字は拒否");
  check(!parses("23CB260100201008325800000000001000E70"), "37文字は拒否");
  check(!parses(""), "空文字は拒否");
  check(!parses("23CB260100201008325800000000001000E7\n"), "末尾LFは拒否");
  check(!parses("23CB260100201008325800000000001000E7\r"), "末尾CRは拒否");
  check(!parses(" 23CB260100201008325800000000001000E"), "先頭空白は拒否");
  check(!parses("23CB26010020100832580000000000100 E7"), "途中空白は拒否");
  check(!parses("23CB260100201008325800000000001000G7"), "16進以外の文字は拒否");
  check(!ir_frame::parse(nullptr, 36, st), "nullptr は拒否");

  // 埋め込み NUL: 長さは36だが途中に \0
  char withNul[36];
  std::memcpy(withNul, good, 36);
  withNul[10] = '\0';
  check(!ir_frame::parse(withNul, 36, st), "埋め込みNULは拒否");

  // 照明の8文字（ADR-022）
  uint32_t code = 0;
  check(ir_frame::parseLight("01A359A6", 8, code) && code == 0x01A359A6u, "照明8文字を32bitへ変換");
  check(!ir_frame::parseLight("01a359a6", 8, code), "照明: 小文字は拒否");
  check(!ir_frame::parseLight("01A359A", 7, code), "照明: 7文字は拒否");
  check(!ir_frame::parseLight("01A359A60", 9, code), "照明: 9文字は拒否");
  check(!ir_frame::parseLight("01A359G6", 8, code), "照明: 16進以外は拒否");
  check(!ir_frame::parseLight(nullptr, 8, code), "照明: nullptr は拒否");
  check(!ir_frame::parse("01A359A6", 8, st), "8文字はエアコンとしては拒否");
  check(!ir_frame::parseLight(good, 36, code), "36文字は照明としては拒否");

  std::printf("%s (%d failures)\n", failures == 0 ? "ALL PASSED" : "FAILED", failures);
  return failures == 0 ? 0 : 1;
}
