#!/bin/bash
#
# nsx-tls11-config_v3-local.sh
# 在「NSX Manager 本機」執行 (SSH 進 Manager -> 'st en' 進 root shell 後跑)。
# 直接打 localhost API (/api/v1/cluster/api-service) 查詢 / 開啟 / 關閉 TLS v1.1。
#
# 依據 Broadcom KB 324163 (TLS v1.1 disabled by default from NSX 4.1.1)
# 需求：curl + python3 (NSX Manager appliance 內建)
#
set -eu

# ---- 設定 ----
HOST="${HOST:-127.0.0.1}"               # 本機，預設 localhost
NSX_USER="${NSX_USER:-admin}"
NSX_PASS="${NSX_PASS:-}"                # 不填會互動詢問
API_PATH="/api/v1/cluster/api-service"
BASE="https://${HOST}${API_PATH}"

usage() {
  cat <<EOF
在 NSX Manager 本機執行。用法：
  $0 get                顯示 API 原始 JSON
  $0 status             顯示各 TLS 版本啟用狀態
  $0 enable-tls11       開啟 TLS v1.1
  $0 disable-tls11      關閉 TLS v1.1

環境變數：NSX_USER(預設admin) NSX_PASS(不填會詢問) HOST(預設127.0.0.1)

範例：
  $0 status
  NSX_PASS='xxx' $0 enable-tls11
EOF
}

die() { echo "錯誤：$*" >&2; exit 1; }

command -v curl    >/dev/null 2>&1 || die "找不到 curl"
command -v python3 >/dev/null 2>&1 || die "找不到 python3"

if [ -z "$NSX_PASS" ]; then
  printf "NSX 密碼 (%s@%s): " "$NSX_USER" "$HOST"
  stty -echo 2>/dev/null || true
  read -r NSX_PASS
  stty echo 2>/dev/null || true
  echo
fi

# curl：localhost 自簽憑證用 -k
api_get() { curl -sS -k -u "$NSX_USER:$NSX_PASS" -H "Content-Type: application/json" -X GET "$BASE"; }
api_put() { curl -sS -k -u "$NSX_USER:$NSX_PASS" -H "Content-Type: application/json" -X PUT "$BASE" -d @-; }

# 用 python3 列出 TLS 版本狀態 (stdin 讀 JSON)
print_status() {
  python3 - <<'PY'
import sys, json
try:
    d = json.load(sys.stdin)
except Exception as e:
    sys.stderr.write("解析 JSON 失敗：%s\n" % e); sys.exit(1)
for p in d.get("protocols", []):
    print("   %s: enabled=%s" % (p.get("name"), str(p.get("enabled")).lower()))
PY
}

# 用 python3 將 TLSv1.1 的 enabled 設為 want，輸出整份新 JSON (供 PUT)
set_tls11_json() {
  want="$1"
  WANT="$want" python3 - <<'PY'
import sys, os, json
want = os.environ["WANT"] == "true"
d = json.load(sys.stdin)
found = False
for p in d.get("protocols", []):
    if p.get("name") == "TLSv1.1":
        p["enabled"] = want
        found = True
if not found:
    sys.stderr.write("找不到 TLSv1.1 欄位\n"); sys.exit(2)
json.dump(d, sys.stdout)
PY
}

set_tls11() {
  want="$1"
  echo ">> 讀取目前設定..."
  cur="$(api_get)"
  echo ">> 變更前："
  printf '%s' "$cur" | print_status

  new="$(printf '%s' "$cur" | set_tls11_json "$want")" || die "修改 JSON 失敗 (請用 '$0 get' 檢查)"

  echo ">> 送出變更 (TLSv1.1 -> enabled=$want)..."
  printf '%s' "$new" | api_put | print_status
  echo ">> 完成。變更可能需數十秒套用至 Manager cluster。"
}

cmd="${1:-}"
case "$cmd" in
  get)            api_get; echo ;;
  status)         echo ">> TLS 版本狀態："; api_get | print_status ;;
  enable-tls11)   set_tls11 true ;;
  disable-tls11)  set_tls11 false ;;
  ""|-h|--help|help) usage ;;
  *)              usage; die "未知指令：$cmd" ;;
esac
