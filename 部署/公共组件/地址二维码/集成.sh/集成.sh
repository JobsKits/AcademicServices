#!/bin/sh
# 脚本自述：仅供部署入口加载；复用当前Go构建本地二维码，不联网编码地址、不启动服务。
# 使用独立本轮目录，辅助功能失败时保留原URL和健康服务。
qr_prepare() {
  QR_READY=0
  QR_OUTPUT=''
  QR_BIN="$SERVER_ROOT/.runtime/bin/deployqr"
  log "来源｜二维码编码依赖｜github.com/skip2/go-qrcode｜固定 da1b6568686e + go.sum｜缓存 $GOMODCACHE"
  if (cd "$DEPLOY_ROOT/公共组件/地址二维码" && "$GO_EXE" build -mod=readonly -trimpath -o "$QR_BIN.next" .) >> "$LOG_FILE" 2>&1 && mv "$QR_BIN.next" "$QR_BIN"; then
    QR_OUTPUT="$(mktemp -d "$SERVER_ROOT/.runtime/access-qr.XXXXXX")" || { log '警告：二维码目录未创建，继续显示URL。'; return 0; }
    QR_READY=1
  else
    log '警告：二维码辅助工具构建失败，继续部署并显示URL；详情见本次日志。'
  fi
}
# 同源用户端与管理端分别编码；纯文本日志不包含ANSI。
qr_display() {
  [ "${QR_READY:-0}" = 1 ] || return 0
  qr_base="${1%/}"
  qr_width=0
  set -- --output-dir "$QR_OUTPUT" --title "$2" --entry "用户端|$qr_base/client/" --entry "管理端|$qr_base/admin/"
  if [ -t 1 ] && [ "${TERM:-dumb}" != dumb ] && [ -z "${NO_COLOR+x}" ]; then
    qr_width="${COLUMNS:-}"
    case "$qr_width" in ''|*[!0-9]*) qr_width="$(stty size 2>/dev/null | awk '{print $2}')" ;; esac
    case "$qr_width" in ''|*[!0-9]*) qr_width=0 ;; esac
    set -- "$@" --terminal-width "$qr_width" --ansi
  fi
  if [ -f "$QR_OUTPUT/index.html" ]; then qr_expire; fi
  if "$QR_BIN" "$@" > "$QR_OUTPUT/display.log" 2>&1; then
    cat "$QR_OUTPUT/display.log"
    sed "$(printf 's/\033\\[[0-9;]*m//g')" "$QR_OUTPUT/display.log" >> "$LOG_FILE"
  else
    qr_expire
    log '警告：二维码未生成（请核对无凭据的完整HTTP地址）；原URL仍可复制，服务继续运行。'
  fi
}
# 仅失效本次创建的页面；已另存的图片无法撤销。
qr_expire() {
  if [ "${QR_READY:-0}" = 1 ] && [ -n "${QR_OUTPUT:-}" ]; then
    "$QR_BIN" --expire --output-dir "$QR_OUTPUT" >> "$LOG_FILE" 2>&1 || log '警告：本轮二维码页面未能标记失效，请丢弃旧码。'
  fi
  return 0
}
# 服务器没有明确外部地址时，仅提供标明仅本机的回环入口。
qr_server_access() {
  if [ -n "${PUBLIC_BASE_URL:-}" ]; then
    case "$PUBLIC_BASE_URL" in http://*|https://*) ;; *) log 'PUBLIC_BASE_URL不是完整HTTP/HTTPS入口；未显示配置值。'; return 0 ;; esac
    case "$PUBLIC_BASE_URL" in *'@'*|*'?'*|*'#'*) log 'PUBLIC_BASE_URL必须不含账户、查询参数或片段；未显示配置值。'; return 0 ;; esac
    qr_server_base="${PUBLIC_BASE_URL%/}"
    log_access_url '服务器访问地址｜用户端（按PUBLIC_BASE_URL配置，尚未公网验收）' "$qr_server_base/client/"
    log_access_url '服务器访问地址｜管理端（按PUBLIC_BASE_URL配置，尚未公网验收）' "$qr_server_base/admin/"
    qr_display "$qr_server_base" '知序｜服务器访问入口'
  else
    qr_server_port="${LISTEN_ADDR##*:}"
    case "$qr_server_port" in ''|*[!0-9]*) log '未识别访问端口；请配置PUBLIC_BASE_URL后重新部署以生成二维码。'; return 0 ;; esac
    qr_server_base="http://127.0.0.1:$qr_server_port"
    log '仅本机入口｜回环地址不能供手机扫码访问；请配置PUBLIC_BASE_URL为实际HTTPS域名后重新部署。'
    log_access_url '仅本机｜用户端' "$qr_server_base/client/"
    log_access_url '仅本机｜管理端' "$qr_server_base/admin/"
    qr_display "$qr_server_base" '知序｜仅本机访问（手机不可用）'
  fi
}
