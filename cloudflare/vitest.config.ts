import { defineConfig } from "vitest/config";

// 段階1: 純粋関数のテストだけなので Node 環境で走らせる。
// Durable Object を含むテスト（段階3以降）は @cloudflare/vitest-pool-workers へ移す。
export default defineConfig({
  test: {
    include: ["test/**/*.test.ts"],
  },
});
