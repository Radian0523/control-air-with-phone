// Worker 入口（design.md §5.5）。認証境界とルーティングだけを持つ。
// 段階4: GET /device/ws と POST /command。/schedule は段階7で追加する。

import { bearerMatches } from "./auth";
import { Home, type Env } from "./home";
import { log } from "./log";
import { validateSetting } from "./validate";

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
      return json(404, { error: "not_found" });
    } catch (e) {
      log("server_error", { message: e instanceof Error ? e.message : String(e) });
      return json(500, { error: "server_error" });
    }
  },
} satisfies ExportedHandler<Env>;
