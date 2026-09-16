// 採取した36文字を design.md §7.1 の規則で分解し、必要なら encoder の期待値と照合する。
//
//   node scripts/decode.ts 23CB260100201008325800000000001000E7
//   node scripts/decode.ts 23CB26...  --expect true,dry,24,auto,middle
//
// Node 22 以降の型ストリップで直接実行できる（ビルド不要）。

import { encode, type Fan, type Mode, type Setting, type Vane } from "../src/encoder.ts";

const MODE6: Record<number, Mode> = { 0x20: "auto", 0x18: "cool", 0x10: "dry", 0x08: "heat", 0x38: "fan" };
const FAN: Record<number, Fan> = { 0: "auto", 1: "1", 2: "2", 3: "3" };
const VANE: Record<number, Vane> = { 0: "auto", 1: "highest", 2: "high", 3: "middle", 4: "low", 5: "lowest", 7: "swing" };

function hex(b: number): string {
  return b.toString(16).toUpperCase().padStart(2, "0");
}

function decode(text: string): void {
  if (!/^[0-9A-F]{36}$/.test(text)) {
    console.error("入力は36文字の大文字16進にしてください");
    process.exit(2);
  }
  const b = Array.from({ length: 18 }, (_, i) => parseInt(text.slice(2 * i, 2 * i + 2), 16));
  const sum = b.slice(0, 17).reduce((a, v) => a + v, 0) & 0xff;

  const rows: Array<[string, string, string]> = [
    ["byte 0-4", b.slice(0, 5).map(hex).join(" "), b.slice(0, 5).map(hex).join("") === "23CB260100" ? "固定部 OK" : "固定部と不一致"],
    ["byte 5 power", hex(b[5]!), b[5] === 0x20 ? "ON" : b[5] === 0x00 ? "OFF" : "未知の値"],
    ["byte 6 mode", hex(b[6]!), MODE6[b[6]!] ?? "未知の値"],
    ["byte 7 temp", hex(b[7]!), `${(b[7]! & 0x0f) + 16}℃` + (b[7]! & 0xf0 ? " (上位bitあり: 半度/未知)" : "")],
    ["byte 8", hex(b[8]!), `上位=${b[8]! >> 4} 下位=${b[8]! & 0x0f}` + (b[8]! >> 4 === 3 ? " (水平風向 中央)" : " (水平風向 非中央)")],
    ["byte 9 fan", String(b[9]! & 0x07), FAN[b[9]! & 0x07] ?? "未知の値"],
    ["byte 9 vane", String((b[9]! >> 3) & 0x07), VANE[(b[9]! >> 3) & 0x07] ?? "未知の値"],
    ["byte 9 bit6", String((b[9]! >> 6) & 1), (b[9]! >> 6) & 1 ? "1 (規則どおり)" : "0 (規則と不一致)"],
    ["byte 9 bit7", String((b[9]! >> 7) & 1), (b[9]! >> 7) & 1 ? "1 (FanAuto: 規則は常に0)" : "0 (規則どおり)"],
    ["byte 10-14", b.slice(10, 15).map(hex).join(" "), b.slice(10, 15).every((v) => v === 0) ? "固定部 OK" : "非ゼロあり: 時計/タイマーを疑う"],
    ["byte 15-16", b.slice(15, 17).map(hex).join(" "), b[15] === 0x10 && b[16] === 0x00 ? "固定部 OK" : "固定部と不一致"],
    ["byte 17 checksum", hex(b[17]!), b[17] === sum ? "OK" : `不一致 (計算値 ${hex(sum)})`],
  ];
  for (const [k, v, note] of rows) console.log(`${k.padEnd(18)} ${v.padEnd(16)} ${note}`);

  const mode = MODE6[b[6]!];
  const fan = FAN[b[9]! & 0x07];
  const vane = VANE[(b[9]! >> 3) & 0x07];
  if (mode && fan && vane && (b[5] === 0x20 || b[5] === 0x00)) {
    const s: Setting = { power: b[5] === 0x20, mode, temp: (b[7]! & 0x0f) + 16, fan, vane };
    const re = encode(s);
    console.log("");
    console.log(`解釈した設定        ${JSON.stringify(s)}`);
    console.log(`encoder の出力      ${re}`);
    console.log(`採取値              ${text}`);
    console.log(re === text ? "一致: encoder はこの採取値を再現できる" : "不一致: 差分のバイトを上の表で確認し、規則の修正を検討する");
  } else {
    console.log("\n規則で解釈できないフィールドがあるため、encoder との照合は省略");
  }
}

function expectFrom(arg: string): void {
  const [power, mode, temp, fan, vane] = arg.split(",");
  const s = { power: power === "true", mode, temp: Number(temp), fan, vane } as Setting;
  console.log(`\n--expect ${JSON.stringify(s)}`);
  console.log(`encoder の期待値    ${encode(s)}`);
}

const [, , text, flag, expectArg] = process.argv;
if (!text) {
  console.error("usage: node scripts/decode.ts <36文字> [--expect power,mode,temp,fan,vane]");
  process.exit(2);
}
decode(text);
if (flag === "--expect" && expectArg) expectFrom(expectArg);
