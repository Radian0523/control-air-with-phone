// Durable Object "home"（design.md §5.1、§5.2、ADR-018）。
// ESP32 の device WebSocket を最大1本、Hibernation API で保持する。
// 段階3: device WebSocket の受け入れと置換だけ。/command と予約は段階4・7で追加する。

import { DurableObject } from "cloudflare:workers";
import { log } from "./log";

export interface Env {
  HOME: DurableObjectNamespace<Home>;
  DEVICE_TOKEN: string;
  APP_TOKEN: string;
}

const DEVICE_TAG = "device";

export class Home extends DurableObject<Env> {
  /**
   * Worker から転送された、認証済みの WebSocket upgrade リクエストを受け入れる。
   * 新しい接続が来たら古い接続を閉じ、新しい接続だけを正とする。
   */
  override async fetch(request: Request): Promise<Response> {
    if (request.headers.get("Upgrade")?.toLowerCase() !== "websocket") {
      return new Response("expected websocket", { status: 426 });
    }

    for (const old of this.ctx.getWebSockets(DEVICE_TAG)) {
      try {
        old.close(1000, "replaced");
      } catch {
        // すでに閉じている場合は無視
      }
    }

    const pair = new WebSocketPair();
    const [client, server] = Object.values(pair) as [WebSocket, WebSocket];
    this.ctx.acceptWebSocket(server, [DEVICE_TAG]);
    log("device_connected");

    return new Response(null, { status: 101, webSocket: client });
  }

  /** ESP32 からアプリ用メッセージは来ない（ADR-010）。業務処理を置かない */
  override async webSocketMessage(_ws: WebSocket, _message: string | ArrayBuffer): Promise<void> {}

  override async webSocketClose(ws: WebSocket, code: number, _reason: string, wasClean: boolean): Promise<void> {
    log("device_disconnected", { code, wasClean });
    try {
      ws.close(code, "closed");
    } catch {
      // 相手側が先に閉じた場合は無視
    }
  }

  override async webSocketError(_ws: WebSocket, _error: unknown): Promise<void> {
    log("device_disconnected", { error: true });
  }

  /** 接続中の device socket を返す。なければ null。段階4以降で使う */
  deviceSocket(): WebSocket | null {
    const sockets = this.ctx.getWebSockets(DEVICE_TAG);
    return sockets[0] ?? null;
  }
}
