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
