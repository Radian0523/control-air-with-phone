# cloudflare

Worker 入口と Durable Object "home" を1プロジェクトに置く（design.md §5、ADR-007）。

```text
src/index.ts     Worker 入口。認証、ルーティング
src/home.ts      Durable Object。WebSocket、予約、Alarm
src/encoder.ts   encode(setting) -> 36文字。純粋関数
src/validate.ts  エアコン設定と executeAt の検証。純粋関数
src/auth.ts      SHA-256 + timingSafeEqual
test/            vitest
```

secret は `wrangler secret put DEVICE_TOKEN` / `wrangler secret put APP_TOKEN` で登録する。リポジトリには置かない。

## デプロイ先

- URL: `https://aircon.aircon-worker.workers.dev`（2026-09-17 初回デプロイ）
- デプロイ: `npm run deploy`
- ログ: `npx wrangler tail --format pretty`

secret の登録（値は `openssl rand -hex 32` などで生成し、DEVICE_TOKEN は ESP32 の secrets.h と同じ値にする）:

```bash
npx wrangler secret put DEVICE_TOKEN
npx wrangler secret put APP_TOKEN
```
