import { cloudflareTest } from "@cloudflare/vitest-pool-workers";
import { defineConfig } from "vitest/config";

// unit:    純粋関数（encoder / validate / auth）。Node 環境
// workers: Worker と Durable Object の統合テスト。workerd 上で wrangler.toml の構成を使う
export default defineConfig({
  test: {
    projects: [
      {
        test: {
          name: "unit",
          include: ["test/unit/**/*.test.ts"],
        },
      },
      {
        plugins: [
          cloudflareTest({
            wrangler: { configPath: "./wrangler.toml" },
            // 試験用 secret。本番は wrangler secret put で登録する
            miniflare: {
              bindings: { DEVICE_TOKEN: "test-device-token", APP_TOKEN: "test-app-token" },
            },
          }),
        ],
        test: {
          name: "workers",
          include: ["test/workers/**/*.test.ts"],
        },
      },
    ],
  },
});
