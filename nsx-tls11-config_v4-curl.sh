#!/bin/bash
#
# nsx-tls11-config_v4-curl.sh
# 在「NSX Manager 本機」執行，只用 curl + 內建 sed/grep (不需 jq/perl/python3)。
# 打 localhost API (/api/v1/cluster/api-service) 查詢 / 開啟 / 關閉 TLS v1.1。
#
# 依據 Broadcom KB 324163 (TLS v1.1 disabled by default from NSX 4.1.1)
#
set -eu

HOST="${HOST:-127.0.0.1}"
NSX_USER="${NSX_USER:-admin}"
NSX_PASS="${NSX_PASS:-}"
BASE="https://${HOST}/api/v1/cluster/api-service"

usage() {
  cat <<EOF
在 NSX Manager 本機執行。用法：
  $0 get                顯示 API 原始 JSON
  $0 status             顯示各 TLS 版本啟用狀態
  $0 enable-tls11       開啟 TLS v1.1
  $0 disable-tls11      關閉 TLS v1.1
環境變數：NSX_USER(預設admin) NSX_PASS(不填會詢問) HOST(預設127.0.0.1)
EOF
}

die() { echo "錯誤：$*" >&2; exit 1; }
command -v curl >/dev/null 2>&1 || die "找不到 curl"

if [ -z "$NSX_PASS" ]; then
  printf "NSX 密碼 (%s@%s): " "$NSX_USER" "$HOST"
  stty -echo 2>/dev/null || true; read -r NSX_PASS; stty echo 2>/dev/null || true; echo
fi

AUTH="-u $NSX_USER:$NSX_PASS"
api_get() { curl -sS -k $AUTH -H "Content-Type: application/json" -X GET "$BASE"; }
# PUT body 由 stdin 讀入
api_put() { curl -sS -k $AUTH -H "Content-Type: application/json" -X PUT "$BASE" --data-binary @-; }

# 用 grep 列出 TLS 版本狀態 (相容 name/enabled 兩種排列)
print_status() {
  grep -oE '"name":"TLSv[0-9.]+","enabled":(true|false)|"enabled":(true|false),"name":"TLSv[0-9.]+"' \
    | sed -E 's/.*"name":"(TLSv[0-9.]+)".*"enabled":(true|false).*|.*"enabled":(true|false).*"name":"(TLSv[0-9.]+)".*/   \1\4: enabled=\2\3/' \
    || echo "   (未取得 protocols 欄位)"
}

set_tls11() {
  want="$1"
  echo ">> 讀取目前設定..."
  cur="$(api_get)"
  echo ">> 變更前："
  printf '%s' "$cur" | print_status

  # 只把 TLSv1.1 物件內的 enabled 換成 want，兩種排列都處理；其餘原樣保留
  new="$(printf '%s' "$cur" | sed -E \
    -e "s/(\"name\":\"TLSv1\.1\",\"enabled\":)(true|false)/\1$want/g" \
    -e "s/(\"enabled\":)(true|false)(,\"name\":\"TLSv1\.1\")/\1$want\3/g")"

  if [ "$new" = "$cur" ]; then
    die "找不到 TLSv1.1 欄位或內容未變動，未送出 (請用 '$0 get' 檢查原始 JSON 格式)"
  fi

  echo ">> 送出變更 (TLSv1.1 -> enabled=$want)..."
  printf '%s' "$new" | api_put | print_status
  echo ">> 完成。變更可能需數十秒套用至 Manager cluster。"
}

case "${1:-}" in
  get)            api_get; echo ;;
  status)         echo ">> TLS 版本狀態："; api_get | print_status ;;
  enable-tls11)   set_tls11 true ;;
  disable-tls11)  set_tls11 false ;;
  ""|-h|--help|help) usage ;;
  *)              usage; die "未知指令：${1}" ;;
esac
