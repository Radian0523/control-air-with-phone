// 照明（オーデリック NRL-3321）のボタンと NEC 32bit コード（ADR-022、docs/ir-captures.md）。
// ESP32 へは8文字の大文字16進で送る。どのボタンかの判断はここだけが持つ。

export type LightButton = "on" | "off" | "eco" | "mame";

export const LIGHT_BUTTONS: readonly LightButton[] = ["on", "off", "eco", "mame"];

// 2026-11-03 採取。アドレス 0x01A3 共通
const LIGHT_CODES: Record<LightButton, string> = {
  on: "01A359A6",
  off: "01A310EF",
  eco: "01A3748B",
  mame: "01A354AB",
};

/** ボタンを機器向けの8文字へ変換する */
export function encodeLight(button: LightButton): string {
  return LIGHT_CODES[button];
}
