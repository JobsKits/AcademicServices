#!/bin/sh
# 脚本自述：
# - 在当前后端目录配置、准备Go、编译和运行知序服务；不改全局PATH或防火墙。
# - 首次保存管理员/客户密码；数据、日志和SDK留在后端代码目录，Ctrl+C停止服务。
# - --check仅检查路径与平台，不下载、不写入；双击正常入口须回车确认。
SCRIPT_ENTRY="$0"
SERVER_ROOT=""
DEPLOY_ROOT=""
CODE_ROOT=""
LOG_FILE=""
GO_EXE=""
TARGET_OS="linux"
PLATFORM_ID="Alpine"
GO_VERSION="go1.27.3"
FZF_EXE=""
CLOUDFLARED_EXE=""
DEPLOY_MODE=""
OWN_SERVER_PID=""
OWN_TUNNEL_PID=""
# BEGIN JOBS DEPLOYMENT LIFECYCLE
# 输出当前结果；经确认后的反部署同时留下纯文本审计。
lc_message() {
  printf '%s\n' "$*" >&2
  if [ "${LC_AUDIT_ACTIVE:-0}" = 1 ]; then
    printf '%s\t%s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LC_STATE/operations.log" || return 1
  fi
}
# 明确返回未完成，不把保留项当作恢复成功。
lc_error() { lc_message "反部署未完成：$*"; return 1; }
# 复用当前系统的SHA256实现。
lc_hash() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | awk '{print $1}'
  else sha256 -q "$1"; fi
}
# 兼容GNU与BSD的权限读取。
lc_mode() {
  if stat -c '%a' "$1" >/dev/null 2>&1; then stat -c '%a' "$1"; else stat -f '%Lp' "$1"; fi
}
# 只读解析状态，核对归属与路径边界。
lc_context() {
  [ -n "${SERVER_ROOT:-}" ] && [ -d "$SERVER_ROOT" ] && [ ! -L "$SERVER_ROOT" ] || lc_error '后端目录无效。' || return
  LC_ROOT="$SERVER_ROOT/.deployment-state"
  LC_STATE="$LC_ROOT/posix"
  LC_LOCK="$LC_ROOT/operation-lock"
  LC_LOCK_HELD=0
  LC_TAB="$(printf '\t')"
  LC_NL='
'
  case "$SERVER_ROOT" in *"$LC_TAB"*|*"$LC_NL"*) lc_error '路径含换行或制表符。'; return 1;; esac
  for lc_path in "$LC_ROOT" "$LC_STATE" "$LC_LOCK"; do
    [ ! -L "$lc_path" ] || { lc_error '恢复记录或操作锁为符号链接。'; return 1; }
  done
  if [ -f "$LC_ROOT/owner" ] && [ "$(cat "$LC_ROOT/owner")" != posix ]; then
    lc_error '资源归属另一操作系统的部署，请使用原部署系统反部署后再切换。'; return 1
  fi
  if [ -f "$LC_STATE/platform" ] && [ "$(cat "$LC_STATE/platform")" != "${PLATFORM_ID:-Unix}" ]; then
    lc_error '原点属于另一系统入口；请使用原部署系统反部署，不复用其它系统的进程与资源清单。'; return 1
  fi
}
# 用启动时间与命令行识别PID，避免PID复用误停。
lc_identity() { ps -p "$1" -o lstart= -o args= 2>/dev/null; }
# 用跨系统共享目录锁串行化操作，仅回收明确死PID遗锁。
lc_acquire_lock() {
  mkdir -p "$LC_ROOT" || return 1
  if ! mkdir "$LC_LOCK" 2>/dev/null; then
    [ -f "$LC_LOCK/pid" ] && [ ! -L "$LC_LOCK/pid" ] || { lc_error '操作锁缺少可核验PID，保留锁。'; return 1; }
    lc_lock_pid="$(cat "$LC_LOCK/pid")"
    case "$lc_lock_pid" in ''|*[!0-9]*) lc_error '操作锁PID不明。'; return 1;; esac
    if kill -0 "$lc_lock_pid" 2>/dev/null || ps -p "$lc_lock_pid" -o pid= 2>/dev/null | grep '[0-9]' >/dev/null; then
      lc_error '部署或反部署仍在运行，保留现场。'; return 1
    fi
    # 只回收本协议的两项锁记录，未知文件使 rmdir 失败。
    rm -f "$LC_LOCK/pid" "$LC_LOCK/identity" || return 1
    rmdir "$LC_LOCK" && mkdir "$LC_LOCK" || { lc_error '遗锁含未知对象。'; return 1; }
  fi
  printf '%s\n' "$$" > "$LC_LOCK/pid" || return 1
  lc_identity "$$" > "$LC_LOCK/identity" || return 1
  LC_LOCK_SHELL_PID="${BASHPID:-$$}"
  LC_LOCK_HELD=1
}
# 只由持锁主Shell释放，命令替换子Shell不得解锁父进程。
lc_release_lock() {
  [ "${ZSH_SUBSHELL:-0}" = 0 ] || return 0
  [ "${BASHPID:-$$}" = "${LC_LOCK_SHELL_PID:-${BASHPID:-$$}}" ] || return 0
  [ "${LC_LOCK_HELD:-0}" = 1 ] || return 0
  [ "$(cat "$LC_LOCK/pid" 2>/dev/null)" = "$$" ] || return 1
  rm -f "$LC_LOCK/pid" "$LC_LOCK/identity" && rmdir "$LC_LOCK" || return 1
  LC_LOCK_HELD=0
}
# 清单仅能定位本后端实际受控的资源。
lc_safe_relative() {
  case "$1" in .runtime|.runtime/*|.tools|.tools/*|data|data/*) ;; *) return 1;; esac
  case "/$1/" in */../*|*/./*|*"$LC_TAB"*|*"$LC_NL"*) return 1;; esac
}
# 清单按单个文件保存内容摘要与模式；目录仅记录模式，不追踪时间戳。
lc_manifest() {
  local lc_base="$1" lc_output="$2" lc_scope="$3" lc_scan lc_full lc_rel lc_kind lc_digest
  lc_scan="$lc_output.paths"
  : > "$lc_output" || return 1
  : > "$lc_scan" || return 1
  case "$lc_scope" in '.runtime .tools') set -- .runtime .tools;; data) set -- data;; *) return 1;; esac
  for lc_rel do
    [ ! -L "$lc_base/$lc_rel" ] || { lc_error '受控目录为符号链接。'; return 1; }
    [ -e "$lc_base/$lc_rel" ] || continue
    [ -z "$(find "$lc_base/$lc_rel" \( -name "*$LC_NL*" -o -name "*$LC_TAB*" \) -print)" ] || { lc_error '文件名含换行或制表符，保持原状。'; return 1; }
    find "$lc_base/$lc_rel" -print >> "$lc_scan" || return 1
  done
  while IFS= read -r lc_full; do
    lc_rel="${lc_full#"$lc_base/"}"
    lc_safe_relative "$lc_rel" || { lc_error '发现不可安全记录的路径。'; return 1; }
    [ ! -L "$lc_full" ] || { lc_error "保留符号链接：$lc_rel"; return 1; }
    if [ -d "$lc_full" ]; then lc_kind=D; lc_digest=-
    elif [ -f "$lc_full" ]; then lc_kind=F; lc_digest="$(lc_hash "$lc_full")" || return 1
    else lc_error "保留特殊文件：$lc_rel"; return 1; fi
    printf '%s\t%s\t%s\t%s\n' "$lc_kind" "$lc_digest" "$(lc_mode "$lc_full")" "$lc_rel" >> "$lc_output" || return 1
  done < "$lc_scan"
  LC_ALL=C sort "$lc_output" -o "$lc_output" || return 1
  rm -f "$lc_scan"
}
# 复制并校验原文件，作为后续恢复依据。
lc_copy_originals() {
  local lc_kind lc_digest lc_perm lc_rel
  mkdir -p "$LC_STATE/originals" || return 1
  while IFS="$LC_TAB" read -r lc_kind lc_digest lc_perm lc_rel; do
    lc_safe_relative "$lc_rel" || return 1
    if [ "$lc_kind" = D ]; then mkdir -p "$LC_STATE/originals/$lc_rel" || return 1
    else
      mkdir -p "$(dirname -- "$LC_STATE/originals/$lc_rel")" || return 1
      cp -p "$SERVER_ROOT/$lc_rel" "$LC_STATE/originals/$lc_rel" || return 1
      [ "$(lc_hash "$LC_STATE/originals/$lc_rel")" = "$lc_digest" ] || return 1
    fi
  done < "$LC_STATE/before.tsv"
}
# 在启动后立即登记实际进程身份。
lc_record_process() {
  [ -n "${LC_STATE:-}" ] && [ -d "$LC_STATE" ] || return 1
  case "$1" in wrapper|server|tunnel) ;; *) return 1;; esac
  case "$2" in ''|*[!0-9]*) return 1;; esac
  mkdir -p "$LC_STATE/processes" || return 1
  lc_identity "$2" > "$LC_STATE/processes/$1.identity" || return 1
  [ -s "$LC_STATE/processes/$1.identity" ] || return 1
  printf '%s\n' "$2" > "$LC_STATE/processes/$1.pid"
}
# 保存安装包版本清单，不安装或修改软件源。
lc_system_inventory() {
  local lc_inventory
  case "$1" in
    apt) lc_inventory="$(dpkg-query -W -f='${Package}\t${Version}\n')" || return 1;;
    dnf|yum) lc_inventory="$(rpm -qa --qf '%{NAME}\t%{VERSION}-%{RELEASE}\n')" || return 1;;
    apk) lc_inventory="$(apk info -v)" || return 1;;
    pkg) lc_inventory="$(pkg query '%n %v')" || return 1;;
    *) return 1;;
  esac
  printf '%s\n' "$lc_inventory" | LC_ALL=C sort
}
# 系统软件包可能被其它业务共享；留出准确原状态，反部署列明保留，绝不猜测卸载。
lc_note_external_resources() {
  printf '%s\n' "$1" > "$LC_STATE/system-manager" || return 1
  printf '%s\t%s\n' "$1" "$2" >> "$LC_STATE/external-resources.tsv" || return 1
  if [ ! -f "$LC_STATE/system-before.txt" ]; then
    lc_system_inventory "$1" > "$LC_STATE/system-before.txt" || { lc_error '无法记录系统包原状态，未开始安装。'; return 1; }
  fi
}
lc_finish_external_resources() {
  [ -f "$LC_STATE/system-manager" ] || return 0
  lc_system_inventory "$(cat "$LC_STATE/system-manager")" > "$LC_STATE/system-after.txt" || return 1
  comm -13 "$LC_STATE/system-before.txt" "$LC_STATE/system-after.txt" > "$LC_STATE/system-changed.txt"
}
# 在首次资源写入前保存原点并拒绝覆盖不可信旧现场。
lc_begin() {
  lc_context && lc_acquire_lock || return 1
  umask 077
  mkdir -p "$LC_STATE" || return 1
  if [ -f "$LC_STATE/completed" ]; then
    lc_error '上一轮已反部署；恢复审计仍保留。请将 .deployment-state 归档后再部署。'; return 1
  fi
  if [ ! -f "$LC_STATE/before.tsv" ]; then
    [ ! -e "$LC_ROOT/owner" ] || { lc_error '归属已登记但原始清单缺失。'; return 1; }
    lc_manifest "$SERVER_ROOT" "$LC_STATE/before.tsv.next" '.runtime .tools' || return 1
    mv "$LC_STATE/before.tsv.next" "$LC_STATE/before.tsv" || return 1
    lc_copy_originals || return 1
    [ ! -d "$SERVER_ROOT/data" ] || printf 'data\n' > "$LC_STATE/preexisting-data"
    printf 'posix\n' > "$LC_ROOT/owner" || return 1
    printf '%s\n' "${PLATFORM_ID:-Unix}" > "$LC_STATE/platform"
  elif [ -f "$LC_STATE/after.tsv" ]; then
    # 旧清单不得把两次部署之间的外部变化认作本次新建。
    lc_manifest "$SERVER_ROOT" "$LC_STATE/redeploy-check.tsv" '.runtime .tools' || return 1
    cmp -s "$LC_STATE/redeploy-check.tsv" "$LC_STATE/after.tsv" || { lc_error '资源已偏离上次清单，先检查反部署差异。'; return 1; }
  else
    lc_error '上一轮部署未封口，保留资源并请使用反部署检查。'; return 1
  fi
  lc_record_process wrapper "$$"
}
# 在运行服务前封口配置、程序与工具的实际后态。
lc_checkpoint() {
  [ "${LC_LOCK_HELD:-0}" = 1 ] || return 1
  lc_manifest "$SERVER_ROOT" "$LC_STATE/after.tsv.next" '.runtime .tools' || return 1
  mv "$LC_STATE/after.tsv.next" "$LC_STATE/after.tsv" || return 1
  printf 'ready\n' > "$LC_STATE/status"
}
# 封存失败现场和本轮日志后释放锁。
lc_finalize() {
  [ "${ZSH_SUBSHELL:-0}" = 0 ] || return 0
  [ "${BASHPID:-$$}" = "${LC_LOCK_SHELL_PID:-${BASHPID:-$$}}" ] || return 0
  [ "${LC_LOCK_HELD:-0}" = 1 ] || return 0
  local lc_final_code=0
  lc_finish_external_resources || lc_final_code=1
  lc_finalize_resources || lc_final_code=1
  lc_release_lock || lc_final_code=1
  return "$lc_final_code"
}
# 封存与解锁分开，记录失败仍须释放本进程的操作锁。
lc_finalize_resources() {
  if [ ! -f "$LC_STATE/after.tsv" ] && [ -f "$LC_STATE/before.tsv" ] && [ -f "$LC_ROOT/owner" ]; then
    lc_checkpoint || return 1
  fi
  # 运行期仅更新本次日志与独占二维码目录；SDK、配置与程序的封口摘要不重算。
  if [ -f "$LC_STATE/after.tsv" ] && [ -n "${LOG_FILE:-}" ]; then
    lc_manifest "$SERVER_ROOT" "$LC_STATE/finalize.tsv" '.runtime .tools' || return 1
    lc_log_rel="${LOG_FILE#"$SERVER_ROOT/"}"
    lc_quick_rel="${quick_config:-}"
    lc_quick_rel="${lc_quick_rel#"$SERVER_ROOT/"}"
    lc_qr_rel="${QR_OUTPUT:-}"
    lc_qr_rel="${lc_qr_rel#"$SERVER_ROOT/"}"
    awk -F '\t' -v log_path="$lc_log_rel" -v quick="$lc_quick_rel" -v qr="$lc_qr_rel" 'function owned() { return $4==log_path || $4==log_path ".server.log" || $4==log_path ".tunnel.log" || (quick!="" && $4==quick) || (qr!="" && ($4==qr || index($4,qr "/")==1)) } NR==FNR { if (owned()) next; print; next } owned() {print}' "$LC_STATE/after.tsv" "$LC_STATE/finalize.tsv" | LC_ALL=C sort > "$LC_STATE/after.tsv.next" || return 1
    mv "$LC_STATE/after.tsv.next" "$LC_STATE/after.tsv" || return 1
  fi
  return 0
}
# 旧部署没有完整归属证据时保持全部现场。
lc_validate_owner() {
  lc_context || return 1
  [ -f "$LC_ROOT/owner" ] && [ -f "$LC_STATE/before.tsv" ] && [ -f "$LC_STATE/after.tsv" ] || {
    lc_error '没有完整部署前后归属记录；旧部署、系统依赖与业务数据全部保留。'; return 1;
  }
}
# 只停止仍与登记身份完全匹配的本次进程。
lc_stop_recorded() {
  local lc_role lc_pid lc_now lc_saved lc_count
  for lc_role in wrapper server tunnel; do
    [ -f "$LC_STATE/processes/$lc_role.pid" ] || continue
    lc_pid="$(cat "$LC_STATE/processes/$lc_role.pid")"
    case "$lc_pid" in ''|*[!0-9]*) lc_error '进程记录PID无效。'; return 1;; esac
    [ "$lc_pid" != "$$" ] || continue
    lc_now="$(lc_identity "$lc_pid" || true)"
    [ -n "$lc_now" ] || continue
    lc_saved="$(cat "$LC_STATE/processes/$lc_role.identity")"
    [ "$lc_now" = "$lc_saved" ] || { lc_error "PID已复用或身份变化，保留进程：$lc_role"; return 1; }
    kill -TERM "$lc_pid" || return 1
    lc_count=0
    while [ -n "$(lc_identity "$lc_pid" || true)" ] && [ "$lc_count" -lt 10 ]; do sleep 1; lc_count=$((lc_count+1)); done
    [ -z "$(lc_identity "$lc_pid" || true)" ] || { lc_error "进程未退出：$lc_role"; return 1; }
  done
}
# 隔离fzf的宿主默认参数，菜单仅接受明确ID。
lc_pick() {
  FZF_DEFAULT_COMMAND= FZF_DEFAULT_OPTS= FZF_DEFAULT_OPTS_FILE= "$LC_FZF" --height=45% --layout=reverse --border --no-multi --delimiter="$LC_TAB" --with-nth=2 --accept-nth=1 --prompt="$1" --header='方向键/Tab选择，回车确认；Esc取消'
}
# 复用本系统已有健康选择器，反部署不下载工具。
lc_find_fzf() {
  LC_FZF="${FZF_BIN:-}"
  if [ -z "$LC_FZF" ]; then LC_FZF="$(command -v fzf 2>/dev/null || true)"; fi
  if [ -z "$LC_FZF" ]; then
    for lc_candidate in "$SERVER_ROOT"/.tools/deploy-fzf-*/fzf; do
      [ -x "$lc_candidate" ] || continue
      [ -z "$LC_FZF" ] || { lc_error '找到多份fzf，请用FZF_BIN指定本系统健康工具。'; return 1; }
      LC_FZF="$lc_candidate"
    done
  fi
  [ -n "$LC_FZF" ] && [ -x "$LC_FZF" ] || { lc_error '缺少健康fzf；未安装工具或删除数据。'; return 1; }
  FZF_DEFAULT_COMMAND= FZF_DEFAULT_OPTS= FZF_DEFAULT_OPTS_FILE= "$LC_FZF" --help 2>/dev/null | grep -- '--accept-nth' >/dev/null || { lc_error 'fzf不支持当前选择协议。'; return 1; }
}
# 以持久事务阶段保护备份、移动、复核与可重试清源。
lc_backup_and_clear_data() {
  local lc_choice="$1" lc_backup_parent lc_stage lc_phase lc_row
  # 外部数据库暂不自动处理；避免把本地文件打包误报成数据库备份。
  if [ -f "$SERVER_ROOT/.runtime/config.env" ] && sed -n 's/^DATABASE_URL=//p' "$SERVER_ROOT/.runtime/config.env" | grep -v '^$' >/dev/null; then
    lc_error '配置使用外部数据库，尚无对应数据库维护凭据与恢复证据；数据库、文件和资源全部保留。'; return 1
  fi
  [ ! -e "$SERVER_ROOT/data/.server-lock" ] || { lc_error 'data仍有服务锁，保留数据；请先按后端锁诊断确认实例已退出。'; return 1; }
  if [ -e "$SERVER_ROOT/data/.server-guard" ]; then
    command -v lsof >/dev/null 2>&1 || { lc_error '缺少lsof，不能核验文件存储系统锁；保留数据。'; return 1; }
    [ -z "$(lsof -t "$SERVER_ROOT/data/.server-guard" 2>/dev/null)" ] || { lc_error '仍有进程持有文件存储系统锁，保留数据。'; return 1; }
  fi
  lc_backup_parent="$(dirname -- "$SERVER_ROOT")/反部署备份"
  [ ! -L "$lc_backup_parent" ] || { lc_error '备份目录为符号链接。'; return 1; }
  mkdir -p "$lc_backup_parent" || return 1
  if [ -f "$LC_STATE/data-pending" ]; then
    lc_stage="$(cat "$LC_STATE/data-pending")"
    case "$lc_stage" in "$lc_backup_parent"/知序-*) ;; *) lc_error '数据重试记录不在备份范围。'; return 1;; esac
    [ -d "$lc_stage" ] && [ ! -L "$lc_stage" ] && [ -f "$lc_stage/data-manifest.tsv" ] || { lc_error '数据重试记录不完整，保留现场。'; return 1; }
    [ "$(cat "$lc_stage/mode")" = "$lc_choice" ] || { lc_error '已有数据处理事务，必须沿用原备份/清零选择。'; return 1; }
  else
    lc_manifest "$SERVER_ROOT" "$LC_STATE/data-confirmed.tsv" 'data' || return 1
    lc_stage="$(mktemp -d "$lc_backup_parent/知序-$(date '+%Y%m%d-%H%M%S').XXXXXX")" || return 1
    chmod 700 "$lc_stage" || return 1
    cp "$LC_STATE/data-confirmed.tsv" "$lc_stage/data-manifest.tsv" || return 1
    printf '%s\n' "$lc_choice" > "$lc_stage/mode" || return 1
    if [ -f "$SERVER_ROOT/.runtime/config.env" ]; then lc_hash "$SERVER_ROOT/.runtime/config.env" > "$lc_stage/config-hash" || return 1; fi
    printf 'captured\n' > "$lc_stage/phase" || return 1
    # 写在任何移动/删除之前，中断后只继续同一个快照，不重新备份后清零。
    printf '%s\n' "$lc_stage" > "$LC_STATE/data-pending" || return 1
  fi
  LC_BACKUP="$lc_stage"
  lc_phase="$(cat "$lc_stage/phase")"
  case "$lc_phase" in captured|verified|moved|clearing|cleared) ;; *) lc_error '数据事务阶段不明。'; return 1;; esac
  if [ "$lc_phase" = captured ]; then
    lc_manifest "$SERVER_ROOT" "$LC_STATE/data-current.tsv" 'data' || return 1
    cmp -s "$lc_stage/data-manifest.tsv" "$LC_STATE/data-current.tsv" || { lc_error '源数据偏离原确认快照；保留源与原备份。'; return 1; }
    if [ "$lc_choice" = backup ]; then
      if [ -d "$SERVER_ROOT/data" ] && [ ! -d "$lc_stage/data" ]; then cp -pR "$SERVER_ROOT/data" "$lc_stage/data" || return 1; fi
      if [ -f "$SERVER_ROOT/.runtime/config.env" ] && [ ! -f "$lc_stage/config.env" ]; then cp -p "$SERVER_ROOT/.runtime/config.env" "$lc_stage/config.env" || return 1; fi
      lc_manifest "$lc_stage" "$lc_stage/verified.tsv" 'data' || return 1
      cmp -s "$lc_stage/data-manifest.tsv" "$lc_stage/verified.tsv" || { lc_error '备份校验失败，原数据和原备份全部保留。'; return 1; }
      if [ -f "$lc_stage/config-hash" ]; then
        [ -f "$lc_stage/config.env" ] && [ "$(lc_hash "$lc_stage/config.env")" = "$(cat "$lc_stage/config-hash")" ] || { lc_error '配置备份校验失败。'; return 1; }
      fi
    fi
    printf 'verified\n' > "$lc_stage/phase" || return 1
    lc_phase=verified
  fi
  # 移动已发生而阶段写入被中断时，复用原隔离路径。
  if [ -d "$lc_stage/check-tree/data" ] && [ "$lc_phase" = verified ]; then lc_phase=moved; fi
  if [ "$lc_phase" = verified ]; then
    lc_manifest "$SERVER_ROOT" "$LC_STATE/data-current.tsv" 'data' || return 1
    cmp -s "$lc_stage/data-manifest.tsv" "$LC_STATE/data-current.tsv" || { lc_error '源数据偏离确认快照；保留源与原备份，不重新备份后清零。'; return 1; }
    if [ -f "$lc_stage/config-hash" ]; then
      [ -f "$SERVER_ROOT/.runtime/config.env" ] && [ "$(lc_hash "$SERVER_ROOT/.runtime/config.env")" = "$(cat "$lc_stage/config-hash")" ] || { lc_error '配置已偏离确认快照。'; return 1; }
    fi
    mkdir -p "$lc_stage/check-tree" || return 1
    if [ -d "$SERVER_ROOT/data" ]; then mv "$SERVER_ROOT/data" "$lc_stage/check-tree/data" || return 1; fi
    printf 'moved\n' > "$lc_stage/phase" || return 1
    lc_phase=moved
  fi
  [ ! -e "$SERVER_ROOT/data" ] || { lc_error '清理期间原数据路径被重新创建，保留并停止。'; return 1; }
  if [ "$lc_phase" = moved ]; then
    lc_manifest "$lc_stage/check-tree" "$lc_stage/moved.tsv" 'data' || return 1
    cmp -s "$lc_stage/data-manifest.tsv" "$lc_stage/moved.tsv" || { lc_error "移动后快照变化，源在隔离目录原样保留：$lc_stage/check-tree/data"; return 1; }
    printf 'clearing\n' > "$lc_stage/phase" || return 1
    lc_phase=clearing
  fi
  if [ "$lc_phase" = clearing ]; then
    lc_manifest "$lc_stage/check-tree" "$lc_stage/remaining.tsv" 'data' || return 1
    while IFS= read -r lc_row; do
      grep -Fx -- "$lc_row" "$lc_stage/data-manifest.tsv" >/dev/null || { lc_error '隔离源出现后续变更；停止删除并保留。'; return 1; }
    done < "$lc_stage/remaining.tsv"
    if [ -d "$lc_stage/check-tree/data" ]; then
      find "$lc_stage/check-tree/data" -depth -type f -exec rm -f -- {} + || return 1
      find "$lc_stage/check-tree/data" -depth -type d -exec rmdir -- {} + || return 1
    fi
    printf 'cleared\n' > "$lc_stage/phase" || return 1
  fi
  printf '%s\n' "$lc_stage" > "$LC_STATE/data-destination"
  printf 'cleared\n' > "$LC_STATE/data-completed"
  lc_message "数据处理完成；恢复包/审计：$lc_stage"
}
# 按前后摘要逐项恢复，保留共享或后续变更。
lc_restore_resources() {
  local lc_kind lc_digest lc_perm lc_rel lc_current lc_before lc_bkind lc_bdigest lc_bperm lc_brel lc_conflicts=0
  lc_manifest "$SERVER_ROOT" "$LC_STATE/current.tsv" '.runtime .tools' || return 1
  while IFS="$LC_TAB" read -r lc_kind lc_digest lc_perm lc_rel; do
    if ! awk -F '\t' -v p="$lc_rel" '$4==p {found=1} END {exit !found}' "$LC_STATE/after.tsv"; then
      lc_message "保留封口后新增/共享对象：$lc_rel"; lc_conflicts=1
    fi
  done < "$LC_STATE/current.tsv"
  # 部署删除过的原对象也有恢复依据；当前仍缺失时恢复，后来新建的同名对象保留。
  while IFS="$LC_TAB" read -r lc_kind lc_digest lc_perm lc_rel; do
    lc_safe_relative "$lc_rel" || return 1
    if ! awk -F '\t' -v p="$lc_rel" '$4==p {found=1} END {exit !found}' "$LC_STATE/after.tsv"; then
      if [ -e "$SERVER_ROOT/$lc_rel" ] || [ -L "$SERVER_ROOT/$lc_rel" ]; then
        lc_current=''
        if [ -f "$SERVER_ROOT/$lc_rel" ] && [ ! -L "$SERVER_ROOT/$lc_rel" ]; then
          lc_current="$(printf 'F\t%s\t%s\t%s' "$(lc_hash "$SERVER_ROOT/$lc_rel")" "$(lc_mode "$SERVER_ROOT/$lc_rel")" "$lc_rel")"
        elif [ -d "$SERVER_ROOT/$lc_rel" ] && [ ! -L "$SERVER_ROOT/$lc_rel" ]; then
          lc_current="$(printf 'D\t-\t%s\t%s' "$(lc_mode "$SERVER_ROOT/$lc_rel")" "$lc_rel")"
        fi
        [ "$lc_current" != "$(printf '%s\t%s\t%s\t%s' "$lc_kind" "$lc_digest" "$lc_perm" "$lc_rel")" ] || continue
        lc_message "保留删除后重新创建的对象：$lc_rel"; lc_conflicts=1; continue
      fi
      if [ "$lc_kind" = D ]; then mkdir -p "$SERVER_ROOT/$lc_rel" && chmod "$lc_perm" "$SERVER_ROOT/$lc_rel" || return 1
      else
        [ -f "$LC_STATE/originals/$lc_rel" ] && [ ! -L "$LC_STATE/originals/$lc_rel" ] && [ "$(lc_hash "$LC_STATE/originals/$lc_rel")" = "$lc_digest" ] || { lc_error '被删除原对象的恢复副本无效。'; return 1; }
        cp -p "$LC_STATE/originals/$lc_rel" "$SERVER_ROOT/$lc_rel" || return 1
      fi
    fi
  done < "$LC_STATE/before.tsv"
  while IFS="$LC_TAB" read -r lc_kind lc_digest lc_perm lc_rel; do
    lc_safe_relative "$lc_rel" || return 1
    [ "$lc_kind" = F ] || continue
    lc_before="$(awk -F '\t' -v p="$lc_rel" '$4==p {print}' "$LC_STATE/before.tsv")"
    lc_current=''
    if [ -f "$SERVER_ROOT/$lc_rel" ] && [ ! -L "$SERVER_ROOT/$lc_rel" ]; then
      lc_current="$(printf 'F\t%s\t%s\t%s' "$(lc_hash "$SERVER_ROOT/$lc_rel")" "$(lc_mode "$SERVER_ROOT/$lc_rel")" "$lc_rel")"
    elif [ -e "$SERVER_ROOT/$lc_rel" ] || [ -L "$SERVER_ROOT/$lc_rel" ]; then lc_current=conflict; fi
    # 未变化的旧资源保留；已恢复项允许重试。
    [ "$lc_before" != "$(printf '%s\t%s\t%s\t%s' "$lc_kind" "$lc_digest" "$lc_perm" "$lc_rel")" ] || continue
    [ -z "$lc_before" ] || [ "$lc_current" != "$lc_before" ] || continue
    if [ -z "$lc_before" ] && [ -z "$lc_current" ]; then continue; fi
    if [ "$lc_current" != "$(printf '%s\t%s\t%s\t%s' "$lc_kind" "$lc_digest" "$lc_perm" "$lc_rel")" ]; then
      lc_message "保留后续变更/共享对象：$lc_rel"; lc_conflicts=1; continue
    fi
    if [ -z "$lc_before" ]; then rm -f -- "$SERVER_ROOT/$lc_rel" || return 1
    else
      IFS="$LC_TAB" read -r lc_bkind lc_bdigest lc_bperm lc_brel <<EOF
$lc_before
EOF
      [ "$lc_bkind" = F ] && [ -f "$LC_STATE/originals/$lc_rel" ] && [ ! -L "$LC_STATE/originals/$lc_rel" ] && [ "$(lc_hash "$LC_STATE/originals/$lc_rel")" = "$lc_bdigest" ] || { lc_error '原始恢复副本校验失败。'; return 1; }
      cp -p "$LC_STATE/originals/$lc_rel" "$SERVER_ROOT/$lc_rel" || return 1
      [ "$(lc_hash "$SERVER_ROOT/$lc_rel")" = "$lc_bdigest" ] || return 1
    fi
  done < "$LC_STATE/after.tsv"
  # 新目录只在空目录时回收；未知文件和共享内容自然阻止rmdir。
  awk -F '\t' '$1=="D" { print $4 }' "$LC_STATE/after.tsv" | LC_ALL=C sort -r > "$LC_STATE/directories.txt"
  while IFS= read -r lc_rel; do
    lc_safe_relative "$lc_rel" || return 1
    [ -d "$SERVER_ROOT/$lc_rel" ] || continue
    if ! awk -F '\t' -v p="$lc_rel" '$4==p {found=1} END {exit !found}' "$LC_STATE/before.tsv"; then
      rmdir "$SERVER_ROOT/$lc_rel" 2>/dev/null || { lc_message "保留非空/共享目录：$lc_rel"; lc_conflicts=1; }
    fi
  done < "$LC_STATE/directories.txt"
  lc_manifest "$SERVER_ROOT" "$LC_STATE/restored.tsv" '.runtime .tools' || return 1
  cmp -s "$LC_STATE/before.tsv" "$LC_STATE/restored.tsv" || { lc_message '当前资源与部署原点仍有差异，清单已保留。'; lc_conflicts=1; }
  if [ -f "$LC_STATE/external-resources.tsv" ]; then
    lc_message '保留部署时由系统包管理器处理的共享依赖；原状态、实际包变化和来源见恢复记录，系统环境未完全还原。'
    lc_conflicts=1
  fi
  [ "$lc_conflicts" = 0 ] || { lc_error '部分资源已恢复，仍有保留项；请核对清单后重试。'; return 1; }
}
# 先展示固定自述，颜色仅用于终端并保留纯文本降级。
lc_show_intro() {
  local lc_color=0
  if [ -t 1 ] && [ "${TERM:-dumb}" != dumb ] && [ -z "${NO_COLOR+x}" ] && [ "${PLAIN_OUTPUT:-0}" != 1 ]; then lc_color=1; fi
  [ "$lc_color" = 0 ] || printf '\033[1;31m'
  printf '知序服务｜%s 反部署\n' "${PLATFORM_ID:-Unix}"
  [ "$lc_color" = 0 ] || printf '\033[0;34m'
  printf '%s\n' '1、按部署前后清单恢复程序、配置与工程内工具；外部数据库和系统共享依赖不自动删除。' '2、数据默认备份到后端目录外，校验后清源；清零不可恢复。Esc / Ctrl+C取消。' '3、危险确认前不写业务；确认后审计见后端 .deployment-state/posix/operations.log。' '4、恢复记录与状态见 .deployment-state/posix/，完整备份或隔离源位置见 data-pending。' '当前仅有语法与隔离验证，目标系统原生验收分别记录。'
  [ "$lc_color" = 0 ] || printf '\033[0m'
}
# 编排只读检查、双重确认、数据处理和资源恢复。
lc_undeploy_main() {
  lc_show_intro
  lc_context || return 1
  case "${1:-}" in
    --check|--plan) [ $# = 1 ] || return 2; lc_validate_owner || return 1; lc_message '检查通过；未写入、停止进程或删除。'; return 0;;
    '') [ $# = 0 ] || return 2;;
    *) lc_error '只接受 --check / --plan 或无参数。'; return 2;;
  esac
  [ -t 0 ] || { lc_error '请在交互终端运行。'; return 1; }
  printf '已了解范围，回车继续；其它输入取消：' >&2
  IFS= read -r lc_intro || return 130
  [ -z "$lc_intro" ] || return 130
  lc_validate_owner || return 1
  if [ -f "$LC_STATE/completed" ]; then lc_message '反部署已完成；审计与恢复副本仍保留，无重复删除。'; return 0; fi
  lc_find_fzf || return 1
  lc_choice="$(printf 'backup\t数据库数据备份（默认，校验后清源）\nclear\t数据库数据清零（不可恢复）\ncancel\t取消，不修改\n' | lc_pick '数据处理 > ')" || return 130
  case "$lc_choice" in backup|clear) ;; *) return 130;; esac
  lc_message "准确数据范围：$SERVER_ROOT/data；配置：$SERVER_ROOT/.runtime/config.env"
  lc_message '仅回收清单归属资源，原有与共享环境保留。'
  lc_confirm="$(printf 'cancel\t取消（默认）\napply\t确认反部署并%s本项目源数据\n' "$(if [ "$lc_choice" = backup ]; then printf '备份后清理'; else printf '永久清零'; fi)" | lc_pick '危险操作确认 > ')" || return 130
  [ "$lc_confirm" = apply ] || return 130
  printf '按一次空格后回车复核授权；其它输入取消：' >&2
  IFS= read -r lc_space || return 130
  [ "$lc_space" = ' ' ] || return 130
  lc_stop_recorded || return 1
  lc_acquire_lock || return 1
  LC_AUDIT_ACTIVE=1
  umask 077
  lc_message "确认反部署；数据模式=$lc_choice；资源原点=$LC_STATE；PID按已登记身份核验。"
  trap 'lc_release_lock' EXIT
  trap 'lc_release_lock; exit 130' INT TERM HUP
  if [ ! -f "$LC_STATE/data-completed" ]; then lc_backup_and_clear_data "$lc_choice" || return 1; fi
  lc_restore_resources || return 1
  printf 'completed\n' > "$LC_STATE/completed" || return 1
  lc_release_lock || return 1
  lc_message '反部署已完成；已恢复清单内变更，原有资源与恢复审计保留。'
}
# END JOBS DEPLOYMENT LIFECYCLE
# 按入口位置解析源码，不依赖终端工作目录。
prepare_display_context() {
  SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$SCRIPT_ENTRY")" && pwd -P)" || exit 1
  CODE_ROOT="$(CDPATH= cd -- "$SCRIPT_DIR/../../../代码" && pwd -P)" || exit 1
  DEPLOY_ROOT="$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd -P)" || exit 1
  SERVER_ROOT="$CODE_ROOT/后端/后端代码"
  LOG_FILE="$SERVER_ROOT/.runtime/logs/deploy-$(date '+%Y%m%d-%H%M%S').log"
}
# 输出自述；确认前不写入磁盘。
show_script_intro_and_wait() {
  prepare_display_context
  if [ -t 1 ] && [ "${TERM:-dumb}" != dumb ] && [ -z "${NO_COLOR:-}" ]; then printf '\033[1;31m'; fi
  printf '\n知序服务｜Alpine 部署\n'
  if [ -t 1 ] && [ "${TERM:-dumb}" != dumb ] && [ -z "${NO_COLOR:-}" ]; then printf '\033[0;34m'; fi
  printf '%s\n' '1、配置本工程账户和监听地址，必要时下载官方Go SDK并校验SHA256。' '2、回车后用fzf选择本地部署＋内网穿透或服务器部署；Esc取消。' '本地模式会创建公网临时HTTPS，先配置非默认密码；服务器模式不启动隧道。' '缺少fzf/cloudflared时按锁清单自动准备工程内工具并显示来源；不改全局PATH、系统服务或防火墙。' '3、后端 .deployment-state 保存原点清单与恢复副本；.tools、.runtime、data 保存本工程资源。' '4、Go模块默认使用goproxy.cn镜像，失败回退官方源；可用GOPROXY覆盖，仅当前进程生效。'
  printf '源码：%s\n日志：%s\n' "$SERVER_ROOT" "$LOG_FILE"
  if [ -t 1 ] && [ "${TERM:-dumb}" != dumb ] && [ -z "${NO_COLOR:-}" ]; then printf '\033[0m'; fi
  if [ "${1:-}" = --check ] && [ $# -eq 1 ]; then
    check_source
    check_platform
    printf '%s\n' '检查通过；尚未编译、安装或启动。'
    exit 0
  fi
  if [ "${1:-}" = --plan ] && [ $# -eq 1 ]; then show_plan; exit 0; fi
  [ $# -eq 0 ] || { printf '%s\n' '不支持的参数。仅可使用 --check 或 --plan。' >&2; exit 2; }
  [ -t 0 ] || { printf '%s\n' '请在交互终端运行，未执行部署。' >&2; exit 1; }
  printf '%s' '按回车继续；输入任意字符取消：'
  IFS= read -r deploy_answer || exit 1
  [ -z "$deploy_answer" ] || exit 1
}
# 将进度写入本次日志。
log() {
  printf '%s\n' "$*" | tee -a "$LOG_FILE"
}
# 提醒临时服务依赖当前终端；样式仅写终端，日志保持纯文本。
log_terminal_lifetime_notice() {
  printf '%s\n' '关闭此运行终端，服务将结束' >> "$LOG_FILE" || return 1
  if [ -t 1 ] && [ "${TERM:-dumb}" != dumb ] && [ -z "${NO_COLOR:-}" ]; then
    printf '\033[1;31m%s\033[0m\n' '关闭此运行终端，服务将结束'
  else
    printf '%s\n' '关闭此运行终端，服务将结束'
  fi
}
# 失败立即停止，保留日志和原数据。
fail() {
  log "失败：$*"
  exit 1
}
# 确认后才创建运行目录和日志。
initialize_runtime() {
  set -eu
  set -o pipefail
  umask 077
  for runtime_target in "$SERVER_ROOT/.runtime" "$SERVER_ROOT/.runtime/logs" "$SERVER_ROOT/.runtime/bin" "$SERVER_ROOT/.tools" "$SERVER_ROOT/data"; do
    [ ! -L "$runtime_target" ] || { printf '%s\n' '拒绝写入符号链接运行目录。' >&2; exit 1; }
  done
  mkdir -p "$SERVER_ROOT/.runtime/logs" "$SERVER_ROOT/.tools"
  : > "$LOG_FILE"
  trap 'stty echo 2>/dev/null || true; printf "\n已停止；数据已保留。\n"; exit 130' INT TERM
}
# 拒绝缺少源码的半份拷贝。
check_source() {
  [ -f "$SERVER_ROOT/go.mod" ] && [ -d "$SERVER_ROOT/cmd/server" ] || { printf '%s\n' '请保持根目录部署与代码/后端/后端代码的相对结构；缺少 go.mod 或 cmd/server。' >&2; exit 1; }
}
# 只读取系统发行标记，不执行os-release内容。
check_linux() {
  [ "$(uname -s)" = Linux ] || { printf '%s\n' '请使用当前系统专属入口。' >&2; exit 1; }
  distro_id="$(sed -n 's/^ID=//p' /etc/os-release | tr -d '\"')"
  [ "$distro_id" = "$1" ] || { printf '当前发行版为%s，请使用对应入口。\n' "$distro_id" >&2; exit 1; }
}
# 检查目标系统，避免拿错平台入口。
check_platform() {
  check_linux alpine
}
# 必需依赖缺失时请求一次安装，非空输入和EOF均停止。
confirm_install() {
  printf '%s\n' "$1"
  printf '%s' '直接回车安装；输入任意字符后回车取消：'
  IFS= read -r dependency_answer || exit 1
  [ -z "$dependency_answer" ] || exit 1
}
# 检查下载与解压工具，只沿缺失分支安装。
ensure_transfer_tools() {
  if command -v curl >/dev/null 2>&1 && command -v tar >/dev/null 2>&1 && { command -v sha256sum >/dev/null 2>&1 || command -v shasum >/dev/null 2>&1 || command -v sha256 >/dev/null 2>&1; }; then
    curl --version >/dev/null && tar --version >/dev/null 2>&1 && return 0
  fi
  confirm_install '缺少curl/tar/SHA256工具，将使用系统软件源安装基础工具；需要管理员权限。'
  lc_note_external_resources apk "ca-certificates curl tar coreutils" || fail '无法记录系统包原状态。'
  log '来源｜系统已配置软件源｜apk 基础工具包'
  if [ "$(id -u)" -eq 0 ]; then sh -c 'apk add --no-cache ca-certificates curl tar coreutils' >> "$LOG_FILE" 2>&1 || fail '基础工具安装失败。'
  elif command -v sudo >/dev/null 2>&1; then sudo sh -c 'apk add --no-cache ca-certificates curl tar coreutils' >> "$LOG_FILE" 2>&1 || fail '基础工具安装失败。'
  else fail '需要root或sudo安装基础工具。'; fi
  command -v curl >/dev/null 2>&1 && curl --version >/dev/null 2>&1 && command -v tar >/dev/null 2>&1 || fail '工具安装后复检失败。' 
}
# 只接受本交付核验过的SDK版本，不更新全局安装。
accept_go() {
  [ -n "$1" ] && [ -x "$1" ] || return 1
  [ "$("$1" version 2>/dev/null | awk '{print $3}')" = "$GO_VERSION" ] || return 1
  GO_EXE="$1"
}
# 根据架构选择官方归档及固定摘要。
select_archive() {
  case "$(uname -m)" in
    arm64|aarch64) GO_ARCH=arm64 ;;
    x86_64|amd64) GO_ARCH=amd64 ;;
    *) fail '当前脚本仅提供amd64和arm64运行环境。' ;;
  esac
  case "$TARGET_OS-$GO_ARCH" in
    linux-amd64) GO_ARCHIVE=go1.27.3.linux-amd64.tar.gz; GO_SHA=65efbc80fdc1fa2cd2631cad5b481777a68e8725f34e89f50fc6ac714e379b40 ;;
    linux-arm64) GO_ARCHIVE=go1.27.3.linux-arm64.tar.gz; GO_SHA=a06e99309dbcbdca1a8ccd2282c3ee146e55930886e26b4f1193269587165f49 ;;
    *) fail '没有当前平台官方SDK归档。' ;;
  esac
}
# 对下载归档校验，校验失败不解压。
verify_archive() {
  if command -v sha256sum >/dev/null 2>&1; then
    actual_hash="$(sha256sum "$1" | awk '{print $1}')"
  elif command -v shasum >/dev/null 2>&1; then
    actual_hash="$(shasum -a 256 "$1" | awk '{print $1}')"
  else
    actual_hash="$(sha256 -q "$1")"
  fi
  [ "$actual_hash" = "$GO_SHA" ] || fail 'SDK摘要不匹配，未解压。请检查网络与来源。'
}
# 缺SDK时下载到工程本地；已有健康SDK直接复用。
ensure_go() {
  if accept_go "${GO_BIN:-}"; then return; fi
  candidate_go="$(command -v go 2>/dev/null || true)"
  if accept_go "$candidate_go"; then return; fi
  if [ -n "$candidate_go" ]; then log "现有Go未通过锁定版本 $GO_VERSION 健康检查；保留系统安装，改用工程内SDK。"; fi
  if accept_go "$SERVER_ROOT/.tools/$GO_VERSION/bin/go"; then return; fi
  select_archive
  log "准备模式所需 $GO_VERSION：来源 https://go.dev/dl/$GO_ARCHIVE；目标 $SERVER_ROOT/.tools/$GO_VERSION；不更改系统Go。"
  ensure_transfer_tools
  archive_path="$SERVER_ROOT/.tools/$GO_ARCHIVE"
  log "来源｜Go SDK｜https://go.dev/dl/$GO_ARCHIVE → $archive_path"
  curl --fail --location --proto '=https' --tlsv1.2 --retry 2 --connect-timeout 15 --max-time 1200 "https://go.dev/dl/$GO_ARCHIVE" -o "$archive_path" >> "$LOG_FILE" 2>&1 || fail 'Go下载失败。'
  verify_archive "$archive_path"
  staging_dir="$(mktemp -d "$SERVER_ROOT/.tools/sdk-stage.XXXXXX")" || fail '无法建立临时目录。'
  tar -xzf "$archive_path" -C "$staging_dir" >> "$LOG_FILE" 2>&1 || fail 'SDK解压失败。'
  if [ -e "$SERVER_ROOT/.tools/$GO_VERSION" ]; then fail '本地SDK目录存在但不健康，保留原目录；移走后重试。'; fi
  mv "$staging_dir/go" "$SERVER_ROOT/.tools/$GO_VERSION"
  rmdir "$staging_dir"
  accept_go "$SERVER_ROOT/.tools/$GO_VERSION/bin/go" || fail 'Go安装后健康检查失败。'
}
# 隐藏输入密码，并限制换行以保证配置文件格式。
read_password() {
  printf '%s' "$1"
  stty -echo
  IFS= read -r CONFIG_PASSWORD || { stty echo; exit 1; }
  stty echo
  printf '\n'
  [ "${#CONFIG_PASSWORD}" -ge 12 ] || fail '密码至少12个字符。'
}
# 初次配置写一次，其后只读复用，禁止执行配置文本。
configure_server() {
  config_file="$SERVER_ROOT/.runtime/config.env"
  [ ! -L "$config_file" ] || fail "拒绝读取或写入符号链接配置。"
  if [ ! -f "$config_file" ]; then
    printf '%s' '监听地址 [127.0.0.1:8080]：'
    IFS= read -r config_listen || exit 1
    config_listen="${config_listen:-127.0.0.1:8080}"
    read_password '设置管理员admin密码（至少12字符）：'
    config_admin="$CONFIG_PASSWORD"
    read_password '设置客户customer密码（至少12字符，不能与管理员相同）：'
    [ "$CONFIG_PASSWORD" != "$config_admin" ] || fail '两个账户必须使用不同密码。'
    printf '%s' 'PostgreSQL连接串（直接回车使用单实例本地文件存储；输入隐藏）：'
    stty -echo
    IFS= read -r config_database || { stty echo; exit 1; }
    stty echo
    printf '\n'
    {
      printf 'APP_ENV=production\nLISTEN_ADDR=%s\nADMIN_PASSWORD=%s\nDEMO_CUSTOMER_PASSWORD=%s\nDATABASE_URL=%s\nCORS_ORIGINS=\n' "$config_listen" "$config_admin" "$CONFIG_PASSWORD" "$config_database"
    } > "$config_file"
    chmod 600 "$config_file"
    unset config_admin CONFIG_PASSWORD config_database
  fi
  [ ! -L "$config_file" ] || fail '拒绝读取符号链接配置。'
  while IFS= read -r config_line || [ -n "$config_line" ]; do
    case "$config_line" in ''|'#'*) continue ;; esac
    config_key="${config_line%%=*}"
    config_value="${config_line#*=}"
    case "$config_key" in
      APP_ENV|LISTEN_ADDR|ADMIN_PASSWORD|DEMO_CUSTOMER_PASSWORD|DATABASE_URL|CORS_ORIGINS|GOPROXY|PUBLIC_BASE_URL) export "$config_key=$config_value" ;;
      *) fail "未知配置键：$config_key" ;;
    esac
  done < "$config_file"
  export DATA_DIR="$SERVER_ROOT/data"
  export ADMIN_STATIC_DIR="$SERVER_ROOT/admin-web"
  export CLIENT_STATIC_DIR="$SERVER_ROOT/client-web"
  export GOPROXY="${GOPROXY:-https://goproxy.cn|https://proxy.golang.org|direct}"
  export GOTELEMETRY=off
  export GOMODCACHE="$SERVER_ROOT/.tools/gomodcache"
  export GOCACHE="$SERVER_ROOT/.tools/gobuildcache"
  export GOTOOLCHAIN=local
  export CGO_ENABLED=0
}
# 构建到临时文件，成功后替换程序，保留数据。
build_server() {
  check_source
  cd "$SERVER_ROOT"
  module_source="$(printf '%s' "$GOPROXY" | sed -E 's#(https?://)[^/@]*@#\1***@#g; s#\?[^|, ]*#?...#g')"
  log "来源｜Go依赖｜$module_source｜版本按go.mod/go.sum锁定｜缓存 $GOMODCACHE"
  log "构建｜$("$GO_EXE" version)｜$SERVER_ROOT"
  "$GO_EXE" build -trimpath -o "$SERVER_ROOT/.runtime/bin/server.next" ./cmd/server >> "$LOG_FILE" 2>&1 || fail '编译失败，原程序与数据已保留。'
  mv "$SERVER_ROOT/.runtime/bin/server.next" "$SERVER_ROOT/.runtime/bin/server"
  log '编译通过。'
  qr_helper="$DEPLOY_ROOT/公共组件/地址二维码/集成.sh/集成.sh"
  if [ -f "$qr_helper" ] && [ ! -L "$qr_helper" ]; then
    . "$qr_helper"
    qr_prepare
  else
    log '警告：缺少二维码辅助模块，保留URL输出并继续运行。'
  fi
}
# 前台运行便于新手看到错误，Ctrl+C可正常退出。
run_server() {
  log "启动｜监听 $LISTEN_ADDR｜管理端 /admin/｜Ctrl+C停止；运行日志 $LOG_FILE"
  if [ ! -f "$ADMIN_STATIC_DIR/index.html" ]; then log '管理端静态文件缺失；API仍可运行，请按说明先构建Flutter管理端。'; fi
  local_server_log="$LOG_FILE.server.log"
  "$SERVER_ROOT/.runtime/bin/server" > "$local_server_log" 2>&1 &
  OWN_SERVER_PID=$!
  lc_record_process server "$OWN_SERVER_PID" || fail '无法登记后端进程身份。'
  log "运行日志｜$local_server_log"
  wait "$OWN_SERVER_PID"
}
# 检查锁清单并映射当前宿主架构，不修改环境。
select_tool_platform() {
  TOOL_OS="$TARGET_OS"
  case "$(uname -m)" in
    arm64|aarch64) TOOL_ARCH=arm64 ;;
    x86_64|amd64) TOOL_ARCH=amd64 ;;
    *) fail '当前入口仅提供amd64与arm64工具。' ;;
  esac
  TOOL_LOCK="$DEPLOY_ROOT/deploy-tools.lock.tsv"
  [ -f "$TOOL_LOCK" ] && [ ! -L "$TOOL_LOCK" ] || fail '缺少可信工具锁清单，请保留完整部署目录。'
}
# 检查工具版本与选择器能力，不触发联网或安装。
accept_local_tool() {
  [ -n "$2" ] && [ -x "$2" ] && [ ! -L "$2" ] || return 1
  if [ "$1" = fzf ]; then
    FZF_DEFAULT_COMMAND= FZF_DEFAULT_OPTS= FZF_DEFAULT_OPTS_FILE= "$2" --version >/dev/null 2>&1 || return 1
    FZF_DEFAULT_COMMAND= FZF_DEFAULT_OPTS= FZF_DEFAULT_OPTS_FILE= "$2" --help 2>/dev/null | grep -- '--accept-nth' >/dev/null || return 1
    FZF_EXE="$2"
  else
    "$2" --version >/dev/null 2>&1 || return 1
    candidate_tool_help="$("$2" tunnel --help 2>/dev/null)" || return 1
    for required_flag in --url --config --no-autoupdate; do
      printf '%s\n' "$candidate_tool_help" | grep -- "$required_flag" >/dev/null || return 1
    done
    CLOUDFLARED_EXE="$2"
  fi
}
# 校验工具归档摘要，失败不解压或执行。
verify_tool_download() {
  if command -v sha256sum >/dev/null 2>&1; then
    tool_actual_sha="$(sha256sum "$1" | awk '{print $1}')"
  elif command -v shasum >/dev/null 2>&1; then
    tool_actual_sha="$(shasum -a 256 "$1" | awk '{print $1}')"
  else
    tool_actual_sha="$(sha256 -q "$1")"
  fi
  [ "$tool_actual_sha" = "$2" ] || fail '工具下载SHA256不匹配，未解压或执行。'
}
# 复用健康工具；缺失时按锁清单下载到工程内并复检。
ensure_local_tool() {
  requested_tool="$1"
  if [ "$requested_tool" = fzf ]; then tool_override="${FZF_BIN:-}"; else tool_override="${CLOUDFLARED_BIN:-}"; fi
  if accept_local_tool "$requested_tool" "$tool_override"; then return; fi
  discovered_tool="$(command -v "$requested_tool" 2>/dev/null || true)"
  if [ -n "$discovered_tool" ]; then
    resolved_tool="$discovered_tool"
    if [ -L "$resolved_tool" ]; then
      resolved_tool="$(readlink "$resolved_tool")"
      case "$resolved_tool" in /*) ;; *) resolved_tool="$(dirname -- "$discovered_tool")/$resolved_tool" ;; esac
    fi
    if accept_local_tool "$requested_tool" "$resolved_tool"; then return; fi
  fi
  tool_target="$SERVER_ROOT/.tools/deploy-$requested_tool-$TOOL_OS-$TOOL_ARCH"
  [ ! -L "$tool_target" ] || fail '拒绝符号链接工具缓存。'
  if accept_local_tool "$requested_tool" "$tool_target/$requested_tool"; then return; fi
  tool_record="$(awk -F '\t' -v tool="$requested_tool" -v os="$TOOL_OS" -v arch="$TOOL_ARCH" 'NR>1 && $1==tool && $2==os && $3==arch {print $4 "\t" $5 "\t" $6 "\t" $7 "\t" $8}' "$TOOL_LOCK")"
  if [ -z "$tool_record" ]; then
    if [ "$TOOL_OS" = freebsd ]; then
      log "没有锁定的 $requested_tool/$TOOL_OS/$TOOL_ARCH 上游成品；请由管理员检查受信pkg候选后安装，再重运行。"
      log "只读查询：pkg search -x $requested_tool；脚本未修改软件源或下载其它架构工具。"
    fi
    fail "缺少 $requested_tool 的当前系统架构归档；可通过对应工具环境变量指定已验证原生工具。"
  fi
  IFS="$(printf '\t')" read -r TOOL_VERSION TOOL_ARCHIVE TOOL_SHA TOOL_URL TOOL_KIND <<EOF
$tool_record
EOF
  case "$TOOL_URL" in https://github.com/junegunn/fzf/releases/download/*|https://github.com/cloudflare/cloudflared/releases/download/*) ;; *) fail '工具来源不在锁定官方发布域。' ;; esac
  ensure_transfer_tools
  log "来源｜$requested_tool $TOOL_VERSION｜$TOOL_URL → $tool_target"
  log "缺少健康 $requested_tool，按已确认自述自动准备并校验工程内原生工具，不修改全局PATH。"
  tool_stage="$(mktemp -d "$SERVER_ROOT/.tools/tool-stage.XXXXXX")" || fail '无法建立工具临时目录。'
  curl --fail --location --proto '=https' --tlsv1.2 --retry 2 --connect-timeout 15 --max-time 300 "$TOOL_URL" -o "$tool_stage/$TOOL_ARCHIVE" >> "$LOG_FILE" 2>&1 || fail '工具下载失败；请查看来源和网络，未继续部署。'
  verify_tool_download "$tool_stage/$TOOL_ARCHIVE" "$TOOL_SHA"
  case "$TOOL_KIND" in
    tar.gz) tar -xzf "$tool_stage/$TOOL_ARCHIVE" -C "$tool_stage" >> "$LOG_FILE" 2>&1 || fail '工具解压失败。' ;;
    binary) cp "$tool_stage/$TOOL_ARCHIVE" "$tool_stage/$requested_tool" ;;
    *) fail '本Shell入口不接受该工具归档格式。' ;;
  esac
  [ -f "$tool_stage/$requested_tool" ] && [ ! -L "$tool_stage/$requested_tool" ] || fail '归档缺少普通可执行工具文件。'
  chmod u+x "$tool_stage/$requested_tool"
  accept_local_tool "$requested_tool" "$tool_stage/$requested_tool" || fail '工具安装后健康检查失败；未下载错平台回退。'
  [ ! -e "$tool_target" ] || fail '本地工具目录存在但不健康，已保留，请移走损坏缓存后重试。'
  mkdir "$tool_target"
  mv "$tool_stage/$requested_tool" "$tool_target/$requested_tool"
  accept_local_tool "$requested_tool" "$tool_target/$requested_tool" || fail '工具发布后复检失败。'
}
# 使用根层fzf选择部署方式，取消或异常不进入业务。
select_deployment_mode() {
  select_tool_platform
  ensure_local_tool fzf
  set +e
  selected_mode="$(printf 'local\t本地部署＋内网穿透（免费临时HTTPS）\nserver\t服务器部署（仅运行后端）\n' | FZF_DEFAULT_COMMAND= FZF_DEFAULT_OPTS= FZF_DEFAULT_OPTS_FILE= "$FZF_EXE" --height=45% --layout=reverse --border --no-multi --delimiter="$(printf '\t')" --with-nth=2 --accept-nth=1 --prompt='部署方式 > ' --header='回车选择；Esc取消，不启动后端')"
  selector_code=$?
  set -e
  case "$selector_code" in
    0) ;;
    1|130) log '已取消选择；未准备Go、修改配置或启动后端。'; exit 130 ;;
    *) fail "fzf选择器失败（$selector_code），未启动业务。" ;;
  esac
  case "$selected_mode" in
    local) DEPLOY_MODE=local ;;
    server) DEPLOY_MODE=server ;;
    *) fail '选择结果为空或无法识别，未启动业务。' ;;
  esac
  log "部署模式｜$DEPLOY_MODE"
}
# 只读打印两模式与工具供应链计划。
show_plan() {
  check_source
  check_platform
  printf '%s\n' '计划：自述回车 → 健康fzf/缺失时本地下载 → 模式选择 → Go/配置/编译。'
  printf '%s\n' '本地模式：强制本次进程production、loopback和同源；健康后建立免费随机HTTPS；Ctrl+C回收本次两个子进程。'
  printf '%s\n' '服务器模式：保留原配置，只运行后端，不启动隧道、不开放防火墙。'
  printf '%s\n' '工具清单：部署/deploy-tools.lock.tsv；fzf0.74.5、cloudflared2026.10.7；原生组合缺失时停止并说明，不运行错架构。'
  printf '%s\n' '公网：Cloudflare Quick仅测试、无SLA、URL变动/200在途/不支持SSE；本计划未联网、下载、写配置或启动。'
}
# 模式确认后建立业务目录，取消选择时不触发。
initialize_business_runtime() {
  for runtime_target in "$SERVER_ROOT/.runtime/bin" "$SERVER_ROOT/data"; do
    [ ! -L "$runtime_target" ] || fail '拒绝业务目录符号链接。'
  done
  mkdir -p "$SERVER_ROOT/.runtime/bin" "$SERVER_ROOT/data"
}
# 本地模式只覆盖当前子进程的公开相关设置，不重写已有配置。
prepare_selected_mode() {
  [ "$DEPLOY_MODE" = local ] || return 0
  ensure_local_tool cloudflared
  local_port="${LISTEN_ADDR##*:}"
  case "$local_port" in ''|*[!0-9]*) fail '本地模式监听端口无效。' ;; esac
  [ "$local_port" -gt 0 ] && [ "$local_port" -le 65535 ] || fail '端口须在1至65535之间。'
  export APP_ENV=production
  export LISTEN_ADDR="127.0.0.1:$local_port"
  export CORS_ORIGINS=''
  LOCAL_URL="http://$LISTEN_ADDR"
  printf '\n本地模式将创建可公网访问的临时HTTPS入口；使用刚配置的非默认密码，仅安排指定测试者和合成数据。\n'
  printf '%s\n' '不改系统代理/全局PATH/防火墙/电源/自启；网址会变，关闭本窗口或Ctrl+C撤回本次入口。'
  log_terminal_lifetime_notice
  printf '%s' '确认发布本次临时入口，直接回车继续；其它输入取消：'
  IFS= read -r tunnel_answer || exit 130
  [ -z "$tunnel_answer" ] || exit 130
}
# 只停止本次直接启动的进程，绝不按名字或端口杀其它服务。
cleanup_owned_processes() {
  trap - INT TERM HUP
  for owned_pid in "${OWN_TUNNEL_PID:-}" "${OWN_SERVER_PID:-}"; do
    [ -n "$owned_pid" ] || continue
    if kill -0 "$owned_pid" 2>/dev/null; then
      kill -TERM "$owned_pid" 2>/dev/null || true
    fi
  done
  cleanup_attempt=0
  while [ "$cleanup_attempt" -lt 5 ]; do
    owned_alive=0
    for owned_pid in "${OWN_TUNNEL_PID:-}" "${OWN_SERVER_PID:-}"; do
      [ -n "$owned_pid" ] || continue
      if kill -0 "$owned_pid" 2>/dev/null; then owned_alive=1; fi
    done
    [ "$owned_alive" -eq 1 ] || break
    cleanup_attempt=$((cleanup_attempt + 1))
    sleep 1
  done
  for owned_pid in "${OWN_TUNNEL_PID:-}" "${OWN_SERVER_PID:-}"; do
    [ -n "$owned_pid" ] || continue
    if kill -0 "$owned_pid" 2>/dev/null; then kill -KILL "$owned_pid" 2>/dev/null || true; fi
    wait "$owned_pid" 2>/dev/null || true
  done
  OWN_TUNNEL_PID=''
  OWN_SERVER_PID=''
  if command -v qr_expire >/dev/null 2>&1; then qr_expire; fi
}
# 中断时撤回临时入口并保留数据。
handle_local_interrupt() {
  cleanup_owned_processes
  stty echo 2>/dev/null || true
  printf '\n本次隧道与后端已停止；原配置和业务数据保留。\n'
  exit 130
}
# 此函数仅在后台子Shell调用；exec保留本次PID，清理只影响该隧道。
start_isolated_quick_child() {
  for tunnel_env_key in $(env | sed -n 's/^\(TUNNEL_[A-Za-z0-9_]*\)=.*/\1/p'); do
    unset "$tunnel_env_key" || exit 1
  done
  exec "$CLOUDFLARED_EXE" tunnel --config "$quick_config" --no-autoupdate --url "$LOCAL_URL"
}
# 启动本次后端、核实健康，再维持免费隧道。
run_local_with_tunnel() {
  ensure_transfer_tools
  occupied_remote="$(curl --silent --max-time 2 --output /dev/null --write-out '%{remote_ip}' "$LOCAL_URL/" 2>/dev/null || true)"
  if [ -n "$occupied_remote" ]; then
    fail '本地端口已有可连接服务；未复用、停止或发布该服务，请核对后重试。'
  fi
  local_server_log="$LOG_FILE.server.log"
  local_tunnel_log="$LOG_FILE.tunnel.log"
  trap handle_local_interrupt INT TERM HUP
  trap 'cleanup_owned_processes; lc_finalize' EXIT
  "$SERVER_ROOT/.runtime/bin/server" > "$local_server_log" 2>&1 &
  OWN_SERVER_PID=$!
  lc_record_process server "$OWN_SERVER_PID" || fail '无法登记后端进程身份。'
  health_attempt=0
  while [ "$health_attempt" -lt 30 ]; do
    kill -0 "$OWN_SERVER_PID" 2>/dev/null || fail "本次后端已退出；见 $local_server_log"
    if curl --fail --silent --max-time 1 "$LOCAL_URL/healthz" >/dev/null 2>&1; then
      kill -0 "$OWN_SERVER_PID" 2>/dev/null || fail '健康响应时本次后端已退出，未建立隧道。'
      break
    fi
    health_attempt=$((health_attempt + 1))
    sleep 1
  done
  [ "$health_attempt" -lt 30 ] || fail "后端健康检查超时；见 $local_server_log"
  log "本机后端健康｜$LOCAL_URL｜本次PID $OWN_SERVER_PID"
  quick_config="$(mktemp "$SERVER_ROOT/.runtime/logs/quick-config.XXXXXX")" || fail '无法建立本次空隧道配置。'
  printf '{}\n' > "$quick_config"
  start_isolated_quick_child > "$local_tunnel_log" 2>&1 &
  OWN_TUNNEL_PID=$!
  lc_record_process tunnel "$OWN_TUNNEL_PID" || fail '无法登记隧道进程身份。'
  public_url=''
  tunnel_wait=0
  tunnel_timeout="${TUNNEL_START_TIMEOUT:-45}"
  case "$tunnel_timeout" in ''|*[!0-9]*) fail 'TUNNEL_START_TIMEOUT必须为1至300秒。' ;; esac
  [ "$tunnel_timeout" -gt 0 ] && [ "$tunnel_timeout" -le 300 ] || fail 'TUNNEL_START_TIMEOUT必须为1至300秒。'
  log "临时隧道日志｜$local_tunnel_log｜正在等待随机HTTPS地址；Ctrl+C停止。"
  while kill -0 "$OWN_SERVER_PID" 2>/dev/null && kill -0 "$OWN_TUNNEL_PID" 2>/dev/null; do
    latest_public_url="$(grep -Eo 'https://[a-zA-Z0-9-]+\.trycloudflare\.com' "$local_tunnel_log" | tail -n 1 || true)"
    if [ -n "$latest_public_url" ] && [ "$latest_public_url" != "$public_url" ]; then
      public_url="$latest_public_url"
      if [ -n "$public_url" ]; then
        log "公网临时地址｜$public_url/client/｜管理端 $public_url/admin/"
        if command -v qr_display >/dev/null 2>&1; then qr_display "$public_url" '知序｜公网临时访问入口'; fi
        log_terminal_lifetime_notice
        log '地址已生成不等于公网验收；请用手机移动网络验证真实登录/写入/重读和文件权限。'
      fi
    fi
    if [ -z "$public_url" ]; then
      tunnel_wait=$((tunnel_wait + 1))
      [ "$tunnel_wait" -lt "$tunnel_timeout" ] || fail "隧道地址等待超时；检查网络/Cloudflare可达性，或按平台README改用cpolar；见 $local_tunnel_log"
    fi
    sleep 1
  done
  fail "本次后端或隧道已退出，将回收另一子进程；后端日志 $local_server_log；隧道日志 $local_tunnel_log"
}
# 根据已确认模式运行，服务器路线不建立公网入口。
run_selected_mode() {
  if [ "$DEPLOY_MODE" = local ]; then run_local_with_tunnel; else run_server; fi
}

# 初始化本脚本内嵌的恢复协议；记录原点之前先准备退出解锁。
initialize_deployment_lifecycle() {
  trap 'cleanup_owned_processes; lc_finalize' EXIT
  lc_begin || exit 1
}
# 运行目录准备完成后启用完整信号清理。
initialize_deployment_runtime() {
  initialize_runtime
  trap handle_local_interrupt INT TERM HUP
}
# 封口失败即停止，未记录的资源不能进入运行态。
seal_deployment_lifecycle() {
  lc_checkpoint || fail '无法封存部署资源归属。'
}

# 编排自述、模式选择、环境准备与本目录部署。
main() {
  show_script_intro_and_wait "$@" # 先说明影响范围并等待确认。
  check_platform # 确认前不写本系统外资源。
  check_source # 检查移植目录完整性。
  initialize_deployment_lifecycle # 先登记原点并注册退出恢复。
  initialize_deployment_runtime # 确认后创建运行目录并接入中断清理。
  select_deployment_mode # fzf明确选择，取消不准备Go或业务配置。
  initialize_business_runtime # 模式选定后建立业务目录。
  ensure_go # 复用SDK或安装工程本地SDK。
  configure_server # 初次配置账户，其后保留已有配置。
  prepare_selected_mode # 本地模式复检工具并确认本次公网访问。
  build_server # 编译单份Go源码。
  seal_deployment_lifecycle # 在启动服务前封存资源后态。
  run_selected_mode # 只启动选定的后端或后端加临时隧道。
}
main "$@"
