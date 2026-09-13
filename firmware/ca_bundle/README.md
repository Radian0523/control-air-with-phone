# CA bundle

design.md §4.6 の手順で生成する。生成のたびに下の表へ追記する。

| 取得日 (UTC) | cacert.pem SHA-256 | gen_crt_bundle.py の core 版 | 生成物サイズ (byte) |
|---|---|---|---|
| | | | |

手順:

1. `curl -fsSLO https://curl.se/ca/cacert.pem && shasum -a 256 cacert.pem`
2. `python3 ~/Library/Arduino15/packages/esp32/hardware/esp32/3.3.11/tools/gen_crt_bundle.py --input cacert.pem`（`--filter` は指定しない）
3. `xxd -i x509_crt_bundle > ../aircon_bridge/ca_bundle.h` し、配列に `const` を付ける
4. `cacert.pem` と `x509_crt_bundle` はこのディレクトリへ置き、コミットする（秘密情報ではない）
