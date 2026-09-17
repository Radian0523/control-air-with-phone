// Worker 入口（design.md §5.5）。認証境界とルーティングだけを持つ。
// 入口は5つ（§5.5）: GET /device/ws、POST /command、GET/PUT/DELETE /schedule

import { bearerMatches } from "./auth";
import { Home, type Env } from "./home";
import { log } from "./log";
import { validateExecuteAt, validateSetting } from "./validate";

export { Home };

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8" },
  });
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    try {
      if (url.pathname === "/device/ws") {
        if (request.method !== "GET") return json(405, { error: "method_not_allowed" });
        if (!(await bearerMatches(request.headers.get("Authorization"), env.DEVICE_TOKEN))) {
          return json(401, { error: "unauthorized" });
        }
        if (request.headers.get("Upgrade")?.toLowerCase() !== "websocket") {
          return json(426, { error: "upgrade_required" });
        }
        const stub = env.HOME.get(env.HOME.idFromName("home"));
        return stub.fetch(request);
      }
      if (url.pathname === "/command") {
        if (request.method !== "POST") return json(405, { error: "method_not_allowed" });
        if (!(await bearerMatches(request.headers.get("Authorization"), env.APP_TOKEN))) {
          return json(401, { error: "unauthorized" });
        }
        let body: unknown;
        try {
          body = await request.json();
        } catch {
          return json(400, { error: "bad_request" });
        }
        const v = validateSetting(body);
        if (!v.ok) return json(400, { error: "bad_request" });
        const stub = env.HOME.get(env.HOME.idFromName("home"));
        const result = await stub.command(v.value);
        return result.ok ? json(202, { ok: true }) : json(503, { error: result.error });
      }
      if (url.pathname === "/schedule") {
        if (!(await bearerMatches(request.headers.get("Authorization"), env.APP_TOKEN))) {
          return json(401, { error: "unauthorized" });
        }
        const stub = env.HOME.get(env.HOME.idFromName("home"));
        switch (request.method) {
          case "GET":
            return json(200, await stub.getSchedule());
          case "DELETE":
            await stub.deleteSchedule();
            return json(200, { ok: true });
          case "PUT": {
            let body: unknown;
            try {
              body = await request.json();
            } catch {
              return json(400, { error: "bad_request" });
            }
            if (typeof body !== "object" || body === null) return json(400, { error: "bad_request" });
            const { executeAt, setting } = body as { executeAt?: unknown; setting?: unknown };
            const t = validateExecuteAt(executeAt, new Date());
            if (!t.ok) return json(400, { error: "bad_request" });
            const v = validateSetting(setting);
            if (!v.ok) return json(400, { error: "bad_request" });
            return json(200, await stub.putSchedule(v.value, t.value.executeAt, t.value.epochMs));
          }
          default:
            return json(405, { error: "method_not_allowed" });
        }
      }
      return json(404, { error: "not_found" });
    } catch (e) {
      log("server_error", { message: e instanceof Error ? e.message : String(e) });
      return json(500, { error: "server_error" });
    }
  },
} satisfies ExportedHandler<Env>;
