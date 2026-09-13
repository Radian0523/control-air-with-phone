import { describe, expect, it } from "vitest";
import { encode, encodeBytes, type Setting } from "../src/encoder";

// design.md §7.2 必須テストベクトル。
// 1件目だけが実機リモコン採取値。2〜4件目は §7.1 の規則から導出したもので、
// encoder が規則どおりであることを確認するが、実機互換性の証明にはしない（段階2a で採取照合）。
const VECTORS: Array<{ name: string; origin: "captured" | "derived"; setting: Setting; expected: string }> = [
  {
    name: "ON / dry / 24℃ / auto / middle",
    origin: "captured",
    setting: { power: true, mode: "dry", temp: 24, fan: "auto", vane: "middle" },
    expected: "23CB260100201008325800000000001000E7",
  },
  {
    name: "ON / cool / 26℃ / auto / auto",
    origin: "derived",
    setting: { power: true, mode: "cool", temp: 26, fan: "auto", vane: "auto" },
    expected: "23CB26010020180A364000000000001000DD",
  },
  {
    name: "OFF / cool / 26℃ / auto / auto",
    origin: "derived",
    setting: { power: false, mode: "cool", temp: 26, fan: "auto", vane: "auto" },
    expected: "23CB26010000180A364000000000001000BD",
  },
  {
    name: "ON / heat / 20℃ / 4 / low",
    origin: "derived",
    setting: { power: true, mode: "heat", temp: 20, fan: "4", vane: "low" },
    expected: "23CB260100200804306400000000001000E5",
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
    const fans = { auto: 0, quiet: 5, "1": 1, "2": 2, "3": 3, "4": 4 } as const;
    const vanes = { auto: 0, highest: 1, high: 2, middle: 3, low: 4, lowest: 5, swing: 7 } as const;
    for (const [fan, fv] of Object.entries(fans)) {
      for (const [vane, vv] of Object.entries(vanes)) {
        const b9 = encodeBytes({ ...base, fan: fan as Setting["fan"], vane: vane as Setting["vane"] })[9]!;
        expect(b9).toBe(0x40 | (vv << 3) | fv);
        expect(b9 & 0x80).toBe(0);
      }
    }
  });

  it("temp 範囲外は RangeError", () => {
    expect(() => encodeBytes({ ...base, temp: 15 })).toThrow(RangeError);
    expect(() => encodeBytes({ ...base, temp: 32 })).toThrow(RangeError);
    expect(() => encodeBytes({ ...base, temp: 26.5 })).toThrow(RangeError);
  });
});
