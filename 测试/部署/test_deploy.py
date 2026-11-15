"""Read-only/sandbox deployment regressions, never installs system packages."""
# JOBS_TERMINAL_STYLE_GUARD_V1_BEGIN
# 保存与恢复由监督进程负责；导入本模块时不接管终端。
def _jobs_terminal_style_bootstrap_v1():
    import os as _os
    import base64 as _base64
    import json as _json
    import shutil as _shutil
    import subprocess as _subprocess
    import sys as _sys
    import tempfile as _tempfile

    _entry = _os.path.abspath(__file__)
    if _os.environ.get("JOBS_TERMINAL_STYLE_REEXEC") == _entry:
        _os.environ.pop("JOBS_TERMINAL_STYLE_REEXEC", None)
        return
    if (getattr(_sys, "frozen", False) or not _sys.stdin or not _sys.stdout
            or not _sys.stdin.isatty() or not _sys.stdout.isatty()
            or "NO_COLOR" in _os.environ
            or _os.environ.get("PLAIN_OUTPUT") == "1"
            or _os.environ.get("IS_SOURCETREE_RUNTIME") == "1"
            or any(_key.upper().startswith(("SOURCETREE", "SOURCE_TREE"))
                   for _key in _os.environ)):
        return
    if _os.name != "nt" and (_os.environ.get("TERM", "") in ("", "dumb")
                             or _os.environ.get("TMUX") or _os.environ.get("STY")):
        return
    _original = getattr(_sys, "orig_argv", None)
    _module_start = False
    for _argument in list(_original[1:]) if _original else []:
        if _argument == "--" or _os.path.abspath(_argument) == _entry:
            break
        if _argument in ("-c", "-m"):
            _module_start = True
            break
    if _module_start:
        _os.environ.update(NO_COLOR="1", PLAIN_OUTPUT="1", FORCE_COLOR="0", CLICOLOR="0")
        return
    _command = [_sys.executable] + (list(_original[1:]) if _original else list(_sys.argv))
    _environment = _os.environ.copy()
    _environment["JOBS_TERMINAL_STYLE_REEXEC"] = _entry
    _shell_core = r"""# 临时保护当前终端配色，业务进程自行管理原有退出清理。
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
"""
    _powershell_core = r"""$__jobsTerminalCommand = @($args)
# BEGIN JOBS_TERMINAL_STYLE_V1 - session-only colors; no profile or registry changes.
function New-JobsTerminalStyleState {
    if ($PSVersionTable.PSVersion.Major -lt 5) { return @{ JobsTerminalPlainFallback = $true; Before = @{} } }
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or $Host.Name -ne 'ConsoleHost') { return $null }
    if ([Console]::IsInputRedirected -or [Console]::IsOutputRedirected -or [Console]::IsErrorRedirected) { return $null }
    if ((Test-Path Env:NO_COLOR) -or $env:TERM -ieq 'dumb' -or $env:PLAIN_OUTPUT -eq '1') { return $null }
    foreach ($key in [Environment]::GetEnvironmentVariables().Keys) {
        if ([string]$key -match '^(?i:SOURCE_?TREE)') { return $null }
    }
    if (-not ('Jobs.TerminalStyleV1.Native' -as [type])) {
        try {
        Add-Type -ErrorAction Stop -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;
namespace Jobs.TerminalStyleV1 {
    public static class Native {
        [StructLayout(LayoutKind.Explicit, Size=20, CharSet=CharSet.Unicode)]
        public struct InputRecord {
            [FieldOffset(0)] public ushort Kind;
            [FieldOffset(4)] public int Down;
            [FieldOffset(8)] public ushort Repeat;
            [FieldOffset(10)] public ushort Key;
            [FieldOffset(12)] public ushort Scan;
            [FieldOffset(14)] public char Character;
            [FieldOffset(16)] public uint Modifiers;
        }
        [DllImport("kernel32.dll")] static extern IntPtr GetStdHandle(int n);
        [DllImport("kernel32.dll")] static extern IntPtr GetConsoleWindow();
        [DllImport("kernel32.dll")] static extern bool GetConsoleMode(IntPtr h, out uint mode);
        [DllImport("kernel32.dll")] static extern bool SetConsoleMode(IntPtr h, uint mode);
        [DllImport("kernel32.dll")] static extern uint WaitForSingleObject(IntPtr h, uint milliseconds);
        [DllImport("kernel32.dll")] static extern bool GetNumberOfConsoleInputEvents(IntPtr h, out uint count);
        [DllImport("kernel32.dll", CharSet=CharSet.Unicode, ExactSpelling=true)] static extern bool ReadConsoleInputW(IntPtr h, [Out] InputRecord[] records, uint count, out uint read);
        [DllImport("kernel32.dll", CharSet=CharSet.Unicode, ExactSpelling=true)] static extern bool WriteConsoleInputW(IntPtr h, InputRecord[] records, uint count, out uint written);
        const string OwnerName = "JOBS_TERMINAL_STYLE_WINDOWS_OWNER";
        static readonly string[] Keys = { "10", "11", "4;0", "4;1", "4;2", "4;3", "4;4", "4;5", "4;6", "4;7", "4;8", "4;9", "4;10", "4;11", "4;12", "4;13", "4;14", "4;15" };
        static readonly string[] Hex = { "000000", "ff5f56", "5fd787", "ffd75f", "5fafff", "d787ff", "5fd7ff", "eeeeee", "9e9e9e", "ff8787", "87ffaf", "ffff87", "87bfff", "ffafff", "afffff", "ffffff" };
        static readonly Regex Reply = new Regex("\\x1b\\](?<key>10|11|4;[0-9]{1,2});(?<rgb>rgb:[0-9a-f]{1,4}/[0-9a-f]{1,4}/[0-9a-f]{1,4})(?:\\x07|\\x1b\\\\)", RegexOptions.IgnoreCase);
        public sealed class State {
            public IntPtr Input, Output;
            public uint OutputMode;
            public ConsoleColor Foreground, Background;
            public Dictionary<string,string> Original, Applied;
            public string Owner, PreviousOwner, Recovery;
            public bool Active, ModeChanged, Fallback;
            public Dictionary<string,string> EnvironmentBefore = new Dictionary<string,string>();
        }
        static string Escape(string key, string value) { return "\x1b]" + key + ";" + value + "\x07"; }
        static string Rgb(string hex) { return "rgb:" + hex.Substring(0,2) + "/" + hex.Substring(2,2) + "/" + hex.Substring(4,2); }
        static string Normal(string rgb) {
            string[] parts = rgb.Substring(4).Split('/');
            for (int n=0; n<3; n++) {
                int maximum = (1 << (4 * parts[n].Length)) - 1;
                int value = Convert.ToInt32(parts[n],16);
                parts[n] = ((value * 65535L + maximum/2) / maximum).ToString("x4");
            }
            return String.Join("/",parts);
        }
        // Preserve unrelated key/window records instead of consuming user input during color queries.
        static Dictionary<string,string> Query(State state) {
            uint pending;
            if (!GetNumberOfConsoleInputEvents(state.Input,out pending) || pending != 0) { return null; }
            StringBuilder commands = new StringBuilder();
            foreach (string key in Keys) { commands.Append(Escape(key,"?")); }
            Console.Write(commands.ToString());
            List<InputRecord> records = new List<InputRecord>();
            List<int> characterIndices = new List<int>();
            StringBuilder text = new StringBuilder();
            Dictionary<string,string> result = new Dictionary<string,string>();
            Stopwatch timer = Stopwatch.StartNew();
            try {
                while (timer.ElapsedMilliseconds < 600) {
                    if (result.Count == Keys.Length && GetNumberOfConsoleInputEvents(state.Input,out pending) && pending == 0) { break; }
                    if (WaitForSingleObject(state.Input,20) != 0) { continue; }
                    InputRecord[] item = new InputRecord[1]; uint read;
                    if (!ReadConsoleInputW(state.Input,item,1,out read) || read != 1) { break; }
                    int index = -1;
                    if (item[0].Kind == 1 && item[0].Character != '\0') {
                        if (item[0].Down != 0) { index = text.Length; text.Append(item[0].Character); }
                        else if (text.Length != 0 && text[text.Length-1] == item[0].Character) { index = text.Length-1; }
                    }
                    records.Add(item[0]); characterIndices.Add(index);
                    foreach (Match match in Reply.Matches(text.ToString())) {
                        string key = match.Groups["key"].Value;
                        if (Array.IndexOf(Keys,key) >= 0) { result[key] = match.Groups["rgb"].Value; }
                    }
                }
            } finally {
                bool[] used = new bool[text.Length];
                foreach (Match match in Reply.Matches(text.ToString())) {
                    for (int n=match.Index; n<match.Index+match.Length; n++) { used[n] = true; }
                }
                List<InputRecord> replay = new List<InputRecord>();
                for (int n=0; n<records.Count; n++) {
                    int index = characterIndices[n];
                    if (index < 0 || !used[index]) { replay.Add(records[n]); }
                }
                if (replay.Count != 0) {
                    uint written;
                    if (!WriteConsoleInputW(state.Input,replay.ToArray(),(uint)replay.Count,out written) || written != replay.Count) {
                        Console.Error.WriteLine("[Jobs] Could not replay terminal input; color protection is unavailable.");
                        result.Clear();
                    }
                }
            }
            return result.Count == Keys.Length ? result : null;
        }
        static void Plain(State state) {
            foreach (string key in new string[] { "NO_COLOR", "PLAIN_OUTPUT", "FORCE_COLOR", "CLICOLOR", "ANSI_COLORS_DISABLED" }) {
                state.EnvironmentBefore[key] = Environment.GetEnvironmentVariable(key);
                Environment.SetEnvironmentVariable(key, key == "FORCE_COLOR" || key == "CLICOLOR" ? "0" : "1");
            }
            state.Fallback = true;
        }
        public static void Enter(State state) {
            try {
                state.Input = GetStdHandle(-10); state.Output = GetStdHandle(-11);
                uint inputMode;
                if (!GetConsoleMode(state.Input,out inputMode) || !GetConsoleMode(state.Output,out state.OutputMode)) { Plain(state); return; }
                IntPtr window = GetConsoleWindow();
                if (window == IntPtr.Zero) { Plain(state); return; }
                string identity = window.ToInt64().ToString("x");
                state.PreviousOwner = Environment.GetEnvironmentVariable(OwnerName);
                if (!String.IsNullOrEmpty(state.PreviousOwner)) {
                    string[] owner = state.PreviousOwner.Split(':');
                    int pid; long started;
                    if (owner.Length == 3 && owner[0] == identity && Int32.TryParse(owner[1],out pid) && Int64.TryParse(owner[2],out started)) {
                        try { if (Process.GetProcessById(pid).StartTime.ToUniversalTime().Ticks == started) { return; } } catch {}
                    }
                }
                state.Foreground = Console.ForegroundColor; state.Background = Console.BackgroundColor;
                if ((state.OutputMode & 4) == 0) {
                    if (!SetConsoleMode(state.Output,state.OutputMode | 4)) { Plain(state); return; }
                    state.ModeChanged = true;
                }
                state.Original = Query(state);
                if (state.Original == null) { Restore(state); Plain(state); return; }
                state.Applied = new Dictionary<string,string>();
                state.Applied["10"] = "rgb:ff/ff/ff"; state.Applied["11"] = "rgb:00/00/00";
                for (int n=0; n<16; n++) { state.Applied["4;"+n] = Rgb(Hex[n]); }
                StringBuilder restore = new StringBuilder();
                foreach (string key in Keys) { restore.Append(Escape(key,state.Original[key])); }
                string encoded = Convert.ToBase64String(Encoding.UTF8.GetBytes(restore.ToString()));
                state.Recovery = Path.Combine(Path.GetTempPath(),"JobsTerminalStyle-"+Process.GetCurrentProcess().Id+"-"+Guid.NewGuid().ToString("N")+".ps1");
                string manual = "# Restore only the session colors saved by this Jobs script.\r\n"+
                    "if ([Console]::IsOutputRedirected) { throw 'Run in the original console.' }\r\n"+
                    "Add-Type -Namespace Jobs -Name RecoveryConsole -MemberDefinition '[System.Runtime.InteropServices.DllImport(\"kernel32.dll\")] public static extern System.IntPtr GetStdHandle(int n); [System.Runtime.InteropServices.DllImport(\"kernel32.dll\")] public static extern bool GetConsoleMode(System.IntPtr h, out uint m); [System.Runtime.InteropServices.DllImport(\"kernel32.dll\")] public static extern bool SetConsoleMode(System.IntPtr h, uint m);'\r\n"+
                    "$h = [Jobs.RecoveryConsole]::GetStdHandle(-11); [uint32]$m = 0\r\n"+
                    "if (-not [Jobs.RecoveryConsole]::GetConsoleMode($h, [ref]$m)) { throw 'Run in the original console.' }\r\n"+
                    "try {\r\nif (-not [Jobs.RecoveryConsole]::SetConsoleMode($h, ($m -bor 4))) { throw 'Cannot enable terminal recovery.' }\r\n"+
                    "[Console]::Write([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('"+encoded+"')))\r\n"+
                    "[Console]::ForegroundColor = [ConsoleColor]"+((int)state.Foreground)+"\r\n"+
                    "[Console]::BackgroundColor = [ConsoleColor]"+((int)state.Background)+"\r\n"+
                    "[Console]::Write([string][char]27 + '[39;49m')\r\n"+
                    "} finally { [void][Jobs.RecoveryConsole]::SetConsoleMode($h, $m) }\r\n";
                File.WriteAllText(state.Recovery,manual,new UTF8Encoding(false));
                state.Owner = identity+":"+Process.GetCurrentProcess().Id+":"+Process.GetCurrentProcess().StartTime.ToUniversalTime().Ticks;
                Environment.SetEnvironmentVariable(OwnerName,state.Owner);
                state.Active = true;
                foreach (string key in Keys) { Console.Write(Escape(key,state.Applied[key])); }
                Console.ForegroundColor = ConsoleColor.White; Console.BackgroundColor = ConsoleColor.Black;
                Dictionary<string,string> check = Query(state);
                foreach (string key in Keys) {
                    if (check == null || Normal(check[key]) != Normal(state.Applied[key])) { Restore(state); Plain(state); return; }
                }
            } catch (Exception error) {
                Restore(state); Plain(state);
                Console.Error.WriteLine("[Jobs] Terminal style unavailable: " + error.Message);
            }
        }
        public static void Restore(State state) {
            if (state == null) { return; }
            try {
                if (state.Active) {
                    Dictionary<string,string> current = Query(state);
                    bool complete = current != null;
                    if (current != null) {
                        bool restoreForeground = Console.ForegroundColor == ConsoleColor.White && Normal(current["10"]) == Normal(state.Applied["10"]) && Normal(current["4;15"]) == Normal(state.Applied["4;15"]);
                        bool restoreBackground = Console.BackgroundColor == ConsoleColor.Black && Normal(current["11"]) == Normal(state.Applied["11"]) && Normal(current["4;0"]) == Normal(state.Applied["4;0"]);
                        foreach (string key in Keys) {
                            if (Normal(current[key]) == Normal(state.Applied[key])) { Console.Write(Escape(key,state.Original[key])); }
                            else if (Normal(current[key]) != Normal(state.Original[key])) {
                                complete = false; Console.Error.WriteLine("[Jobs] Kept a concurrent color change: " + key);
                            }
                        }
                        if (restoreForeground) { Console.ForegroundColor = state.Foreground; Console.Write("\x1b[39m"); }
                        if (restoreBackground) { Console.BackgroundColor = state.Background; Console.Write("\x1b[49m"); }
                    }
                    if (complete) {
                        Dictionary<string,string> check = Query(state);
                        foreach (string key in Keys) { if (check == null || Normal(check[key]) != Normal(state.Original[key])) { complete = false; } }
                    }
                    if (complete) { File.Delete(state.Recovery); }
                    else { Console.Error.WriteLine("[Jobs] Color restore needs review. Manual recovery: powershell -NoProfile -File \""+state.Recovery+"\""); }
                }
            } catch (Exception error) {
                Console.Error.WriteLine("[Jobs] Color restore failed: "+error.Message+"; recovery: "+state.Recovery);
            } finally {
                if (state.Owner != null && Environment.GetEnvironmentVariable(OwnerName) == state.Owner) { Environment.SetEnvironmentVariable(OwnerName,state.PreviousOwner); }
                state.Active = false;
                uint currentMode;
                if (state.ModeChanged && GetConsoleMode(state.Output,out currentMode) && currentMode == (state.OutputMode | 4)) { SetConsoleMode(state.Output,state.OutputMode); }
                state.ModeChanged = false;
                if (state.Fallback) {
                    foreach (KeyValuePair<string,string> pair in state.EnvironmentBefore) {
                        string applied = pair.Key == "FORCE_COLOR" || pair.Key == "CLICOLOR" ? "0" : "1";
                        if (Environment.GetEnvironmentVariable(pair.Key) == applied) { Environment.SetEnvironmentVariable(pair.Key,pair.Value); }
                    }
                    state.Fallback = false;
                }
            }
        }
    }
}
'@
        } catch {
            [Console]::Error.WriteLine('[Jobs] Terminal style setup failed; using plain output: ' + $_.Exception.Message)
            return @{ JobsTerminalPlainFallback = $true; Before = @{} }
        }
    }
    return New-Object Jobs.TerminalStyleV1.Native+State
}
# Guard setup is optional; failure keeps business behavior and the user's original terminal settings.
function Start-JobsTerminalStyle {
    param($State)
    if ($State -is [Collections.IDictionary] -and $State.Contains('JobsTerminalPlainFallback')) {
        foreach ($key in @('NO_COLOR', 'PLAIN_OUTPUT', 'FORCE_COLOR', 'CLICOLOR', 'ANSI_COLORS_DISABLED')) {
            $State.Before[$key] = [Environment]::GetEnvironmentVariable($key)
            [Environment]::SetEnvironmentVariable($key, $(if (@('FORCE_COLOR', 'CLICOLOR') -contains $key) { '0' } else { '1' }))
        }
        return
    }
    if ($null -ne $State) { [Jobs.TerminalStyleV1.Native]::Enter($State) }
}
# A finally block also runs for script exit and Ctrl+C; direct .NET calls avoid stopped pipelines.
function Stop-JobsTerminalStyle {
    param($State)
    if ($State -is [Collections.IDictionary] -and $State.Contains('JobsTerminalPlainFallback')) {
        foreach ($key in $State.Before.Keys) {
            $applied = if (@('FORCE_COLOR', 'CLICOLOR') -contains $key) { '0' } else { '1' }
            if ([Environment]::GetEnvironmentVariable($key) -ceq $applied) { [Environment]::SetEnvironmentVariable($key, $State.Before[$key]) }
        }
        return
    }
    if ($null -ne $State) { [Jobs.TerminalStyleV1.Native]::Restore($State) }
}
# END JOBS_TERMINAL_STYLE_V1

$__jobsTerminalStyleState = $null
$__jobsTerminalExitCode = 0
try {
    $__jobsTerminalStyleState = New-JobsTerminalStyleState
    Start-JobsTerminalStyle $__jobsTerminalStyleState
    if ($null -eq $__jobsTerminalCommand -or $__jobsTerminalCommand.Count -eq 0) { throw 'A program is required.' }
    $__jobsTerminalProgram = $__jobsTerminalCommand[0]
    $__jobsTerminalArguments = @()
    if ($__jobsTerminalCommand.Count -gt 1) { $__jobsTerminalArguments = @($__jobsTerminalCommand[1..($__jobsTerminalCommand.Count-1)]) }
    $LASTEXITCODE = 0
    & $__jobsTerminalProgram @__jobsTerminalArguments
    $__jobsTerminalCommandSucceeded = $?
    $__jobsTerminalExitCode = $LASTEXITCODE
    if (-not $__jobsTerminalCommandSucceeded -and $__jobsTerminalExitCode -eq 0) { $__jobsTerminalExitCode = 1 }
} finally {
    Stop-JobsTerminalStyle $__jobsTerminalStyleState
}
exit $__jobsTerminalExitCode
"""
    _interrupted = False
    # 等监督进程完成恢复后再退出，避免 Ctrl+C 提前关闭控制终端。
    def _wait(_arguments):
        nonlocal _interrupted
        _process = _subprocess.Popen(_arguments, env=_environment)
        while True:
            try:
                return _process.wait()
            except KeyboardInterrupt:
                _interrupted = True
                continue
    try:
        if _os.name == "nt":
            _powershell = _shutil.which("powershell.exe") or _shutil.which("pwsh.exe")
            if not _powershell:
                _os.environ.update(NO_COLOR="1", PLAIN_OUTPUT="1", FORCE_COLOR="0", CLICOLOR="0")
                return
            with _tempfile.TemporaryDirectory(prefix="jobs-terminal-style-") as _directory:
                _wrapper = _os.path.join(_directory, "guard.ps1")
                with open(_wrapper, "w", encoding="utf-8-sig", newline="\n") as _file:
                    _file.write(_powershell_core)
                # 原参数经 JSON 交给原生 Python 数组，避开旧 Windows PowerShell 的参数重解析。
                _environment["JOBS_TERMINAL_STYLE_PYTHON_COMMAND"] = _json.dumps(_command, ensure_ascii=False)
                _receipt = _os.path.join(_directory, "started")
                _environment["JOBS_TERMINAL_STYLE_PYTHON_RECEIPT"] = _receipt
                _bridge_source = """import json, os, subprocess, sys
command = json.loads(os.environ.pop('JOBS_TERMINAL_STYLE_PYTHON_COMMAND'))
with open(os.environ.pop('JOBS_TERMINAL_STYLE_PYTHON_RECEIPT'), 'wb') as receipt:
    receipt.write(b'started')
process = subprocess.Popen(command)
while True:
    try:
        result = process.wait()
        break
    except KeyboardInterrupt:
        continue
sys.exit(result if result >= 0 else 128 - result)
"""
                _bridge = "exec(__import__('base64').b64decode('" + _base64.b64encode(_bridge_source.encode()).decode() + "'))"
                _result = _wait([_powershell, "-NoProfile", "-ExecutionPolicy", "Bypass",
                                 "-File", _wrapper, _sys.executable, "-c", _bridge])
                if not _os.path.exists(_receipt) and not _interrupted and _result not in (129, 130, 143, -1073741510, 0xC000013A):
                    _os.environ.update(NO_COLOR="1", PLAIN_OUTPUT="1", FORCE_COLOR="0", CLICOLOR="0")
                    print("终端配色保护未能启动，保持原配色并使用纯文本。", file=_sys.stderr)
                    return
        else:
            _result = _wait(["/bin/sh", "-c", _shell_core + '\njobs_terminal_style_run "$@"\n',
                             "jobs-terminal-style", *_command])
    except KeyboardInterrupt:
        raise SystemExit(130) from None
    except OSError:
        _os.environ.update(NO_COLOR="1", PLAIN_OUTPUT="1", FORCE_COLOR="0", CLICOLOR="0")
        print("终端配色保护未能启动，保持原配色并使用纯文本。", file=_sys.stderr)
        return
    if _result in (-1073741510, 0xC000013A):
        raise SystemExit(130)
    raise SystemExit(_result if _result >= 0 else 128 - _result)


if __name__ == "__main__":
    _jobs_terminal_style_bootstrap_v1()
# JOBS_TERMINAL_STYLE_GUARD_V1_END

from pathlib import Path
import os
import pty
import shutil
import subprocess
import tempfile
import unittest

ROOT=next(parent for parent in Path(__file__).resolve().parents if (parent / '代码').is_dir() and (parent / '测试').is_dir())
DEPLOY=ROOT/'部署'
MAC_ENTRY=DEPLOY/'MacOS/【MacOS】部署.command/【MacOS】部署.command'
MAC_SHORTCUT=DEPLOY/'MacOS/【MacOS】双击部署（快捷入口）.command'


def desktop_exec_argv(file, location):
    """Decode the Desktop Entry string and Exec quoting layers before expanding %k."""
    line = next(line[5:] for line in file.read_text().splitlines() if line.startswith('Exec='))
    escapes = {'s': ' ', 'n': '\n', 't': '\t', 'r': '\r', '\\': '\\'}
    decoded = []
    index = 0
    while index < len(line):
        char = line[index]
        if char == '\\':
            index += 1
            if index >= len(line) or line[index] not in escapes:
                raise ValueError('Invalid Desktop Entry string escape: ' + str(file))
            char = escapes[line[index]]
        decoded.append(char)
        index += 1

    value = ''.join(decoded)
    args, token = [], []
    quoted = False
    started = False
    index = 0
    while index < len(value):
        char = value[index]
        if char == '"':
            quoted = not quoted
            started = True
        elif char == '\\':
            index += 1
            if index >= len(value) or value[index] not in ('"', '`', '$', '\\'):
                raise ValueError('Invalid Desktop Exec argument escape: ' + str(file))
            token.append(value[index])
            started = True
        elif char.isspace() and not quoted:
            if started:
                args.append(''.join(token))
                token, started = [], False
        else:
            if char in ('$', '`'):
                raise ValueError('Unescaped Desktop Exec reserved character: ' + str(file))
            if char == '%' and quoted and value[index:index + 2] == '%k':
                raise ValueError('%k must be outside quoted Desktop Exec arguments')
            token.append(char)
            started = True
        index += 1
    if quoted:
        raise ValueError('Unclosed Desktop Exec quote: ' + str(file))
    if started:
        args.append(''.join(token))
    result = []
    for arg in args:
        if arg == '%k':
            result.append(str(location))
        else:
            index = 0
            expanded = []
            while index < len(arg):
                if arg[index] == '%':
                    if arg[index:index + 2] != '%%':
                        raise ValueError('Unsupported Desktop Exec field code')
                    index += 1
                expanded.append(arg[index])
                index += 1
            result.append(''.join(expanded))
    return result


def real_entry(platform):
    brand='【MacOS】部署.command' if platform=='MacOS' else '【FreeBSD】部署.sh' if platform=='FreeBSD' else '【Linux】部署.sh'
    return DEPLOY/platform/brand/brand

class DeploymentTests(unittest.TestCase):
    def test_01_shell_syntax(self):
        for p in DEPLOY.rglob('*'):
            if not p.is_file() or p.suffix not in {'.sh','.command'}:continue
            shell=shutil.which('zsh' if p.suffix=='.command' else 'bash')
            if not shell:raise RuntimeError('Shell missing: '+p.name)
            subprocess.run([shell,'-n',str(p)],check=True,capture_output=True)
    def test_02_powershell_parse(self):
        pwsh=shutil.which('pwsh')
        if not pwsh:self.skipTest('PowerShell parser not installed; Windows remains unverified')
        for file in DEPLOY.rglob('*.ps1'):
            if not file.is_file():continue
            path=str(file).replace("'","''")
            cmd=f"$e=$null;$t=$null;[System.Management.Automation.Language.Parser]::ParseFile('{path}',[ref]$t,[ref]$e)|Out-Null;$e|%{{$_.Message}};if($e.Count){{exit 1}}"
            subprocess.run([pwsh,'-NoLogo','-NoProfile','-Command',cmd],check=True,capture_output=True)
    def test_03_no_hardcoded_developer_paths(self):
        for p in DEPLOY.rglob('*'):
            if p.is_file() and p.suffix in {'.sh','.command','.ps1','.cmd'}:
                s=p.read_text(encoding='utf-8-sig');self.assertNotIn('/Users/jobs',s,p);self.assertNotIn('rm -rf',s,p)
    def test_04_mac_check_relocated_from_unrelated_cwd(self):
        if os.uname().sysname!='Darwin':self.skipTest('Requires MacOS')
        with tempfile.TemporaryDirectory(prefix='知序 移动目录 ') as temp:
            code=Path(temp)/'改名工程/代码'
            p=code/'后端/后端代码';(p/'cmd/server').mkdir(parents=True);(p/'go.mod').write_text('module fixture\ngo 1.27\n')
            target=code.parent/'部署/MacOS';shutil.copytree(DEPLOY/'MacOS',target)
            r=subprocess.run(['zsh',str(target/'【MacOS】部署.command/【MacOS】部署.command'),'--check'],cwd='/',capture_output=True,text=True)
            self.assertEqual(r.returncode,0,r.stdout+r.stderr);self.assertIn('检查通过',r.stdout);self.assertFalse((p/'.runtime').exists())
    def test_05_eof_cancels_without_writes(self):
        if os.uname().sysname!='Darwin':self.skipTest('Requires MacOS')
        with tempfile.TemporaryDirectory() as temp:
            code=Path(temp)/'代码';p=code/'后端/后端代码';target=code.parent/'部署/MacOS/【MacOS】部署.command/【MacOS】部署.command'
            (p/'cmd/server').mkdir(parents=True);(p/'go.mod').write_text('module fixture\ngo 1.27\n')
            shutil.copytree(DEPLOY/'MacOS',target.parent.parent)
            r=subprocess.run(['zsh',str(target)],input='',capture_output=True,text=True)
            self.assertNotEqual(r.returncode,0);self.assertFalse((p/'.runtime').exists())
    def fixture(self,body,*,answer='\n',fake_go=None):
        with tempfile.TemporaryDirectory(prefix='go-fixture-') as temp:
            p=Path(temp).resolve();(p/'project').mkdir();fake=p/'fake';fake.mkdir();log=p/'calls';log.write_text('')
            if fake_go:
                f=fake/'go';f.write_text('#!/bin/sh\n'+fake_go);f.chmod(0o755)
            prefix=MAC_ENTRY.read_text().rsplit('main "$@"',1)[0]
            script=p/'fixture.zsh';script.write_text(prefix+f'\nSERVER_ROOT="{p / 'project'}"\nLOG_FILE="{log}"\nlc_context\nmkdir -p "$LC_STATE"\n'+body+'\n')
            env={**os.environ,'HOME':str(p/'home'),'XDG_CACHE_HOME':str(p/'cache'),'GO_BIN':str(fake/'go') if fake_go else '', 'PATH':str(fake)+':/usr/bin:/bin:/usr/sbin:/sbin'}
            r=subprocess.run(['zsh',str(script)],input=answer,text=True,capture_output=True,env=env,cwd='/')
            return r,log.read_text()
    def test_06_healthy_go_reused_no_download(self):
        r,log=self.fixture('ensure_go\nprintf "SDK=%s\\n" "$GO_EXE"',fake_go='echo "go version go1.27.3 darwin/arm64"\n')
        self.assertEqual(r.returncode,0,r.stdout+r.stderr);self.assertIn('SDK=',r.stdout);self.assertNotIn('来源',log)
    def test_07_bad_selector_stops_before_go(self):
        r,log=self.fixture('select_tool_platform() { return 0; }\nensure_local_tool() { FZF_EXE=/usr/bin/false; }\nselect_deployment_mode\nprintf unexpected')
        self.assertNotEqual(r.returncode,0);self.assertNotIn('unexpected',r.stdout);self.assertNotIn('来源｜Go',log)
    def test_08_corrupt_archive_rejected(self):
        r,log=self.fixture('printf damaged > "$SERVER_ROOT/archive"\nGO_SHA=0000000000000000000000000000000000000000000000000000000000000000\nverify_archive "$SERVER_ROOT/archive"')
        self.assertNotEqual(r.returncode,0);self.assertIn('摘要不匹配',log)
    def test_backend_diagnostic_redacts_overlapping_passwords(self):
        r,log=self.fixture('export ADMIN_PASSWORD=abcd DEMO_CUSTOMER_PASSWORD=abcdXYZ\nlocal_server_log="$SERVER_ROOT/server.log"\nprintf "data directory is already locked\\ncredentials: abcd abcdXYZ\\n" > "$local_server_log"\nreport_backend_start_failure "本次后端已退出"')
        self.assertNotEqual(r.returncode,0)
        for output in (r.stdout,log):
            self.assertIn('data directory is already locked',output)
            self.assertIn('credentials: [已隐藏] [已隐藏]',output)
            self.assertNotIn('abcd',output)
            self.assertNotIn('XYZ',output)
    def test_09_script_main_has_first_intro(self):
        for p in DEPLOY.rglob('*'):
            if not p.is_file() or p.suffix not in {'.sh','.command'}:continue
            if '快捷入口' in p.name:
                self.assertFalse(p.is_symlink(),p)
                continue
            if p == DEPLOY/'公共组件/地址二维码/集成.sh/集成.sh':
                self.assertEqual(p.parent.name,p.name,p)
                self.assertTrue((p.parent/'README.md').is_file(),p)
                self.assertNotIn('\nmain "$@"',p.read_text(),p)
                continue
            self.assertEqual(p.parent.name,p.name,p)
            source=p.read_text()
            self.assertEqual(source.count('\nmain() {'),1,p)
            self.assertTrue(source.rstrip().endswith('main "$@"'),p)
            body=source.split('\nmain() {',1)[1].rsplit('\n}\nmain "$@"',1)[0]
            lines=[line.strip() for line in body.strip().splitlines()]
            if p == MAC_ENTRY:
                # 内部会话只做参数校验、只读定位和具名分派；公开流程仍先展示自述。
                dispatch=[
                    'if [ "${1:-}" = --session-child ]; then',
                    '[ $# -eq 3 ] || return 2',
                    'prepare_display_context',
                    'run_session_child "$2" "$3"',
                    'return',
                    'fi',
                    'if [ "${1:-}" = --session-guard ]; then',
                    '[ $# -eq 2 ] || return 2',
                    'prepare_display_context',
                    'run_session_guard "$2"',
                    'return',
                    'fi',
                ]
                self.assertEqual(lines[:len(dispatch)],dispatch,p)
                lines=lines[len(dispatch):]
            self.assertTrue(lines[0].startswith('show_script_intro_and_wait'),p)
            for line in lines:self.assertIn(' # ',line,p)


    def test_10_dangling_config_symlink_cannot_write_outside(self):
        for platform,shell in [('MacOS','zsh'),('Ubuntu','bash')]:
            with tempfile.TemporaryDirectory() as temp:
                root=Path(temp);(root/'.runtime').mkdir();outside=root/'outside.env';(root/'.runtime/config.env').symlink_to(outside)
                log=root/'log';log.write_text('')
                prefix=real_entry(platform).read_text().rsplit('main "$@"',1)[0]
                script=root/'fixture';script.write_text(prefix+f'\nSERVER_ROOT="{root}"\nLOG_FILE="{log}"\nconfigure_server\n')
                result=subprocess.run([shell,str(script)],input='\nadmin-password-123\ncustomer-password-123\n\n',text=True,capture_output=True)
                self.assertNotEqual(result.returncode,0);self.assertFalse(outside.exists(),platform)
    def test_11_runtime_symlink_rejected_before_log_creation(self):
        if os.uname().sysname!='Darwin':self.skipTest('Requires zsh fixture')
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);outside=root/'outside';outside.mkdir();(root/'.runtime').symlink_to(outside,target_is_directory=True)
            prefix=MAC_ENTRY.read_text().rsplit('main "$@"',1)[0]
            script=root/'fixture';script.write_text(prefix+f'\nSERVER_ROOT="{root}"\nLOG_FILE="{root}/.runtime/logs/test.log"\ninitialize_runtime\n')
            result=subprocess.run(['zsh',str(script)],text=True,capture_output=True)
            self.assertNotEqual(result.returncode,0);self.assertEqual(list(outside.iterdir()),[])

    def test_12_sdk_download_failure_stops(self):
        body='confirm_install() { return 0; }\nensure_transfer_tools() { return 0; }\ncurl() { return 22; }\nensure_go\nprintf unexpected'
        result,log=self.fixture(body)
        self.assertNotEqual(result.returncode,0);self.assertIn('依赖下载失败',log);self.assertNotIn('unexpected',result.stdout)
    def test_13_installed_sdk_recheck_failure_stops(self):
        body="""mkdir -p "$SERVER_ROOT/.tools"
confirm_install() { return 0; }
ensure_transfer_tools() { return 0; }
curl() { return 0; }
verify_archive() { return 0; }
tar() { mkdir -p "$staging_dir/go/bin"; printf '#!/bin/sh\\nexit 1\\n' > "$staging_dir/go/bin/go"; chmod +x "$staging_dir/go/bin/go"; }
ensure_go
printf unexpected"""
        result,log=self.fixture(body)
        self.assertNotEqual(result.returncode,0);self.assertIn('Go安装后健康检查失败',log);self.assertNotIn('unexpected',result.stdout)

    def test_14_mac_shortcut_relocated_read_only_and_cancel(self):
        if os.uname().sysname != 'Darwin':
            self.skipTest('Requires MacOS')
        with tempfile.TemporaryDirectory(prefix='快捷入口 中文 空格 ') as temp:
            root = Path(temp) / "改名工程 ! $ ` ' (测试)"
            server = root / '代码/后端/后端代码'
            (server / 'cmd/server').mkdir(parents=True)
            (server / 'go.mod').write_text('module fixture\ngo 1.27\n')
            platform = root / '部署/MacOS'
            shutil.copytree(DEPLOY / 'MacOS', platform)
            shortcut = platform / MAC_SHORTCUT.name
            before = sorted(str(path.relative_to(root)) for path in root.rglob('*'))
            for argument in ('--check', '--plan'):
                with self.subTest(argument=argument):
                    result = subprocess.run(['zsh', str(shortcut), argument], cwd='/',
                                            input='', capture_output=True, text=True, timeout=10)
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            result = subprocess.run(['zsh', str(shortcut)], cwd='/', input='',
                                    capture_output=True, text=True, timeout=10)
            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn('请在交互终端运行', result.stdout + result.stderr)
            master, slave = pty.openpty()
            process = None
            try:
                process = subprocess.Popen(['zsh', str(shortcut)], cwd='/', stdin=slave,
                                           stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                os.close(slave)
                slave = None
                os.write(master, b'cancel\n')
                output, error = process.communicate(timeout=10)
                self.assertNotEqual(process.returncode, 0, output + error)
                self.assertIn('按回车继续', output.decode())
            finally:
                if process is not None and process.poll() is None:
                    process.kill()
                    process.wait()
                if slave is not None:
                    os.close(slave)
                os.close(master)
            self.assertEqual(before, sorted(str(path.relative_to(root)) for path in root.rglob('*')))
            self.assertFalse((server / '.runtime').exists())

    def test_15_mac_shortcut_forwards_arguments_and_status_missing_target(self):
        with tempfile.TemporaryDirectory(prefix='快捷入口 转交 ') as temp:
            root = Path(temp) / "中文 空格 ! $ ` ' (测试)"
            root.mkdir()
            shortcut = root / MAC_SHORTCUT.name
            shutil.copy2(MAC_SHORTCUT, shortcut)
            target = root / MAC_ENTRY.parent.name / MAC_ENTRY.name
            target.parent.mkdir()
            calls = root / 'captured-arguments'
            target.write_text('printf \'%s\\0\' "$0" "$@" > "$SHORTCUT_CALLS"\nexit 37\n')
            arguments = ['--check', '中文 空格', "apostrophe'", '$value', 'back`tick', 'percent%']
            result = subprocess.run(['zsh', str(shortcut), *arguments], cwd='/', capture_output=True,
                                    env={**os.environ, 'SHORTCUT_CALLS': str(calls)}, timeout=10)
            self.assertEqual(result.returncode, 37, result.stdout + result.stderr)
            self.assertEqual(calls.read_bytes().decode().split('\0')[:-1], [str(target.resolve()), *arguments])
            target.unlink()
            calls.unlink()
            result = subprocess.run(['zsh', str(shortcut), '--check'], cwd='/',
                                    capture_output=True, timeout=10)
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse(calls.exists())

    def test_16_desktop_shortcuts_decode_and_relocate_without_installing(self):
        for platform_name in ('Ubuntu', 'Debian', 'RockyLinux', 'AlibabaCloudLinux', 'Alpine', 'FreeBSD'):
            with self.subTest(platform=platform_name), tempfile.TemporaryDirectory(prefix='桌面入口 ') as temp:
                root = Path(temp) / "中文 空格 ! $ ` ' (测试)"
                root.mkdir()
                desktops = list((DEPLOY / platform_name).glob('双击部署（快捷入口）.desktop'))
                self.assertEqual(len(desktops), 1, desktops)
                desktop = root / desktops[0].name
                shutil.copy2(desktops[0], desktop)
                self.assertIn('Terminal=true', desktop.read_text())
                entry = real_entry(platform_name)
                target = root / entry.parent.name / entry.name
                target.parent.mkdir()
                target.write_text('printf \'%s\\0\' "$0" "$@" > "$SHORTCUT_CALLS"\nexit 37\n')
                calls = root / 'captured-arguments'
                env = {**os.environ, 'SHORTCUT_CALLS': str(calls)}
                args = desktop_exec_argv(desktop, desktop)
                expected_shell = 'sh' if platform_name in ('Alpine', 'FreeBSD') else 'bash'
                self.assertEqual(args[0], expected_shell)
                if expected_shell == 'sh':
                    # Any accidental inner bash call must fail, even on a Mac with bash installed.
                    tools = root / 'tools'
                    tools.mkdir()
                    bad_bash = tools / 'bash'
                    bad_bash.write_text('#!/bin/sh\nexit 93\n')
                    bad_bash.chmod(0o755)
                    env['PATH'] = str(tools) + os.pathsep + os.environ['PATH']
                result = subprocess.run(args, cwd='/', env=env, capture_output=True, timeout=10)
                self.assertEqual(result.returncode, 37, result.stdout + result.stderr)
                self.assertEqual(calls.read_bytes().decode().split('\0')[:-1], [str(target.resolve())])
                calls.unlink()
                for invalid_location in ('', 'file:///tmp/not-a-local-path.desktop', 'https://example.invalid/launcher.desktop'):
                    result = subprocess.run(desktop_exec_argv(desktop, invalid_location), cwd='/', env=env,
                                            capture_output=True, timeout=10)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertFalse(calls.exists())
                ambiguous = root / 'another.sh/another.sh'
                ambiguous.parent.mkdir()
                ambiguous.write_text('exit 0\n')
                result = subprocess.run(args, cwd='/', env=env, capture_output=True, timeout=10)
                # 用途明确的固定入口不能被其它部署/反部署脚本误选或遮蔽。
                self.assertEqual(result.returncode, 37, result.stdout + result.stderr)
                self.assertEqual(calls.read_bytes().decode().split('\0')[:-1], [str(target.resolve())])
                calls.unlink()
                ambiguous.unlink()
                ambiguous.parent.rmdir()
                target.unlink()
                result = subprocess.run(args, cwd='/', env=env, capture_output=True, timeout=10)
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(calls.exists())

    def test_17_windows_shortcut_ascii_and_parameter_contract(self):
        """Static checks only; Windows CMD execution still needs a native Windows host."""
        shortcuts = [path for path in (DEPLOY / 'Windows').glob('【Windows】双击部署（快捷入口）.cmd') if path.is_file()]
        self.assertEqual(len(shortcuts), 1, shortcuts)
        raw = shortcuts[0].read_bytes()
        script = raw.decode('ascii')
        self.assertIn('DisableDelayedExpansion', script)
        self.assertIn('%~dp0', script)
        self.assertIn('%*', script)
        self.assertIn('-File', script)
        self.assertNotIn('chcp', script.lower())
        self.assertNotIn('call ', script.lower())
        self.assertIn('exit /b', script.lower())
        targets = [path / path.name for path in (DEPLOY / 'Windows').glob('【Windows】部署.ps1')
                   if path.is_dir() and (path / path.name).is_file()]
        self.assertEqual(len(targets), 1, targets)

if __name__=='__main__':unittest.main(verbosity=2)
