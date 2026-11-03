// POST /light の統合テスト（design.md §5.5、ADR-022）
import { SELF, env } from "cloudflare:test";
import { describe, expect, it } from "vitest";

const LIGHT_URL = "https://example.com/light";
const WS_URL = "https://example.com/device/ws";

// token: 省略で APP_TOKEN、null で Authorization ヘッダなし
function post(body: unknown, token: string | null = env.APP_TOKEN, raw = false): Promise<Response> {
  const headers: Record<string, string> = { "content-type": "application/json" };
  if (token !== null) headers.Authorization = `Bearer ${token}`;
  return SELF.fetch(LIGHT_URL, { method: "POST", headers, body: raw ? (body as string) : JSON.stringify(body) });
}

async function connectDevice(): Promise<WebSocket> {
  const res = await SELF.fetch(WS_URL, { headers: { Upgrade: "websocket", Authorization: `Bearer ${env.DEVICE_TOKEN}` } });
  expect(res.status).toBe(101);
  const ws = res.webSocket!;
  ws.accept();
  return ws;
}

describe("POST /light", () => {
  it("APP_TOKEN が無い・違う・DEVICE_TOKEN では 401", async () => {
    expect((await post({ button: "on" }, null)).status).toBe(401);
    expect((await post({ button: "on" }, "wrong")).status).toBe(401);
    expect((await post({ button: "on" }, env.DEVICE_TOKEN)).status).toBe(401);
  });

  it("未知のボタンと壊れた JSON は 400", async () => {
    expect((await post({ button: "dim" })).status).toBe(400);
    expect((await post({})).status).toBe(400);
    expect((await post("{not json", env.APP_TOKEN, true)).status).toBe(400);
  });

  it("GET は 405", async () => {
    expect((await SELF.fetch(LIGHT_URL, { headers: { Authorization: `Bearer ${env.APP_TOKEN}` } })).status).toBe(405);
  });

  it("device が接続していれば 202 と8文字が届く。切断後は 503", async () => {
    const ws = await connectDevice();
    const received = new Promise<string>((resolve) => ws.addEventListener("message", (ev) => resolve(String(ev.data))));

    const res = await post({ button: "mame" });
    expect(res.status).toBe(202);
    expect(await res.json()).toEqual({ ok: true });
    expect(await received).toBe("01A354AB");

    ws.close(1000, "test done");
    // close が DO 側へ伝わるのを待つ
    await new Promise((r) => setTimeout(r, 100));
    const offline = await post({ button: "off" });
    expect(offline.status).toBe(503);
    expect(await offline.json()).toEqual({ error: "device_offline" });
  });
});
