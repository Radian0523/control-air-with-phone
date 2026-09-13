# control-air-with-phone

iPhone から三菱電機エアコンを赤外線で操作する個人プロジェクト。iPhone → Cloudflare Worker / Durable Object → ESP32 → 赤外線。

| 場所 | 内容 |
|---|---|
| [docs/design.md](docs/design.md) | 現行仕様 |
| [docs/adr.md](docs/adr.md) | 設計判断 |
| [docs/implementation-plan.md](docs/implementation-plan.md) | 実装計画と進行表 |
| [docs/circuit/](docs/circuit/) | 赤外線送信回路図（CircuiTikZ） |
| `cloudflare/` | Worker と Durable Object |
| `firmware/` | ESP32 ファームと試験スケッチ |
| `ios/` | SwiftUI アプリ |
| `tools/` | 赤外線の解析用スケッチ |
