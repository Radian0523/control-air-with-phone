// Durable Object "home"（design.md §5.1、§5.2、ADR-018）。
// ESP32 の device WebSocket を最大1本、Hibernation API で保持する。
// device WebSocket の受け入れと置換、即時操作、一発予約（1件）と Alarm を持つ。

import { DurableObject } from "cloudflare:workers";
import { encode, type Setting } from "./encoder";
import { log } from "./log";

export interface Env {
  HOME: DurableObjectNamespace<Home>;
  DEVICE_TOKEN: string;
  APP_TOKEN: string;
}

const DEVICE_TAG = "device";
const SCHEDULE_KEY = "schedule";

/** 永続化する業務データ。予約1件だけ（§5.2） */
interface ScheduleRecord {
  executeAt: string; // UTC 正規形
  setting: Setting;
  payload: string; // 受付時に生成した36文字。後日のコード変更で予約内容が変わらないため
}

/** API が返す形。payload は返さない（§5.5） */
export interface ScheduleView {
  executeAt: string;
  setting: Setting;
}

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

  /** 接続中の device socket を返す。なければ null */
  private deviceSocket(): WebSocket | null {
    const sockets = this.ctx.getWebSockets(DEVICE_TAG);
    return sockets[0] ?? null;
  }

  /**
   * 36文字を device socket へ1回だけ送る（§5.5）。
   * 接続なし、閉じている、send() が同期的に例外 → false（503 相当）。送信できたら true（202 相当）。
   * 設計どおり、ESP32 の処理完了やエアコンの受理は確認しない。
   */
  private sendToDevice(payload: string): boolean {
    const ws = this.deviceSocket();
    if (!ws) return false;
    try {
      ws.send(payload);
      return true;
    } catch {
      return false;
    }
  }

  // ---- 一発予約（§5.2、ADR-011）------------------------------------------------

  /** GET /schedule。予約1件または null */
  async getSchedule(): Promise<ScheduleView | null> {
    const rec = await this.ctx.storage.get<ScheduleRecord>(SCHEDULE_KEY);
    return rec ? { executeAt: rec.executeAt, setting: rec.setting } : null;
  }

  /** PUT /schedule。新しい予約は古い予約を置き換える。Alarm も置き換わる */
  async putSchedule(setting: Setting, executeAt: string, epochMs: number): Promise<ScheduleView> {
    const rec: ScheduleRecord = { executeAt, setting, payload: encode(setting) };
    await this.ctx.storage.put(SCHEDULE_KEY, rec);
    await this.ctx.storage.setAlarm(epochMs);
    log("schedule_set", { executeAt });
    return { executeAt, setting };
  }

  /** DELETE /schedule。レコードと Alarm を削除する */
  async deleteSchedule(): Promise<void> {
    await this.ctx.storage.delete(SCHEDULE_KEY);
    await this.ctx.storage.deleteAlarm();
    log("schedule_deleted");
  }

  /**
   * Alarm handler。順序は §5.2 に固定する。
   *   読む → なければ終了 → 削除して完了を待つ → 接続中なら1回 send → 失敗は記録して正常終了
   * 読み込み・削除で失敗した場合はまだ送っていないので、例外をそのまま投げて Alarm の再試行に任せる。
   * 削除が完了した後は何があっても例外を投げない（再試行で二重送信しないため、ADR-005）。
   */
  override async alarm(): Promise<void> {
    const rec = await this.ctx.storage.get<ScheduleRecord>(SCHEDULE_KEY);
    if (!rec) return;
    await this.ctx.storage.delete(SCHEDULE_KEY);

    try {
      if (this.sendToDevice(rec.payload)) {
        log("schedule_fired_sent", { executeAt: rec.executeAt });
      } else {
        log("schedule_fired_offline", { executeAt: rec.executeAt });
      }
    } catch (e) {
      log("server_error", { where: "alarm", message: e instanceof Error ? e.message : String(e) });
    }
  }

  /** POST /command（§5.5）。検証済みの設定を受け取り、encode して送る。RPC で Worker から呼ばれる */
  async command(setting: Setting): Promise<{ ok: true } | { ok: false; error: "device_offline" }> {
    const payload = encode(setting);
    if (this.sendToDevice(payload)) {
      log("command_sent");
      return { ok: true };
    }
    log("command_offline");
    return { ok: false, error: "device_offline" };
  }
}
