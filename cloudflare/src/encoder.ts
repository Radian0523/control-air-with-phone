// encode(setting) -> 36文字。design.md §7 の純粋関数。
// 外部状態を参照しない。入力は validate.ts を通った Setting だけを受ける。

export type Mode = "auto" | "cool" | "dry" | "heat" | "fan";
export type Fan = "auto" | "1" | "2" | "3";
export type Vane = "auto" | "highest" | "high" | "middle" | "low" | "lowest" | "swing";

export interface Setting {
  power: boolean;
  mode: Mode;
  temp: number; // 16〜31 の整数
  fan: Fan;
  vane: Vane;
}

export const TEMP_MIN = 16;
export const TEMP_MAX = 31;

// §7.1 byte 6
const MODE_BYTE6: Record<Mode, number> = {
  auto: 0x20,
  cool: 0x18,
  dry: 0x10,
  heat: 0x08,
  fan: 0x38,
};

// §7.1 byte 8。上位4bit の 3 は水平風向を中央へ固定する意味を持つ
const MODE_BYTE8: Record<Mode, number> = {
  auto: 0x30,
  cool: 0x36,
  dry: 0x32,
  heat: 0x30,
  fan: 0x37,
};

// §7.1 fan値（byte 9 の下位3bit）。対象リモコンは自動と3段のみ（ADR-019、docs/ir-captures.md）
const FAN_VALUE: Record<Fan, number> = {
  auto: 0,
  "1": 1,
  "2": 2,
  "3": 3,
};

// §7.1 vane値（byte 9 の bit 3〜5）
const VANE_VALUE: Record<Vane, number> = {
  auto: 0,
  highest: 1,
  high: 2,
  middle: 3,
  low: 4,
  lowest: 5,
  swing: 7,
};

/** 18バイトの生バイト列を返す。テストと採取値照合のために公開する */
export function encodeBytes(s: Setting): Uint8Array {
  if (!Number.isInteger(s.temp) || s.temp < TEMP_MIN || s.temp > TEMP_MAX) {
    throw new RangeError(`temp out of range: ${s.temp}`);
  }
  const b = new Uint8Array(18);
  b[0] = 0x23;
  b[1] = 0xcb;
  b[2] = 0x26;
  b[3] = 0x01;
  b[4] = 0x00;
  b[5] = s.power ? 0x20 : 0x00;
  b[6] = MODE_BYTE6[s.mode];
  b[7] = s.temp - TEMP_MIN;
  b[8] = MODE_BYTE8[s.mode];
  // bit 6 は常に1（0x40）、bit 7 は常に0。実機リモコンの電源ボタン（フルステート）フレームに一致する。
  // ボタン直後だけ現れる 0x98 / 0x81 の形は採用しない（docs/ir-captures.md）
  b[9] = 0x40 | (VANE_VALUE[s.vane] << 3) | FAN_VALUE[s.fan];
  // byte 10〜14 は 0x00（初期化済み）
  // byte 15 はリモコンでは電源ボタン時 0x10、他ボタン時 0x00。エアコンは両方を受理するので 0x10 固定
  b[15] = 0x10;
  b[16] = 0x00;
  let sum = 0;
  for (let i = 0; i < 17; i++) sum += b[i]!;
  b[17] = sum & 0xff;
  return b;
}

/** 36文字の大文字16進テキスト（design.md §4.3 の機器向けメッセージ） */
export function encode(s: Setting): string {
  return Array.from(encodeBytes(s), (v) => v.toString(16).toUpperCase().padStart(2, "0")).join("");
}
