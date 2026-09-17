// Worker 入口（design.md §5.5）。認証境界とルーティングだけを持つ。
// 段階3: GET /device/ws のみ。/command と /schedule は段階4・7で追加する。

import { bearerMatches } from "./auth";
import { Home, type Env } from "./home";
import { log } from "./log";

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
      return json(404, { error: "not_found" });
    } catch (e) {
      log("server_error", { message: e instanceof Error ? e.message : String(e) });
      return json(500, { error: "server_error" });
    }
  },
} satisfies ExportedHandler<Env>;
