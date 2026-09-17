import { describe, expect, it } from "vitest";
import { bearerMatches, extractBearer } from "../../src/auth";

describe("extractBearer", () => {
  it("Bearer 形式だけを受理する", () => {
    expect(extractBearer("Bearer abc")).toBe("abc");
    expect(extractBearer("  Bearer abc  ")).toBe("abc");
    expect(extractBearer("bearer abc")).toBeNull(); // 大文字小文字は区別
    expect(extractBearer("Basic abc")).toBeNull();
    expect(extractBearer("Bearer")).toBeNull();
    expect(extractBearer("Bearer a b")).toBeNull();
    expect(extractBearer(null)).toBeNull();
    expect(extractBearer("")).toBeNull();
  });
});

describe("bearerMatches", () => {
  it("一致すれば true、不一致・欠落・secret 未設定は false", async () => {
    expect(await bearerMatches("Bearer s3cret", "s3cret")).toBe(true);
    expect(await bearerMatches("Bearer s3cret", "other")).toBe(false);
    expect(await bearerMatches("Bearer s3cre", "s3cret")).toBe(false);
    expect(await bearerMatches(null, "s3cret")).toBe(false);
    expect(await bearerMatches("Bearer s3cret", undefined)).toBe(false);
    expect(await bearerMatches("Bearer s3cret", "")).toBe(false);
  });
});
