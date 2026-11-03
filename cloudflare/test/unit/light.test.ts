import { describe, expect, it } from "vitest";
import { encodeLight, LIGHT_BUTTONS } from "../../src/light";
import { validateLight } from "../../src/validate";

describe("encodeLight: 採取したコード（docs/ir-captures.md）", () => {
  it("4ボタンが採取値どおりの8文字になる", () => {
    expect(encodeLight("on")).toBe("01A359A6");
    expect(encodeLight("off")).toBe("01A310EF");
    expect(encodeLight("eco")).toBe("01A3748B");
    expect(encodeLight("mame")).toBe("01A354AB");
  });

  it("すべて8文字の大文字16進で、NEC のコマンドと反転が XOR で 0xFF になる", () => {
    for (const b of LIGHT_BUTTONS) {
      const s = encodeLight(b);
      expect(s).toMatch(/^[0-9A-F]{8}$/);
      const cmd = parseInt(s.slice(4, 6), 16);
      const inv = parseInt(s.slice(6, 8), 16);
      expect(cmd ^ inv).toBe(0xff);
    }
  });
});

describe("validateLight: §5.5", () => {
  it("4ボタンを受理し、未知フィールドは無視する", () => {
    for (const b of LIGHT_BUTTONS) expect(validateLight({ button: b })).toEqual({ ok: true, value: b });
    expect(validateLight({ button: "on", extra: 1 })).toEqual({ ok: true, value: "on" });
  });

  it("未知のボタン、大文字、型違い、欠落、object 以外は不可", () => {
    expect(validateLight({ button: "dim" }).ok).toBe(false);
    expect(validateLight({ button: "ON" }).ok).toBe(false);
    expect(validateLight({ button: 1 }).ok).toBe(false);
    expect(validateLight({}).ok).toBe(false);
    expect(validateLight(null).ok).toBe(false);
    expect(validateLight(["on"]).ok).toBe(false);
    expect(validateLight("on").ok).toBe(false);
  });
});
