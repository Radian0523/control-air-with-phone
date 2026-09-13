// エアコン設定（design.md §5.4）と executeAt（§5.2）の検証。純粋関数。
// 現在時刻は引数で受け取り、テストで固定できるようにする。

import { TEMP_MAX, TEMP_MIN, type Fan, type Mode, type Setting, type Vane } from "./encoder";

export type Result<T> = { ok: true; value: T } | { ok: false; error: string };

const MODES: readonly Mode[] = ["auto", "cool", "dry", "heat", "fan"];
const FANS: readonly Fan[] = ["auto", "quiet", "1", "2", "3", "4"];
const VANES: readonly Vane[] = ["auto", "highest", "high", "middle", "low", "lowest", "swing"];

function isRecord(v: unknown): v is Record<string, unknown> {
  return typeof v === "object" && v !== null && !Array.isArray(v);
}

function oneOf<T extends string>(v: unknown, allowed: readonly T[]): v is T {
  return typeof v === "string" && (allowed as readonly string[]).includes(v);
}

/**
 * §5.4: 必須項目、型、範囲、列挙値を検査する。未知フィールドは無視し、
 * 5項目だけを持つ正規化済み Setting を返す。
 */
export function validateSetting(input: unknown): Result<Setting> {
  if (!isRecord(input)) return { ok: false, error: "setting must be an object" };

  const { power, mode, temp, fan, vane } = input;

  if (typeof power !== "boolean") return { ok: false, error: "power must be boolean" };
  if (!oneOf(mode, MODES)) return { ok: false, error: "mode must be one of " + MODES.join("/") };
  if (typeof temp !== "number" || !Number.isInteger(temp) || temp < TEMP_MIN || temp > TEMP_MAX) {
    return { ok: false, error: `temp must be an integer ${TEMP_MIN}..${TEMP_MAX}` };
  }
  if (!oneOf(fan, FANS)) return { ok: false, error: "fan must be one of " + FANS.join("/") };
  if (!oneOf(vane, VANES)) return { ok: false, error: "vane must be one of " + VANES.join("/") };

  return { ok: true, value: { power, mode, temp, fan, vane } };
}

// §5.2: UTC の正規形だけを受理する。小数秒、オフセット表記、小文字の z は不可
const EXECUTE_AT_RE = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/;

/**
 * §5.2: 形式一致 → パース → UTC 成分の一致確認 → 現在より未来であることを確認する。
 * 成功時は正規形の文字列と epoch ミリ秒を返す。未来側の独自上限は設けない（ADR-011）。
 */
export function validateExecuteAt(input: unknown, now: Date): Result<{ executeAt: string; epochMs: number }> {
  if (typeof input !== "string") return { ok: false, error: "executeAt must be a string" };
  if (!EXECUTE_AT_RE.test(input)) return { ok: false, error: "executeAt must be YYYY-MM-DDTHH:mm:ssZ" };

  const epochMs = Date.parse(input);
  if (Number.isNaN(epochMs)) return { ok: false, error: "executeAt is not a valid date-time" };

  // 2月30日や 24:00:00 のように Date.parse が丸めて受理するものを弾く
  const roundTrip = new Date(epochMs).toISOString().replace(".000Z", "Z");
  if (roundTrip !== input) return { ok: false, error: "executeAt is not a real date-time" };

  if (epochMs <= now.getTime()) return { ok: false, error: "executeAt must be in the future" };

  return { ok: true, value: { executeAt: input, epochMs } };
}
