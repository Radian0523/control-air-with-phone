// /schedule と Alarm の統合テスト（design.md §5.2、§5.5、§10）
import { SELF, env, runDurableObjectAlarm, runInDurableObject } from "cloudflare:test";
import { beforeEach, describe, expect, it } from "vitest";

const URL_ = "https://example.com/schedule";
const WS_URL = "https://example.com/device/ws";
const good = { power: true, mode: "cool", temp: 26, fan: "auto", vane: "middle" };
const EXPECTED_PAYLOAD = "23CB26010020180A365800000000001000F5";

function futureIso(seconds: number): string {
  return new Date(Date.now() + seconds * 1000).toISOString().replace(/\.\d{3}Z$/, "Z");
}

function auth(token: string = env.APP_TOKEN): Record<string, string> {
  return { Authorization: `Bearer ${token}`, "content-type": "application/json" };
}

async function put(body: unknown): Promise<Response> {
  return SELF.fetch(URL_, { method: "PUT", headers: auth(), body: JSON.stringify(body) });
}

async function get(): Promise<Response> {
  return SELF.fetch(URL_, { headers: auth() });
}

async function del(): Promise<Response> {
  return SELF.fetch(URL_, { method: "DELETE", headers: auth() });
}

function stub() {
  return env.HOME.get(env.HOME.idFromName("home"));
}

async function connectDevice(): Promise<WebSocket> {
  const res = await SELF.fetch(WS_URL, { headers: { Upgrade: "websocket", Authorization: `Bearer ${env.DEVICE_TOKEN}` } });
  const ws = res.webSocket!;
  ws.accept();
  return ws;
}

describe("/schedule", () => {
  beforeEach(async () => {
    await del();
  });

  it("APP_TOKEN が無ければ全メソッド 401", async () => {
    for (const method of ["GET", "PUT", "DELETE"]) {
      const res = await SELF.fetch(URL_, { method, headers: { "content-type": "application/json" }, body: method === "PUT" ? "{}" : undefined });
      expect(res.status, method).toBe(401);
    }
  });

  it("予約がなければ GET は 200 null", async () => {
    const res = await get();
    expect(res.status).toBe(200);
    expect(await res.json()).toBeNull();
  });

  it("PUT は予約を作り、GET は payload を含まない形で返す", async () => {
    const executeAt = futureIso(3600);
    const res = await put({ executeAt, setting: good });
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ executeAt, setting: good });

    const shown = await (await get()).json();
    expect(shown).toEqual({ executeAt, setting: good });
    expect(JSON.stringify(shown)).not.toContain(EXPECTED_PAYLOAD);
  });

  it("不正な executeAt は 400 で、予約も Alarm も変わらない", async () => {
    const executeAt = futureIso(3600);
    await put({ executeAt, setting: good });

    for (const bad of ["2020-01-01T00:00:00Z", futureIso(3600).replace("Z", ".000Z"), "2027-02-30T10:00:00Z", futureIso(3600).replace("Z", "+09:00"), 123, undefined]) {
      const res = await put({ executeAt: bad, setting: good });
      expect(res.status, String(bad)).toBe(400);
    }
    expect((await put({ executeAt: futureIso(60), setting: { ...good, temp: 99 } })).status).toBe(400);
    expect((await SELF.fetch(URL_, { method: "PUT", headers: auth(), body: "{oops" })).status).toBe(400);

    expect(await (await get()).json()).toEqual({ executeAt, setting: good });
  });

  it("新しい予約は古い予約を置き換える", async () => {
    const a = futureIso(3600);
    const b = futureIso(7200);
    await put({ executeAt: a, setting: good });
    await put({ executeAt: b, setting: { ...good, temp: 20 } });
    expect(await (await get()).json()).toEqual({ executeAt: b, setting: { ...good, temp: 20 } });
  });

  it("DELETE は予約と Alarm を消し、Alarm は発火しない", async () => {
    await put({ executeAt: futureIso(3600), setting: good });
    expect((await del()).status).toBe(200);
    expect(await (await get()).json()).toBeNull();
    expect(await runDurableObjectAlarm(stub())).toBe(false);
  });

  it("device 接続中に発火すると payload を1回送り、予約は消える。再発火しても二重送信しない", async () => {
    const ws = await connectDevice();
    const received: string[] = [];
    ws.addEventListener("message", (ev) => received.push(String(ev.data)));

    await put({ executeAt: futureIso(3600), setting: good });
    expect(await runDurableObjectAlarm(stub())).toBe(true);
    await new Promise((r) => setTimeout(r, 50));

    expect(received).toEqual([EXPECTED_PAYLOAD]);
    expect(await (await get()).json()).toBeNull();

    // Alarm が（再試行などで）もう一度呼ばれても、予約が無いので何も送らない
    expect(await runDurableObjectAlarm(stub())).toBe(false);
    await runInDurableObject(stub(), (instance) => instance.alarm());
    await new Promise((r) => setTimeout(r, 50));
    expect(received).toEqual([EXPECTED_PAYLOAD]);
    ws.close(1000, "done");
  });

  it("device 未接続で発火すると予約は消え、例外にならない", async () => {
    await put({ executeAt: futureIso(3600), setting: good });
    await expect(runDurableObjectAlarm(stub())).resolves.toBe(true);
    expect(await (await get()).json()).toBeNull();
  });

  it("PATCH は 405", async () => {
    expect((await SELF.fetch(URL_, { method: "PATCH", headers: auth() })).status).toBe(405);
  });
});
