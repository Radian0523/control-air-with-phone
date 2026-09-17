// Bearer token の照合（design.md §5.3、ADR-013）。
// 入力値と secret をそれぞれ SHA-256 にし、同じ長さの digest 同士を timingSafeEqual で比較する。

const encoder = new TextEncoder();

async function sha256(text: string): Promise<ArrayBuffer> {
  return crypto.subtle.digest("SHA-256", encoder.encode(text));
}

/** "Bearer <token>" 形式の Authorization ヘッダから token を取り出す。形式外は null */
export function extractBearer(header: string | null): string | null {
  if (!header) return null;
  const m = /^Bearer\s+(\S+)$/.exec(header.trim());
  return m ? m[1]! : null;
}

/** Authorization ヘッダが secret と一致するか。secret が未設定なら常に false */
export async function bearerMatches(header: string | null, secret: string | undefined): Promise<boolean> {
  if (!secret) return false;
  const token = extractBearer(header);
  if (token === null) return false;
  const [a, b] = await Promise.all([sha256(token), sha256(secret)]);
  return crypto.subtle.timingSafeEqual(a, b);
}
