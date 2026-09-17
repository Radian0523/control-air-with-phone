import { describe, expect, it } from "vitest";
import { encode, encodeBytes, type Setting } from "../../src/encoder";

// design.md §7.2 必須テストベクトル（docs/ir-captures.md の採取に基づく）。
// captured: 実機リモコンの電源ボタン（フルステート）フレームと完全一致
// normalized: 採取値の byte 15 を電源ボタン形式の 0x10 に正規化したもの（他バイトは採取で確認済み）
const VECTORS: Array<{ name: string; origin: "captured" | "normalized"; setting: Setting; expected: string }> = [
  {
    name: "ON / dry / 24℃ / auto / middle",
    origin: "captured",
    setting: { power: true, mode: "dry", temp: 24, fan: "auto", vane: "middle" },
    expected: "23CB260100201008325800000000001000E7",
  },
  {
    name: "ON / cool / 26℃ / auto / middle",
    origin: "captured",
    setting: { power: true, mode: "cool", temp: 26, fan: "auto", vane: "middle" },
    expected: "23CB26010020180A365800000000001000F5",
  },
  {
    name: "OFF / cool / 26℃ / auto / middle",
    origin: "captured",
    setting: { power: false, mode: "cool", temp: 26, fan: "auto", vane: "middle" },
    expected: "23CB26010000180A365800000000001000D5",
  },
  {
    name: "ON / cool / 26℃ / 1 / auto",
    origin: "captured",
    setting: { power: true, mode: "cool", temp: 26, fan: "1", vane: "auto" },
    expected: "23CB26010020180A364100000000001000DE",
  },
  {
    name: "ON / heat / 26℃ / 1 / lowest",
    origin: "normalized",
    setting: { power: true, mode: "heat", temp: 26, fan: "1", vane: "lowest" },
    expected: "23CB26010020080A306900000000001000F0",
  },
];

describe("encode: §7.2 テストベクトル", () => {
  for (const v of VECTORS) {
    it(`${v.name} (${v.origin})`, () => {
      expect(encode(v.setting)).toBe(v.expected);
    });
  }
});

describe("encode: 形式の不変条件", () => {
  const base: Setting = { power: true, mode: "cool", temp: 26, fan: "auto", vane: "auto" };

  it("36文字の大文字16進", () => {
    for (const v of VECTORS) expect(encode(v.setting)).toMatch(/^[0-9A-F]{36}$/);
  });

  it("byte 17 は byte 0〜16 の合計の下位8bit", () => {
    for (const v of VECTORS) {
      const b = encodeBytes(v.setting);
      let sum = 0;
      for (let i = 0; i < 17; i++) sum += b[i]!;
      expect(b[17]).toBe(sum & 0xff);
    }
  });

  it("固定部: byte 0〜4, 10〜14, 15〜16", () => {
    const b = encodeBytes(base);
    expect(Array.from(b.subarray(0, 5))).toEqual([0x23, 0xcb, 0x26, 0x01, 0x00]);
    expect(Array.from(b.subarray(10, 15))).toEqual([0, 0, 0, 0, 0]);
    expect(Array.from(b.subarray(15, 17))).toEqual([0x10, 0x00]);
  });

  it("byte 5: power", () => {
    expect(encodeBytes({ ...base, power: true })[5]).toBe(0x20);
    expect(encodeBytes({ ...base, power: false })[5]).toBe(0x00);
  });

  it("byte 6 / 8: mode", () => {
    const table = { auto: [0x20, 0x30], cool: [0x18, 0x36], dry: [0x10, 0x32], heat: [0x08, 0x30], fan: [0x38, 0x37] } as const;
    for (const [mode, [b6, b8]] of Object.entries(table)) {
      const b = encodeBytes({ ...base, mode: mode as Setting["mode"] });
      expect(b[6]).toBe(b6);
      expect(b[8]).toBe(b8);
    }
  });

  it("byte 7: temp - 16 で 16℃=00, 31℃=0F", () => {
    expect(encodeBytes({ ...base, temp: 16 })[7]).toBe(0x00);
    expect(encodeBytes({ ...base, temp: 31 })[7]).toBe(0x0f);
  });

  it("byte 9: 0x40 | vane<<3 | fan、bit 7 は常に 0", () => {
    const fans = { auto: 0, "1": 1, "2": 2, "3": 3 } as const;
    const vanes = { auto: 0, highest: 1, high: 2, middle: 3, low: 4, lowest: 5, swing: 7 } as const;
    for (const [fan, fv] of Object.entries(fans)) {
      for (const [vane, vv] of Object.entries(vanes)) {
        const b9 = encodeBytes({ ...base, fan: fan as Setting["fan"], vane: vane as Setting["vane"] })[9]!;
        expect(b9).toBe(0x40 | (vv << 3) | fv);
        expect(b9 & 0x80).toBe(0);
      }
    }
  });

  it("fan auto + vane auto は byte 9 = 0x40（リセット後の電源フレーム採取値と一致）", () => {
    expect(encodeBytes({ ...base, fan: "auto", vane: "auto" })[9]).toBe(0x40);
    // 採取: 23 CB 26 01 00 20 18 05 36 40 00 00 00 00 00 00 00 C8（21℃、byte 15 は 00）
    const b = encodeBytes({ ...base, temp: 21, fan: "auto", vane: "auto" });
    expect(Array.from(b.subarray(0, 15))).toEqual([0x23, 0xcb, 0x26, 0x01, 0x00, 0x20, 0x18, 0x05, 0x36, 0x40, 0, 0, 0, 0, 0]);
  });

  it("temp 範囲外は RangeError", () => {
    expect(() => encodeBytes({ ...base, temp: 15 })).toThrow(RangeError);
    expect(() => encodeBytes({ ...base, temp: 32 })).toThrow(RangeError);
    expect(() => encodeBytes({ ...base, temp: 26.5 })).toThrow(RangeError);
  });
});
