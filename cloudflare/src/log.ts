// 運用ログ（design.md §5.6）。各行を JSON にし、time と event だけを必須にする。
// Bearer token、36文字 payload、エアコン設定は絶対に渡さない。

export type LogEvent =
  | "device_connected"
  | "device_disconnected"
  | "command_sent"
  | "command_offline"
  | "schedule_set"
  | "schedule_deleted"
  | "schedule_fired_sent"
  | "schedule_fired_offline"
  | "server_error";

export function log(event: LogEvent, extra: Record<string, string | number | boolean> = {}): void {
  console.log(JSON.stringify({ time: new Date().toISOString(), event, ...extra }));
}
