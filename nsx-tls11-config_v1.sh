#!/usr/bin/env bash
#
# nsx-tls11-config_v1.sh
# 依據 Broadcom KB 324163 (TLS v1.1 disabled by default from NSX 4.1.1)
# 透過 NSX Manager API (/api/v1/cluster/api-service) 查詢 / 開啟 / 關閉 TLS v1.1。
#
# 需求：curl、jq
# 文件：https://knowledge.broadcom.com/external/article/324163
#
set -euo pipefail

# ---- 設定 (可用環境變數覆寫) ----
NSX_MANAGER="${NSX_MANAGER:-}"          # NSX Manager IP / FQDN，例如 nsx-mgr.lab.local
NSX_USER="${NSX_USER:-admin}"
NSX_PASS="${NSX_PASS:-}"                # 建議用環境變數帶入，避免寫在腳本
INSECURE="${INSECURE:-true}"           # 自簽憑證時設 true (curl -k)
API_PATH="/api/v1/cluster/api-service"

usage() {
  cat <<EOF
用法：
  $0 get                顯示目前 TLS 協定與 cipher 設定
  $0 status             只顯示各 TLS 版本啟用狀態
  $0 enable-tls11       開啟 TLS v1.1
  $0 disable-tls11      關閉 TLS v1.1

環境變數：
  NSX_MANAGER  NSX Manager 位址 (必填)
  NSX_USER     帳號 (預設 admin)
  NSX_PASS     密碼 (必填；未設定時會互動詢問)
  INSECURE     自簽憑證設 true，預設 true

範例：
  NSX_MANAGER=10.0.0.10 NSX_PASS='xxx' $0 status
  NSX_MANAGER=nsx.lab NSX_PASS='xxx' $0 enable-tls11
EOF
}

die() { echo "錯誤：$*" >&2; exit 1; }

command -v curl >/dev/null || die "找不到 curl"
command -v jq   >/dev/null || die "找不到 jq (brew install jq)"

[[ -n "$NSX_MANAGER" ]] || { usage; die "請設定 NSX_MANAGER"; }
if [[ -z "$NSX_PASS" ]]; then
  read -rsp "NSX 密碼 ($NSX_USER@$NSX_MANAGER): " NSX_PASS; echo
fi

CURL_OPTS=(-sS -u "$NSX_USER:$NSX_PASS" -H "Content-Type: application/json")
[[ "$INSECURE" == "true" ]] && CURL_OPTS+=(-k)
BASE="https://${NSX_MANAGER}${API_PATH}"

api_get() {
  curl "${CURL_OPTS[@]}" -X GET "$BASE"
}

api_put() {
  # $1 = JSON body
  curl "${CURL_OPTS[@]}" -X PUT "$BASE" -d "$1"
}

set_tls11() {
  # $1 = true|false
  local want="$1"
  echo ">> 讀取目前設定..."
  local cur; cur="$(api_get)"

  echo ">> 目前 TLS 版本狀態："
  echo "$cur" | jq -r '.protocols[] | "   \(.name): enabled=\(.enabled)"'

  # 將 TLSv1.1 的 enabled 改為指定值，其餘保留
  local new; new="$(echo "$cur" | jq --argjson v "$want" \
    '(.protocols[] | select(.name=="TLSv1.1") | .enabled) |= $v')"

  echo ">> 送出變更 (TLSv1.1 -> enabled=$want)..."
  api_put "$new" | jq -r '.protocols[] | "   \(.name): enabled=\(.enabled)"'
  echo ">> 完成。變更可能需數十秒套用至 Manager cluster。"
}

case "${1:-}" in
  get)
    api_get | jq .
    ;;
  status)
    api_get | jq -r '.protocols[] | "\(.name): enabled=\(.enabled)"'
    ;;
  enable-tls11)
    set_tls11 true
    ;;
  disable-tls11)
    set_tls11 false
    ;;
  ""|-h|--help|help)
    usage
    ;;
  *)
    usage; die "未知指令：$1"
    ;;
esac
