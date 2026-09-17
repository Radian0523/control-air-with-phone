// cloudflare:test の `env` は `Cloudflare.Env` 型。アプリの Env で拡張する
import type { Env as AppEnv } from "../../src/home";

declare global {
  namespace Cloudflare {
    interface Env extends AppEnv {}
  }
}

export {};
