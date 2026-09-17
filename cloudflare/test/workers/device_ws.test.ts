// /device/ws の統合テスト（design.md §5.5、§10）。workers pool 上で Worker と DO を実際に動かす。
import { SELF, env } from "cloudflare:test";
import { describe, expect, it } from "vitest";

const WS_URL = "https://example.com/device/ws";

function upgrade(token?: string): RequestInit {
  const headers: Record<string, string> = { Upgrade: "websocket" };
  if (token !== undefined) headers.Authorization = `Bearer ${token}`;
  return { headers };
}

describe("GET /device/ws", () => {
  it("DEVICE_TOKEN が無ければ 401", async () => {
    const res = await SELF.fetch(WS_URL, upgrade());
    expect(res.status).toBe(401);
    expect(await res.json()).toEqual({ error: "unauthorized" });
  });

  it("DEVICE_TOKEN が違えば 401", async () => {
    const res = await SELF.fetch(WS_URL, upgrade("wrong"));
    expect(res.status).toBe(401);
  });

  it("APP_TOKEN では device に入れない", async () => {
    const res = await SELF.fetch(WS_URL, upgrade(env.APP_TOKEN));
    expect(res.status).toBe(401);
  });

  it("Upgrade ヘッダが無ければ 426", async () => {
    const res = await SELF.fetch(WS_URL, { headers: { Authorization: `Bearer ${env.DEVICE_TOKEN}` } });
    expect(res.status).toBe(426);
  });

  it("正しい DEVICE_TOKEN で 101 と WebSocket", async () => {
    const res = await SELF.fetch(WS_URL, upgrade(env.DEVICE_TOKEN));
    expect(res.status).toBe(101);
    expect(res.webSocket).toBeTruthy();
    res.webSocket!.accept();
    res.webSocket!.close(1000, "test done");
  });

  it("新しい接続が来たら古い接続が閉じられる", async () => {
    const first = await SELF.fetch(WS_URL, upgrade(env.DEVICE_TOKEN));
    const ws1 = first.webSocket!;
    ws1.accept();
    const closed = new Promise<CloseEvent>((resolve) => ws1.addEventListener("close", resolve));

    const second = await SELF.fetch(WS_URL, upgrade(env.DEVICE_TOKEN));
    expect(second.status).toBe(101);
    const ws2 = second.webSocket!;
    ws2.accept();

    const ev = await closed;
    expect(ev.code).toBe(1000);
    expect(ev.reason).toBe("replaced");
    ws2.close(1000, "test done");
  });

  it("他のパスは 404、POST は 405", async () => {
    expect((await SELF.fetch("https://example.com/nope")).status).toBe(404);
    // Upgrade ヘッダ付きだと workerd がメソッドを GET に正規化するため、Upgrade なしの POST で確認する
    const res = await SELF.fetch(WS_URL, { method: "POST", headers: { Authorization: `Bearer ${env.DEVICE_TOKEN}` } });
    expect(res.status).toBe(405);
  });
});
