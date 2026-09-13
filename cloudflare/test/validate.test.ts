import { describe, expect, it } from "vitest";
import { validateExecuteAt, validateSetting } from "../src/validate";

const good = { power: true, mode: "cool", temp: 26, fan: "auto", vane: "auto" };

describe("validateSetting: §5.4", () => {
  it("正常値を受理し、5項目だけを返す", () => {
    const r = validateSetting({ ...good, extra: "ignored", nested: { a: 1 } });
    expect(r).toEqual({ ok: true, value: good });
  });

  it("電源OFFでも temp は必須", () => {
    expect(validateSetting({ ...good, power: false }).ok).toBe(true);
    const { temp: _t, ...noTemp } = { ...good, power: false };
    expect(validateSetting(noTemp).ok).toBe(false);
  });

  it("temp の境界: 16 と 31 は可、15 と 32 は不可、小数と文字列は不可", () => {
    expect(validateSetting({ ...good, temp: 16 }).ok).toBe(true);
    expect(validateSetting({ ...good, temp: 31 }).ok).toBe(true);
    expect(validateSetting({ ...good, temp: 15 }).ok).toBe(false);
    expect(validateSetting({ ...good, temp: 32 }).ok).toBe(false);
    expect(validateSetting({ ...good, temp: 26.5 }).ok).toBe(false);
    expect(validateSetting({ ...good, temp: "26" }).ok).toBe(false);
  });

  it("power は boolean のみ", () => {
    expect(validateSetting({ ...good, power: "true" }).ok).toBe(false);
    expect(validateSetting({ ...good, power: 1 }).ok).toBe(false);
  });

  it("mode / fan / vane の列挙値", () => {
    for (const mode of ["auto", "cool", "dry", "heat", "fan"]) expect(validateSetting({ ...good, mode }).ok).toBe(true);
    expect(validateSetting({ ...good, mode: "Cool" }).ok).toBe(false);
    expect(validateSetting({ ...good, mode: "off" }).ok).toBe(false);

    for (const fan of ["auto", "quiet", "1", "2", "3", "4"]) expect(validateSetting({ ...good, fan }).ok).toBe(true);
    expect(validateSetting({ ...good, fan: 1 }).ok).toBe(false); // 数値ではなく文字列 "1"
    expect(validateSetting({ ...good, fan: "5" }).ok).toBe(false);

    for (const vane of ["auto", "highest", "high", "middle", "low", "lowest", "swing"]) {
      expect(validateSetting({ ...good, vane }).ok).toBe(true);
    }
    expect(validateSetting({ ...good, vane: "up" }).ok).toBe(false);
  });

  it("欠落・型違い・非オブジェクト", () => {
    expect(validateSetting(null).ok).toBe(false);
    expect(validateSetting([]).ok).toBe(false);
    expect(validateSetting("{}").ok).toBe(false);
    expect(validateSetting({}).ok).toBe(false);
    const { mode: _m, ...noMode } = good;
    expect(validateSetting(noMode).ok).toBe(false);
  });
});

describe("validateExecuteAt: §5.2", () => {
  const now = new Date("2026-09-13T12:00:00Z");

  it("正規形で未来なら受理", () => {
    const r = validateExecuteAt("2026-09-13T18:00:00Z", now);
    expect(r).toEqual({ ok: true, value: { executeAt: "2026-09-13T18:00:00Z", epochMs: Date.parse("2026-09-13T18:00:00Z") } });
  });

  it("現在と同時刻、過去は拒否", () => {
    expect(validateExecuteAt("2026-09-13T12:00:00Z", now).ok).toBe(false);
    expect(validateExecuteAt("2026-09-13T11:59:59Z", now).ok).toBe(false);
    expect(validateExecuteAt("2026-09-13T12:00:01Z", now).ok).toBe(true);
  });

  it("小数秒、オフセット、小文字 z、空白、日付のみは拒否", () => {
    for (const s of [
      "2026-09-13T18:00:00.000Z",
      "2026-09-13T18:00:00+09:00",
      "2026-09-13T18:00:00",
      "2026-09-13T18:00:00z",
      "2026-09-13 18:00:00Z",
      "2026-09-13",
      " 2026-09-13T18:00:00Z",
    ]) {
      expect(validateExecuteAt(s, now).ok).toBe(false);
    }
  });

  it("存在しない日時は拒否（2月30日、24時、60秒、13月）", () => {
    for (const s of ["2027-02-30T10:00:00Z", "2026-12-01T24:00:00Z", "2026-12-01T10:00:60Z", "2026-13-01T10:00:00Z"]) {
      expect(validateExecuteAt(s, now).ok).toBe(false);
    }
  });

  it("うるう年は正しく判定", () => {
    expect(validateExecuteAt("2028-02-29T10:00:00Z", now).ok).toBe(true);
    expect(validateExecuteAt("2027-02-29T10:00:00Z", now).ok).toBe(false);
  });

  it("文字列以外は拒否", () => {
    expect(validateExecuteAt(Date.parse("2026-09-13T18:00:00Z"), now).ok).toBe(false);
    expect(validateExecuteAt(null, now).ok).toBe(false);
    expect(validateExecuteAt(undefined, now).ok).toBe(false);
  });

  it("未来側の上限は設けない", () => {
    expect(validateExecuteAt("2099-01-01T00:00:00Z", now).ok).toBe(true);
  });
});
