#!/bin/sh
# 脚本自述：
# - 按本项目部署前后清单恢复程序、配置与工程内工具；数据默认备份、验证后清源。
# - 共享或归属不明环境保留；旧部署缺少记录及外部数据库会停止，不声称已恢复。
# - 回车阅读后用fzf选择，再以默认取消菜单和空格复核；Ctrl+C或Esc取消。
# BEGIN JOBS DEPLOYMENT LIFECYCLE
# 输出当前结果；经确认后的反部署同时留下纯文本审计。
# >>> Jobs terminal style protection v1 >>>
# 临时保护当前终端配色，业务进程自行管理原有退出清理。
jobs_terminal_style_run() {
    # 无法可靠保存原色时，沿用脚本已有的纯文本约定。
    jobs_terminal_style_plain() {
        PLAIN_OUTPUT=1
        NO_COLOR=1
        FORCE_COLOR=0
        CLICOLOR=0
        ANSI_COLORS_DISABLED=1
        npm_config_color=false
        export PLAIN_OUTPUT NO_COLOR FORCE_COLOR CLICOLOR ANSI_COLORS_DISABLED npm_config_color
        if "$@"; then
            jobs_style_exit_status=0
        else
            jobs_style_exit_status=$?
        fi
        exit "$jobs_style_exit_status"
    }
    if [ ! -t 0 ] || [ ! -t 1 ] || [ -z "${TERM:-}" ] ||
       [ "${TERM:-}" = dumb ] || [ "${NO_COLOR+x}" = x ] ||
       [ "${PLAIN_OUTPUT:-0}" = 1 ] || [ "${IS_SOURCETREE_RUNTIME:-0}" = 1 ] ||
       env | LC_ALL=C grep -qiE '^(SOURCETREE|SOURCE_TREE)'; then
        if "$@"; then
            jobs_style_exit_status=0
        else
            jobs_style_exit_status=$?
        fi
        exit "$jobs_style_exit_status"
    fi
    if [ -n "${TMUX:-}${STY:-}" ]; then
        jobs_terminal_style_plain "$@"
    fi
    jobs_style_tty=$(tty 2>/dev/null) || jobs_terminal_style_plain "$@"
    if ! ps -o pgid= -o tpgid= -p "$$" 2>/dev/null |
         LC_ALL=C awk 'NF == 2 && $1 == $2 && $1 > 0 { foreground = 1 } END { exit !foreground }'; then
        jobs_terminal_style_plain "$@"
    fi
    case ${JOBS_TERMINAL_STYLE_OWNER:-} in
        ''|*[!0-9]*) ;;
        *)
            if [ "${JOBS_TERMINAL_STYLE_TTY:-}" = "$jobs_style_tty" ] &&
               kill -0 "$JOBS_TERMINAL_STYLE_OWNER" 2>/dev/null; then
                if "$@"; then
                    jobs_style_exit_status=0
                else
                    jobs_style_exit_status=$?
                fi
                exit "$jobs_style_exit_status"
            fi
            ;;
    esac
    jobs_style_stty=$(stty -g 2>/dev/null < /dev/tty) || jobs_terminal_style_plain "$@"
    jobs_style_saved=''
    jobs_style_saved_rows=''
    jobs_style_applied_rows=''
    jobs_style_changed=0
    jobs_style_applied_complete=0
    jobs_style_query_active=0
    jobs_style_recovery=''
    jobs_style_exit_status=0
    jobs_style_esc=$(printf '\033')
    jobs_style_bel=$(printf '\007')
    # 只接受本次请求对应的 RGB 响应；非协议输入使本次探测失败。
    jobs_terminal_style_query() {
        jobs_style_query_key=$1
        printf '\033]%s;?\007' "$jobs_style_query_key" > /dev/tty || return 1
        jobs_style_reply=''
        for jobs_style_attempt in 1 2 3; do
            jobs_style_piece=$(dd bs=256 count=1 2>/dev/null < /dev/tty)
            jobs_style_reply=$jobs_style_reply$jobs_style_piece
            case $jobs_style_reply in
                *"$jobs_style_bel"|*"$jobs_style_esc\\") break ;;
                '') ;;
                "$jobs_style_esc"*) ;;
                *) break ;;
            esac
        done
        case $jobs_style_reply in
            "$jobs_style_esc]$jobs_style_query_key;rgb:"*"$jobs_style_bel")
                jobs_style_rgb=${jobs_style_reply#"$jobs_style_esc]$jobs_style_query_key;rgb:"}
                jobs_style_rgb=${jobs_style_rgb%"$jobs_style_bel"}
                ;;
            "$jobs_style_esc]$jobs_style_query_key;rgb:"*"$jobs_style_esc\\")
                jobs_style_rgb=${jobs_style_reply#"$jobs_style_esc]$jobs_style_query_key;rgb:"}
                jobs_style_rgb=${jobs_style_rgb%"$jobs_style_esc\\"}
                ;;
            *) return 1 ;;
        esac
        jobs_style_normalized=$(printf '%s\n' "$jobs_style_rgb" | LC_ALL=C awk -F/ '
            NF != 3 { exit 1 }
            {
                for (i = 1; i <= 3; i++) {
                    h = tolower($i)
                    if (length(h) < 1 || length(h) > 4 || h ~ /[^0-9a-f]/) exit 1
                    n = 0
                    for (j = 1; j <= length(h); j++) n = n * 16 + index("0123456789abcdef", substr(h, j, 1)) - 1
                    value[i] = int(n * 65535 / (16 ^ length(h) - 1) + 0.5)
                }
                printf "%d/%d/%d", value[1], value[2], value[3]
            }
        ') || return 1
        [ -n "$jobs_style_normalized" ]
    }
    # 查询可用不代表终端允许改色，按目标值核对实际生效结果。
    jobs_terminal_style_accepts_target() {
        jobs_style_requested_hex=''
        case $1 in
            10|12) jobs_style_requested_hex=ffffff ;;
            11) jobs_style_requested_hex=000000 ;;
            '4;'*)
                jobs_style_requested_index=0
                for jobs_style_requested_color in 000000 ff5f56 5fd787 ffd75f 5fafff d787ff 5fd7ff eeeeee 9e9e9e ff8787 87ffaf ffff87 87bfff ffafff afffff ffffff; do
                    if [ "4;$jobs_style_requested_index" = "$1" ]; then
                        jobs_style_requested_hex=$jobs_style_requested_color
                        break
                    fi
                    jobs_style_requested_index=$((jobs_style_requested_index + 1))
                done
                ;;
        esac
        [ -n "$jobs_style_requested_hex" ] || return 1
        printf '%s|%s\n' "$jobs_style_normalized" "$jobs_style_requested_hex" | LC_ALL=C awk -F'|' '
            function hexbyte(h) {
                return (index("0123456789abcdef", substr(h, 1, 1)) - 1) * 16 + index("0123456789abcdef", substr(h, 2, 1)) - 1
            }
            {
                if (split($1, actual, "/") != 3 || length($2) != 6) exit 1
                for (i = 1; i <= 3; i++) {
                    difference = actual[i] - hexbyte(substr($2, i * 2 - 1, 2)) * 257
                    if (difference < -255 || difference > 255) exit 1
                }
            }
        '
    }
    # 检测到后续改色时只恢复仍由本次保护持有的项，保留独立恢复入口。
    jobs_terminal_style_cleanup() {
        jobs_style_result=$1
        trap '' HUP INT TERM
        if [ "$jobs_style_query_active" = 1 ]; then
            stty "$jobs_style_stty" 2>/dev/null < /dev/tty || :
            jobs_style_query_active=0
        fi
        if [ "$jobs_style_changed" = 1 ]; then
            jobs_style_cleanup_ok=0
            jobs_style_conflicts=''
            jobs_style_restore_safe=''
            if [ "$jobs_style_applied_complete" = 1 ]; then
                jobs_style_stty=$(stty -g 2>/dev/null < /dev/tty) || jobs_style_stty=''
                if [ -n "$jobs_style_stty" ] && stty -echo -icanon min 0 time 1 2>/dev/null < /dev/tty; then
                    jobs_style_query_active=1
                    jobs_style_cleanup_ok=1
                    while IFS='|' read -r jobs_style_key jobs_style_expected jobs_style_original; do
                        [ -n "$jobs_style_key" ] || continue
                        if ! jobs_terminal_style_query "$jobs_style_key"; then
                            jobs_style_cleanup_ok=0
                            break
                        fi
                        if [ "$jobs_style_normalized" = "$jobs_style_expected" ]; then
                            jobs_style_restore_safe=$jobs_style_restore_safe$jobs_style_original
                        else
                            jobs_style_conflicts="$jobs_style_conflicts $jobs_style_key"
                        fi
                    done <<JOBS_STYLE_APPLIED
$jobs_style_applied_rows
JOBS_STYLE_APPLIED
                    stty "$jobs_style_stty" 2>/dev/null < /dev/tty || jobs_style_cleanup_ok=0
                    jobs_style_query_active=0
                fi
            fi
            if [ "$jobs_style_cleanup_ok" = 1 ] && printf '%s\033[0m' "$jobs_style_restore_safe" > /dev/tty; then
                if [ -z "$jobs_style_conflicts" ]; then
                    rm -f "$jobs_style_recovery"
                    rmdir "${jobs_style_recovery%/*}" 2>/dev/null || :
                else
                    printf '检测到运行期间的配色变更，已保留这些项：%s\n' "$jobs_style_conflicts" >&2
                    printf '确认要覆盖后续改色时才使用恢复入口：sh "%s"\n' "$jobs_style_recovery" >&2
                    [ "$jobs_style_result" -ne 0 ] || jobs_style_result=1
                fi
            else
                printf '终端配色未能安全自动恢复；确认覆盖当前配色后可运行：sh "%s"\n' "$jobs_style_recovery" >&2
                [ "$jobs_style_result" -ne 0 ] || jobs_style_result=1
            fi
        fi
        if [ "${2:-}" = continue ]; then
            jobs_style_cleanup_status=$jobs_style_result
            return 0
        fi
        exit "$jobs_style_result"
    }
    trap 'jobs_terminal_style_cleanup "$jobs_style_exit_status"' 0
    trap 'jobs_style_exit_status=129; exit 129' HUP
    trap 'jobs_style_exit_status=130; exit 130' INT
    trap 'jobs_style_exit_status=143; exit 143' TERM
    if ! stty -echo -icanon min 0 time 1 2>/dev/null < /dev/tty; then
        jobs_terminal_style_plain "$@"
    fi
    jobs_style_query_active=1
    jobs_style_probe_ok=1
    for jobs_style_key in 10 11 12 '4;0' '4;1' '4;2' '4;3' '4;4' '4;5' '4;6' '4;7' '4;8' '4;9' '4;10' '4;11' '4;12' '4;13' '4;14' '4;15'; do
        if ! jobs_terminal_style_query "$jobs_style_key"; then
            jobs_style_probe_ok=0
            break
        fi
        jobs_style_saved=$jobs_style_saved$jobs_style_reply
        jobs_style_saved_rows="$jobs_style_saved_rows$jobs_style_key|$jobs_style_reply
"
    done
    stty "$jobs_style_stty" 2>/dev/null < /dev/tty || { jobs_style_exit_status=1; exit 1; }
    jobs_style_query_active=0
    if [ "$jobs_style_probe_ok" != 1 ]; then
        printf '%s\n' '终端不支持完整配色保存，或启动时收到其它输入；保留原配色并使用纯文本。' >&2
        jobs_terminal_style_plain "$@"
    fi
    jobs_style_recovery_dir=$(umask 077; mktemp -d "${TMPDIR:-/tmp}/jobs-terminal-style.XXXXXX") || jobs_terminal_style_plain "$@"
    jobs_style_recovery=$jobs_style_recovery_dir/restore.sh
    if ! (umask 077; {
        printf '#!/bin/sh\n'
        printf '[ -t 0 ] && [ "$(tty)" = '\''%s'\'' ] || { printf '\''请在原终端运行恢复入口。\\n'\'' >&2; exit 1; }\n' "$jobs_style_tty"
        printf 'printf '\''本操作会覆盖此终端当前配色。确认恢复脚本启动前的配色，请输入 YES：'\'' >&2\n'
        printf 'IFS= read -r jobs_restore_choice\n[ "$jobs_restore_choice" = YES ] || exit 1\n'
        printf 'printf '\''%%s\\033[0m'\'' '\''%s'\'' > /dev/tty\n' "$jobs_style_saved"
    } > "$jobs_style_recovery"); then
        printf '%s\n' '无法保存终端配色恢复入口；保留原配色并使用纯文本。' >&2
        jobs_terminal_style_plain "$@"
    fi
    printf '正在准备本次终端临时配色；强退后恢复入口：sh "%s"\n' "$jobs_style_recovery" >&2
    jobs_style_changed=1
    printf '\033]10;#ffffff\007\033]11;#000000\007\033]12;#ffffff\007' > /dev/tty
    jobs_style_index=0
    for jobs_style_color in 000000 ff5f56 5fd787 ffd75f 5fafff d787ff 5fd7ff eeeeee 9e9e9e ff8787 87ffaf ffff87 87bfff ffafff afffff ffffff; do
        printf '\033]4;%s;#%s\007' "$jobs_style_index" "$jobs_style_color" > /dev/tty
        jobs_style_index=$((jobs_style_index + 1))
    done
    printf '\033[0m' > /dev/tty
    jobs_style_stty=$(stty -g 2>/dev/null < /dev/tty) || { jobs_style_exit_status=1; exit 1; }
    stty -echo -icanon min 0 time 1 2>/dev/null < /dev/tty || { jobs_style_exit_status=1; exit 1; }
    jobs_style_query_active=1
    jobs_style_probe_ok=1
    jobs_style_targets_ok=1
    while IFS='|' read -r jobs_style_key jobs_style_original; do
        [ -n "$jobs_style_key" ] || continue
        if ! jobs_terminal_style_query "$jobs_style_key"; then
            jobs_style_probe_ok=0
            break
        fi
        jobs_style_applied_rows="$jobs_style_applied_rows$jobs_style_key|$jobs_style_normalized|$jobs_style_original
"
        if ! jobs_terminal_style_accepts_target "$jobs_style_key"; then
            jobs_style_targets_ok=0
        fi
    done <<JOBS_STYLE_ORIGINAL
$jobs_style_saved_rows
JOBS_STYLE_ORIGINAL
    stty "$jobs_style_stty" 2>/dev/null < /dev/tty || { jobs_style_exit_status=1; exit 1; }
    jobs_style_query_active=0
    if [ "$jobs_style_probe_ok" != 1 ]; then
        printf '%s\n' '无法核实本次临时配色，已停止启动业务。' >&2
        jobs_style_exit_status=1
        exit 1
    fi
    jobs_style_applied_complete=1
    if [ "$jobs_style_targets_ok" != 1 ]; then
        jobs_terminal_style_cleanup 0 continue
        jobs_style_changed=0
        if [ "$jobs_style_cleanup_status" != 0 ]; then
            jobs_style_exit_status=1
            exit 1
        fi
        trap 'jobs_style_exit_status=129; exit 129' HUP
        trap 'jobs_style_exit_status=130; exit 130' INT
        trap 'jobs_style_exit_status=143; exit 143' TERM
        printf '%s\n' '终端未接受本次配色，已恢复原配色并使用纯文本。' >&2
        jobs_terminal_style_plain "$@"
    fi
    printf '%s\n' '本次终端已临时使用黑底白字。' >&2
    JOBS_TERMINAL_STYLE_TTY=$jobs_style_tty
    JOBS_TERMINAL_STYLE_OWNER=$$
    export JOBS_TERMINAL_STYLE_TTY JOBS_TERMINAL_STYLE_OWNER
    if "$@"; then
        jobs_style_exit_status=0
    else
        jobs_style_exit_status=$?
    fi
    exit "$jobs_style_exit_status"
}
# 仅监督直接执行的入口；被 source 时不切换配色、不重新执行业务。
jobs_terminal_style_bootstrap() {
    jobs_style_bootstrap_script=$1
    shift
    if [ -n "${ZSH_VERSION:-}" ]; then
        case ${ZSH_EVAL_CONTEXT:-} in
            *:file|*:file:*) return 0 ;;
        esac
    elif [ -n "${BASH_VERSION:-}" ] && [ "${BASH_SOURCE:-$jobs_style_bootstrap_script}" != "$jobs_style_bootstrap_script" ]; then
        return 0
    fi
    if [ "${JOBS_TERMINAL_STYLE_REEXEC:-}" = "$jobs_style_bootstrap_script" ]; then
        unset JOBS_TERMINAL_STYLE_REEXEC
        return 0
    fi
    if [ ! -t 0 ] || [ ! -t 1 ] || [ -z "${TERM:-}" ] ||
       [ "${TERM:-}" = dumb ] || [ "${NO_COLOR+x}" = x ] ||
       [ "${PLAIN_OUTPUT:-0}" = 1 ] || [ "${IS_SOURCETREE_RUNTIME:-0}" = 1 ] ||
       [ -n "${TMUX:-}${STY:-}" ] ||
       env | LC_ALL=C grep -qiE '^(SOURCETREE|SOURCE_TREE)'; then
        return 0
    fi
    case ${JOBS_TERMINAL_STYLE_OWNER:-} in
        ''|*[!0-9]*) ;;
        *)
            if kill -0 "$JOBS_TERMINAL_STYLE_OWNER" 2>/dev/null &&
               [ "${JOBS_TERMINAL_STYLE_TTY:-}" = "$(tty 2>/dev/null)" ]; then
                return 0
            fi
            ;;
    esac
    JOBS_TERMINAL_STYLE_REEXEC=$jobs_style_bootstrap_script
    export JOBS_TERMINAL_STYLE_REEXEC
    jobs_terminal_style_run /bin/sh "$jobs_style_bootstrap_script" "$@"
    jobs_style_bootstrap_result=$?
    exit "$jobs_style_bootstrap_result"
}
jobs_terminal_style_bootstrap "$0" "$@"
# <<< Jobs terminal style protection v1 <<<

# JOBS_INPUT_CHOICE_STYLE_BEGIN
# 只展示提示选项；不读取答案、不改变默认值、返回码或业务环境。
jobs_prompt_color_ready() {
  [ -z "${NO_COLOR+x}" ] && [ -n "${TERM:-}" ] && [ "${TERM:-}" != dumb ] &&
    [ "${PLAIN_OUTPUT:-0}" != 1 ] && [ "${IS_SOURCETREE_RUNTIME:-0}" != 1 ]
}
# 原生 awk 分段着色；任意/非空输入优先，括号内外沿用同一个选项。
jobs_prompt_format() {
  /usr/bin/awk -v color="${1:-0}" -v lines="${2:-0}" -v keep="${3:-0}" '
    function typedEnter(value, start, prefix) {
      prefix = substr(value, 1, start - 1)
      gsub(/[“”‘’「」『』"]/, "", prefix)
      gsub(sprintf("%c", 39), "", prefix)
      if (prefix ~ /(空格|[Ss][Pp][Aa][Cc][Ee])[[:space:]]*(后|再|并|[Tt][Hh][Ee][Nn])?[[:space:]]*$/) return 1
      return prefix ~ /(输入|键入|填写|[Tt]ype)[^；;|]*[[:alnum:]_+-]+[[:space:]]*(后|再|并)?[[:space:]]*$/
    }
    function greenPosition(value, token, start) {
      if (match(value, /(直接|仅|只需|只|按下|按)?[[:space:]]*(回车|回車)/)) {
        start = RSTART
        return typedEnter(value, start) ? 0 : start
      }
      if (!match(value, /(^|[^[:alnum:]_])([Ee][Nn][Tt][Ee][Rr]|[Rr][Ee][Tt][Uu][Rr][Nn])([^[:alnum:]_]|$)/)) return 0
      start = RSTART
      token = substr(value, RSTART, RLENGTH)
      match(token, /[Ee][Nn][Tt][Ee][Rr]|[Rr][Ee][Tt][Uu][Rr][Nn]/)
      start += RSTART - 1
      return typedEnter(value, start) ? 0 : start
    }
    function segment(value, inherited, start, kind, prefix, body, red, green, connector, left, right, splitAt) {
      if (value == "") return value
      kind = inherited
      start = 1
      if (!kind) {
        if (match(value, /(输入)?(任意|任何)(非空)?(字符|内容|输入|键)|非空(字符|内容|输入)?|其它输入|其他输入|[Tt]ype (anything|any[^ ]*)|[Pp]ress any key/)) {
          red = RSTART
        }
        green = greenPosition(value)
        if (red && green && green < red) {
          left = substr(value, 1, red - 1)
          right = substr(value, red)
          connector = ""
          if (match(left, /(或者|或)[[:space:]]*$/)) {
            connector = substr(left, RSTART)
            left = substr(left, 1, RSTART - 1)
          }
          return segment(left, 0) connector segment(right, 31)
        }
        if (red && green && red < green && match(value, /或[[:space:]]*(直接|仅|只需|只|按下|按)?(回车|回車)/)) {
          splitAt = RSTART
          return segment(substr(value, 1, splitAt - 1), 31) "或" segment(substr(value, splitAt + length("或")), 0)
        }
        if (red) {
          kind = 31
          start = red
        } else if (green) {
          kind = 32
          start = green
        }
      }
      if (!kind || !color) return value
      prefix = substr(value, 1, start - 1)
      body = substr(value, start)
      return prefix esc "[1;" kind "m" body esc "[0m"
    }
    function render(value, output, part, boundary, inherited, kind, consumed, depth, original) {
      original = value
      gsub(esc "\\[[0-9;]*m", "", value)
      if (color && keep && !greenPosition(value) && value !~ /(任意|任何|非空|其它输入|其他输入|[Tt]ype (anything|any[^ ]*)|[Pp]ress any key)/) return original
      output = ""
      inherited = 0
      depth = 0
      while (match(value, /[；;\/|，,、？?：:=＝（）()\[\]【】]/)) {
        part = substr(value, 1, RSTART - 1)
        boundary = substr(value, RSTART, RLENGTH)
        consumed = RSTART + RLENGTH
        output = output segment(part, inherited) boundary
        if (boundary ~ /[（(\[【]/) {
          depth++
          if (part ~ /(任意|任何|非空|其它输入|其他输入|[Tt]ype (anything|any[^ ]*)|[Pp]ress any key)/) inherited = 31
          else if (greenPosition(part)) inherited = 32
        } else if (boundary ~ /[）)\]】]/) {
          if (depth) depth--
        } else if (boundary ~ /[：:=＝]/) {
          if (!inherited) {
            if (part ~ /(任意|任何|非空|其它输入|其他输入)/) inherited = 31
            else if (greenPosition(part)) inherited = 32
          }
        } else if (!depth) inherited = 0
        value = substr(value, consumed)
      }
      return output segment(value, inherited)
    }
    BEGIN { esc = sprintf("%c", 27); first = 1 }
    {
      if (lines == 2) {
        if (!first) printf "%s\n", render(pending)
        pending = $0
        first = 0
        next
      }
      if (!lines && !first) printf "\n"
      printf "%s", render($0)
      if (lines) printf "\n"
      first = 0
    }
    END {
      if (lines == 2 && !first) {
        sub(sprintf("%c", 1) "$", "", pending)
        printf "%s", render(pending)
      }
    }
  '
}
# read 的命令替换会使 stdout 成为管道，按输入与提示所在 stderr 判断终端。
jobs_prompt_render() {
  local jobs_prompt_color=0
  if [ -t 0 ] && [ -t 2 ] && jobs_prompt_color_ready; then jobs_prompt_color=1; fi
  printf "%s" "$1" | jobs_prompt_format "$jobs_prompt_color" 0
}
# 仅放在显示链末端；tee 在此函数之前接收纯文本，不把 ANSI 写入日志。
jobs_prompt_stream() {
  local jobs_prompt_color=0
  if [ -t 1 ] && jobs_prompt_color_ready; then jobs_prompt_color=1; fi
  jobs_prompt_format "$jobs_prompt_color" 1 1
}
# 显示管道保留原末尾换行；只删除本轮追加的最后一个结束标记。
jobs_prompt_filter() {
  local jobs_prompt_color=0
  if [ -t 1 ] && jobs_prompt_color_ready; then jobs_prompt_color=1; fi
  { /bin/cat; printf '\001'; } | jobs_prompt_format "$jobs_prompt_color" 2 1
}
# 仅包装原 printf/echo/print 展示，原参数、尾换行与显示命令退出码保持不变。
jobs_prompt_output() {
  local jobs_prompt_status=0 jobs_prompt_stderr=0 jobs_prompt_arg="" jobs_prompt_previous=""
  if [ "${1:-}" = print ]; then
    for jobs_prompt_arg in "$@"; do
      case "$jobs_prompt_arg" in -?*u2*|-u2) jobs_prompt_stderr=1 ;; esac
      if [ "$jobs_prompt_previous" = -u ] && [ "$jobs_prompt_arg" = 2 ]; then jobs_prompt_stderr=1; fi
      jobs_prompt_previous="$jobs_prompt_arg"
      [ "$jobs_prompt_arg" != -- ] || break
    done
  fi
  if [ -n "${ZSH_VERSION:-}" ]; then
    if [ "$jobs_prompt_stderr" = 1 ]; then
      "$@" 2>&1 | jobs_prompt_filter >&2
      jobs_prompt_status=$(( ${pipestatus[1]} != 0 ? ${pipestatus[1]} : ${pipestatus[2]} ))
    else
      "$@" | jobs_prompt_filter
      jobs_prompt_status=$(( ${pipestatus[1]} != 0 ? ${pipestatus[1]} : ${pipestatus[2]} ))
    fi
  elif [ -n "${BASH_VERSION:-}" ]; then
    "$@" | jobs_prompt_filter
    jobs_prompt_status=$(( ${PIPESTATUS[0]} != 0 ? ${PIPESTATUS[0]} : ${PIPESTATUS[1]} ))
  else
    "$@" | jobs_prompt_filter
    jobs_prompt_status=$?
  fi
  return "$jobs_prompt_status"
}
# 仅替换日志 primitive 的 tee：磁盘同步追加纯文，终端保留非选项原色。
jobs_prompt_tee() {
  local jobs_prompt_log="$1" jobs_prompt_line="" jobs_prompt_newline=0
  while :; do
    jobs_prompt_line=""
    if IFS= read -r jobs_prompt_line; then jobs_prompt_newline=1; else jobs_prompt_newline=0; [ -n "$jobs_prompt_line" ] || break; fi
    if [ "$jobs_prompt_newline" = 1 ]; then
      { printf '%s\n' "$jobs_prompt_line"; printf '\001'; } | jobs_prompt_format 0 2 >> "$jobs_prompt_log" || return $?
      printf '%s\n' "$jobs_prompt_line" | jobs_prompt_filter || return $?
    else
      { printf '%s' "$jobs_prompt_line"; printf '\001'; } | jobs_prompt_format 0 2 >> "$jobs_prompt_log" || return $?
      printf '%s' "$jobs_prompt_line" | jobs_prompt_filter || return $?
    fi
  done
}
# JOBS_INPUT_CHOICE_STYLE_END

lc_message() {
  jobs_prompt_output printf '%s\n' "$*" >&2
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
  local lc_base="$1" lc_output="$2" lc_scope="$3" lc_scan lc_full lc_rel lc_parent lc_kind lc_digest
  lc_scan="$lc_output.paths"
  : > "$lc_output" || return 1
  : > "$lc_scan" || return 1
  case "$lc_scope" in
    '.runtime .tools') set -- .runtime .tools;;
    data) set -- data;;
    runtime-selected) shift 3;;
    *) return 1;;
  esac
  for lc_rel do
    [ -n "$lc_rel" ] || continue
    if [ "$lc_scope" = runtime-selected ]; then
      case "$lc_rel" in .runtime/*) ;; *) lc_error '本轮运行资源越出 .runtime，保留原清单。'; return 1;; esac
      lc_safe_relative "$lc_rel" || { lc_error '本轮运行资源路径不安全，保留原清单。'; return 1; }
      lc_parent="$lc_rel"
      while :; do
        [ ! -L "$lc_base/$lc_parent" ] || { lc_error '本轮运行资源或祖先为符号链接，保留原清单。'; return 1; }
        case "$lc_parent" in */*) lc_parent="${lc_parent%/*}";; *) break;; esac
      done
    fi
    [ ! -L "$lc_base/$lc_rel" ] || { lc_error '受控目录为符号链接。'; return 1; }
    [ -e "$lc_base/$lc_rel" ] || continue
    [ -z "$(find "$lc_base/$lc_rel" \( -name "*$LC_NL*" -o -name "*$LC_TAB*" \) -print)" ] || { lc_error '文件名含换行或制表符，保持原状。'; return 1; }
    find "$lc_base/$lc_rel" -print >> "$lc_scan" || return 1
  done
  if [ "$lc_scope" = runtime-selected ]; then
    LC_ALL=C sort -u "$lc_scan" -o "$lc_scan" || return 1
  fi
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
    lc_log_rel="${LOG_FILE#"$SERVER_ROOT/"}"
    lc_quick_rel="${quick_config:-}"
    lc_quick_rel="${lc_quick_rel#"$SERVER_ROOT/"}"
    lc_qr_rel="${QR_OUTPUT:-}"
    lc_qr_rel="${lc_qr_rel#"$SERVER_ROOT/"}"
    lc_manifest "$SERVER_ROOT" "$LC_STATE/finalize.tsv" runtime-selected \
      "$lc_log_rel" "$lc_log_rel.server.log" "$lc_log_rel.tunnel.log" \
      "$lc_quick_rel" "$lc_qr_rel" || return 1
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
  jobs_prompt_output printf '已了解范围，回车继续；其它输入取消：' >&2
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
  jobs_prompt_output printf '按一次空格后回车复核授权；其它输入取消：' >&2
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
# 执行本脚本内嵌的生命周期流程，统一展示自述、选择与恢复。
show_script_intro_and_wait() {
  SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)" || exit 1
  DEPLOY_ROOT="$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd -P)" || exit 1
  PROJECT_ROOT="$(CDPATH= cd -- "$DEPLOY_ROOT/.." && pwd -P)" || exit 1
  SERVER_ROOT="$PROJECT_ROOT/代码/后端/后端代码"
  PLATFORM_ID='FreeBSD'
  [ "$(uname -s)" = FreeBSD ] || { printf '%s\n' '请使用当前系统对应入口。' >&2; exit 1; }
  lc_undeploy_main "$@"
}
# 编排本脚本内嵌的反部署实现。
main() {
  show_script_intro_and_wait "$@" # 复用固定自述、只读检查、数据选择与恢复。
}
main "$@"
