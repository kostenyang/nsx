#!/usr/bin/env bash
#
# nsx-tls11-config_v2.sh  (免 jq 版；只用 curl + macOS 內建 perl)
# 依據 Broadcom KB 324163 (TLS v1.1 disabled by default from NSX 4.1.1)
# 透過 NSX Manager API (/api/v1/cluster/api-service) 查詢 / 開啟 / 關閉 TLS v1.1。
#
# 需求：curl、perl (macOS / Linux 內建)
# 文件：https://knowledge.broadcom.com/external/article/324163
#
set -euo pipefail

# ---- 設定 (可用環境變數覆寫) ----
NSX_MANAGER="${NSX_MANAGER:-}"          # NSX Manager IP / FQDN
NSX_USER="${NSX_USER:-admin}"
NSX_PASS="${NSX_PASS:-}"
INSECURE="${INSECURE:-true}"           # 自簽憑證設 true (curl -k)
API_PATH="/api/v1/cluster/api-service"

usage() {
  cat <<EOF
用法：
  $0 get                顯示 API 原始 JSON 設定
  $0 status             顯示各 TLS 版本啟用狀態
  $0 enable-tls11       開啟 TLS v1.1
  $0 disable-tls11      關閉 TLS v1.1

環境變數：NSX_MANAGER(必填) NSX_USER(預設admin) NSX_PASS(必填) INSECURE(預設true)

範例：
  NSX_MANAGER=10.0.0.10 NSX_PASS='xxx' $0 status
  NSX_MANAGER=nsx.lab   NSX_PASS='xxx' $0 enable-tls11
EOF
}

die() { echo "錯誤：$*" >&2; exit 1; }

command -v curl >/dev/null || die "找不到 curl"
command -v perl >/dev/null || die "找不到 perl"

[[ -n "$NSX_MANAGER" ]] || { usage; die "請設定 NSX_MANAGER"; }
if [[ -z "$NSX_PASS" ]]; then
  read -rsp "NSX 密碼 ($NSX_USER@$NSX_MANAGER): " NSX_PASS; echo
fi

CURL_OPTS=(-sS -u "$NSX_USER:$NSX_PASS" -H "Content-Type: application/json")
[[ "$INSECURE" == "true" ]] && CURL_OPTS+=(-k)
BASE="https://${NSX_MANAGER}${API_PATH}"

api_get() { curl "${CURL_OPTS[@]}" -X GET "$BASE"; }
api_put() { curl "${CURL_OPTS[@]}" -X PUT "$BASE" -d "$1"; }

# 從 JSON 列出 TLS 版本與啟用狀態 (相容 name/enabled 兩種排列)
print_status() {
  perl -0777 -ne '
    while (/"name"\s*:\s*"(TLSv[0-9.]+)"\s*,\s*"enabled"\s*:\s*(true|false)/g) { print "   $1: enabled=$2\n"; }
    while (/"enabled"\s*:\s*(true|false)\s*,\s*"name"\s*:\s*"(TLSv[0-9.]+)"/g) { print "   $2: enabled=$1\n"; }
  '
}

# 將 TLSv1.1 物件中的 enabled 改為指定值 (限制在同一個 {} 內，兩種排列都處理)
set_tls11_in_json() {
  local want="$1"
  perl -0777 -pe '
    my $v = "'"$want"'";
    s/(\{[^{}]*"name"\s*:\s*"TLSv1\.1"[^{}]*?"enabled"\s*:\s*)(?:true|false)/${1}$v/g;
    s/("enabled"\s*:\s*)(?:true|false)([^{}]*?"name"\s*:\s*"TLSv1\.1")/${1}$v$2/g;
  '
}

set_tls11() {
  local want="$1" cur new
  echo ">> 讀取目前設定..."
  cur="$(api_get)"
  echo ">> 變更前："
  printf '%s' "$cur" | print_status

  new="$(printf '%s' "$cur" | set_tls11_in_json "$want")"
  if [[ "$new" == "$cur" ]]; then
    echo ">> 找不到 TLSv1.1 欄位或內容未變動，未送出。請用 '$0 get' 檢查原始 JSON。" >&2
    exit 1
  fi

  echo ">> 送出變更 (TLSv1.1 -> enabled=$want)..."
  api_put "$new" | print_status
  echo ">> 完成。變更可能需數十秒套用至 Manager cluster。"
}

case "${1:-}" in
  get)            api_get; echo ;;
  status)         echo ">> TLS 版本狀態："; api_get | print_status ;;
  enable-tls11)   set_tls11 true ;;
  disable-tls11)  set_tls11 false ;;
  ""|-h|--help|help) usage ;;
  *)              usage; die "未知指令：$1" ;;
esac
