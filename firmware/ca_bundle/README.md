# CA bundle

design.md §4.6 の手順で生成する。生成のたびに下の表へ追記する。

| 取得日 (UTC) | cacert.pem SHA-256 | Mozilla データ日付 | gen_crt_bundle.py の core 版 | 生成物サイズ (byte) | 証明書数 |
|---|---|---|---|---|---|
| 2026-09-17 | `f66dff1bdf8f96060b8177976f8b7d9254bc89bc4db933d769f7384d28480bc9`（curl.se 配布の .sha256 と一致） | 2026-08-13 | 3.3.11 | 55,587 | 121 |

手順:

1. `curl -fsSLO https://curl.se/ca/cacert.pem && shasum -a 256 cacert.pem`
2. `python3 ~/Library/Arduino15/packages/esp32/hardware/esp32/3.3.11/tools/gen_crt_bundle.py --input cacert.pem`（`--filter` は指定しない）
3. `xxd -i x509_crt_bundle` の出力を、配列名 `ca_bundle` / 長さ `ca_bundle_len`、いずれも `const` に書き換えて `../aircon_bridge/ca_bundle.h` に保存する

   ```bash
   xxd -i x509_crt_bundle | sed 's/^unsigned char x509_crt_bundle\[\]/const unsigned char ca_bundle[]/; s/^unsigned int x509_crt_bundle_len/const unsigned int ca_bundle_len/' > ../aircon_bridge/ca_bundle.h
   ```
4. `cacert.pem` と `x509_crt_bundle` はこのディレクトリへ置き、コミットする（秘密情報ではない）
