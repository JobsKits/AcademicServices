# 脚本自述：按本工程Windows原点精确反部署，fzf默认备份数据后清理本次新建源数据。
# 只处理已记录且摘要未变的资源；原有data、共享资源、外部PostgreSQL与未知旧部署保留并报告。
param([switch]$Check,[switch]$Plan)
# Jobs enter-choice emphasis is display-only; input and business decisions stay with callers.
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
try {
    if ($MyInvocation.InvocationName -ne '.') {
        $__jobsTerminalStyleState = New-JobsTerminalStyleState
        Start-JobsTerminalStyle $__jobsTerminalStyleState
    }
# BEGIN JOBS_TERMINAL_STYLE_ORIGINAL_BODY
function Test-JobsEnterChoiceColor {
    if ((Test-Path Env:NO_COLOR) -or $env:TERM -ieq 'dumb' -or $env:PLAIN_OUTPUT -eq '1') { return $false }
    $consoleType = [Console]
    if ($null -eq $consoleType.GetProperty('IsInputRedirected') -or $null -eq $consoleType.GetProperty('IsOutputRedirected')) { return $false }
    return ($Host.Name -ceq 'ConsoleHost' -and -not [Console]::IsInputRedirected -and -not [Console]::IsOutputRedirected)
}
# Older hosts keep native colors without sending unsupported bold escape sequences.
function Test-JobsEnterChoiceBold {
    $property = $Host.UI.PSObject.Properties['SupportsVirtualTerminal']
    return ($null -ne $property -and [bool]$property.Value)
}
# Separate ordinary question text from Enter and arbitrary-input options without changing words.
function Get-JobsEnterChoiceParts {
    param([string]$Text)
    $red = '(?:(?:\u8f93\u5165)?(?:\u4efb\u610f(?:\u975e\u7a7a)?(?:\u5b57\u7b26|\u5185\u5bb9|\u6587\u5b57|\u8f93\u5165)?|\u975e\u7a7a(?:\u8f93\u5165|\u5b57\u7b26|\u5185\u5bb9)?|(?:\u5176\u5b83|\u5176\u4ed6)(?:\u975e\u7a7a)?(?:\u8f93\u5165|\u5185\u5bb9|\u5b57\u7b26)?))|(?:any\s+(?:(?:other|non[- ]empty)\s+)?(?:input|text|characters?)|non[- ]empty\s+input)'
    $green = '(?:(?:\u76f4\u63a5|\u53ea\u9700|\u4ec5(?:\u9700)?|\u6309(?:\u4e0b)?|\u7a7a)?\s*\u56de\u8f66|(?:press\s+)?\bEnter\b(?!\s+(?:YES|REPAIR|CLEAN|CONTINUE)\b))'
    $pattern = '(?is)(?<red>(?:' + $red + ')[^;\uFF1B\r\n]*?(?=[;\uFF1B\r\n]|\z))|(?<green>(?:' + $green + ')[^;\uFF1B\r\n]*?(?=(?:' + $red + ')|[;\uFF1B\r\n]|\z))'
    $offset = 0
    foreach ($match in [regex]::Matches($Text, $pattern)) {
        if ($match.Index -gt $offset) { [pscustomobject]@{ Text = $Text.Substring($offset, $match.Index - $offset); Color = '' } }
        $prefix = [regex]::Split($Text.Substring(0, $match.Index), '[;\uFF1B\r\n]')[-1]
        $typed = $prefix -match '(?i)(?:\u8f93\u5165|\u952e\u5165|type|enter)\s*(?:\u5927\u5199\s*)?(?:YES|REPAIR|CLEAN|CONTINUE)\b|\u7cbe\u786e\u8f93\u5165|\u8f93\u5165[^;\uFF1B\r\n]*[\u540e\u518d]\s*$'
        $color = if ($match.Groups['red'].Success) { 'Red' } elseif ($typed) { '' } else { 'Green' }
        [pscustomobject]@{ Text = $match.Value; Color = $color }
        $offset = $match.Index + $match.Length
    }
    if ($offset -lt $Text.Length) { [pscustomobject]@{ Text = $Text.Substring($offset); Color = '' } }
}
# Native host text remains plain in information streams and logs; bold control is console-only.
function Write-JobsEnterChoiceText {
    [CmdletBinding()]
    param([Parameter(Position=0)][AllowNull()][object]$Object, [switch]$NoNewline, [ConsoleColor]$ForegroundColor, [ConsoleColor]$BackgroundColor, [object]$Separator = ' ')
    $text = if ($Object -is [array]) { $Object -join [string]$Separator } else { [string]$Object }
    if (-not (Test-JobsEnterChoiceColor)) {
        Write-Host $Object -NoNewline:$NoNewline -Separator $Separator
        return
    }
    $normal = @{}
    if ($PSBoundParameters.ContainsKey('ForegroundColor')) { $normal.ForegroundColor = $ForegroundColor }
    if ($PSBoundParameters.ContainsKey('BackgroundColor')) { $normal.BackgroundColor = $BackgroundColor }
    foreach ($part in @(Get-JobsEnterChoiceParts $text)) {
        if (-not $part.Color) { Write-Host $part.Text -NoNewline @normal; continue }
        $bold = Test-JobsEnterChoiceBold
        if ($bold) { [Console]::Write(([string][char]27) + '[1m') }
        try { Write-Host $part.Text -ForegroundColor $part.Color -NoNewline }
        finally { if ($bold) { [Console]::Write(([string][char]27) + '[0m') } }
    }
    if (-not $NoNewline) { Write-Host }
}
# Delegate the original reader, including secure input and EOF behavior, after prompt display.
function Read-JobsEnterChoiceHost {
    [CmdletBinding()]
    param([Parameter(Position=0)][string]$Prompt, [switch]$AsSecureString, [switch]$MaskInput)
    if ($AsSecureString -or $MaskInput -or -not (Test-JobsEnterChoiceColor) -or @((Get-JobsEnterChoiceParts $Prompt) | Where-Object { $_.Color }).Count -eq 0) {
        return (Read-Host @PSBoundParameters)
    }
    Write-JobsEnterChoiceText ($Prompt + ': ') -NoNewline
    return (Read-Host)
}


$ErrorActionPreference = 'Stop'
$ServerRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../代码/后端/后端代码'))

# BEGIN JOBS DEPLOYMENT LIFECYCLE
# 原点与恢复函数由本脚本内嵌；严格模式仅限定在生命周期函数内。
function Assert-PlainPath([string]$Path) {
    Set-StrictMode -Version 2
    $cursor = [IO.Path]::GetFullPath($Path)
    while ($cursor) {
        $item = Get-Item -LiteralPath $cursor -Force -ErrorAction SilentlyContinue
        if ($item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw "拒绝链接路径：$cursor" }
        $parent = [IO.Path]::GetDirectoryName($cursor)
        if ($parent -eq $cursor) { break }
        $cursor = $parent
    }
}

function Protect-Origin([string]$Path) {
    Set-StrictMode -Version 2
    if ($env:OS -ne 'Windows_NT') { return }
    $acl = New-Object Security.AccessControl.DirectorySecurity
    $acl.SetAccessRuleProtection($true,$false)
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    $rule = New-Object Security.AccessControl.FileSystemAccessRule($identity,'FullControl','ContainerInherit,ObjectInherit','None','Allow')
    $acl.AddAccessRule($rule)
    Set-Acl -LiteralPath $Path -AclObject $acl
}

function Get-OriginLocation([string]$Root) {
    Set-StrictMode -Version 2
    return Join-Path $Root '.deployment-state/windows'
}

function Enter-OriginLock([string]$Root) {
    Set-StrictMode -Version 2
    $state = Join-Path $Root '.deployment-state'
    Assert-PlainPath $state
    $owner = Join-Path $state 'owner'
    Assert-PlainPath $owner
    if ((Test-Path -LiteralPath $owner) -and (Get-Content -LiteralPath $owner -Raw).Trim() -cne 'windows') { throw '另一个操作系统持有部署原点，必须回到原系统反部署。' }
    if ((Test-Path -LiteralPath $state) -and -not (Test-Path -LiteralPath $owner) -and @(Get-ChildItem -LiteralPath $state -Force).Count) { throw '状态目录已有资料但归属缺失，保留并停止。' }
    $null = New-Item -ItemType Directory -Path $state -Force
    Protect-Origin $state
    $guardPath = Join-Path $state 'windows-operation.guard'
    Assert-PlainPath $guardPath
    $guard = [IO.File]::Open($guardPath,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    try {
    $path = Join-Path $state 'operation-lock'
    Assert-PlainPath $path
    if (Test-Path -LiteralPath $path) {
        $pidFile = Join-Path $path 'pid'
        Assert-PlainPath $pidFile
        $oldPid = 0
        if (-not (Test-Path -LiteralPath $pidFile) -or -not [int]::TryParse((Get-Content -LiteralPath $pidFile -Raw).Trim(),[ref]$oldPid)) { throw '操作锁身份未知，保留并停止。' }
        if (Get-Process -Id $oldPid -ErrorAction SilentlyContinue) { throw '部署或反部署正在运行，未取得操作锁。' }
        foreach ($item in Get-ChildItem -LiteralPath $path -Force) {
            if ($item.Name -notin @('pid','identity') -or $item.PSIsContainer) { throw '操作锁含未知资料，未回收。' }
            Assert-PlainPath $item.FullName
        }
        Remove-Item -LiteralPath $path -Recurse
    }
    $null = New-Item -ItemType Directory -Path $path -ErrorAction Stop
    [IO.File]::WriteAllText((Join-Path $path 'pid'),$PID.ToString())
    [IO.File]::WriteAllText((Join-Path $path 'identity'),(Get-Process -Id $PID).StartTime.ToUniversalTime().Ticks.ToString())
    if (-not (Test-Path -LiteralPath $owner)) { [IO.File]::WriteAllText($owner,'windows') }
    if ((Get-Content -LiteralPath $owner -Raw).Trim() -cne 'windows') { throw '原点归属在争锁时发生变化。' }
    return [pscustomobject]@{ path=$path; stream=$guard }
    } catch { $guard.Dispose(); throw }
}

function Exit-OriginLock($Lock) {
    Set-StrictMode -Version 2
    $Path = $Lock.path
    try {
    Assert-PlainPath $Path
    if ((Get-Content -LiteralPath (Join-Path $Path 'pid') -Raw).Trim() -cne $PID.ToString()) { throw '操作锁归属已改变，保留。' }
    Remove-Item -LiteralPath (Join-Path $Path 'pid')
    Remove-Item -LiteralPath (Join-Path $Path 'identity')
    Remove-Item -LiteralPath $Path
    } finally { $Lock.stream.Dispose() }
}

function Get-ArtifactInventory([string]$Root,[string[]]$Parts = @('.runtime','.tools')) {
    Set-StrictMode -Version 2
    $rows = @()
    foreach ($part in $Parts) {
        $path = Join-Path $Root $part
        Assert-PlainPath $path
        if (-not (Test-Path -LiteralPath $path)) { continue }
        $rootItem = Get-Item -LiteralPath $path -Force
        $items = @($rootItem)
        if ($rootItem.PSIsContainer) { $items += @(Get-ChildItem -LiteralPath $path -Recurse -Force) }
        foreach ($item in $items) {
            Assert-PlainPath $item.FullName
            $relative = $item.FullName.Substring($Root.TrimEnd('\','/').Length + 1).Replace('\','/')
            if ($item.PSIsContainer) { $hash = 'directory' } else { $hash = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash }
            $sddl = ''
            if ($env:OS -eq 'Windows_NT') { $sddl = (Get-Acl -LiteralPath $item.FullName).Sddl }
            $rows += [pscustomobject]@{ path=$relative; hash=$hash; acl=$sddl }
        }
    }
    return @($rows | Sort-Object path)
}

function Get-InventoryDigest($Rows,[switch]$IncludeAcl) {
    Set-StrictMode -Version 2
    $text = (@($Rows | Where-Object { $null -ne $_ } | Sort-Object path | ForEach-Object { $_.path + '|' + $_.hash + $(if ($IncludeAcl) { '|' + $_.acl } else { '' }) }) -join "`n")
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($text))).Replace('-','') }
    finally { $sha.Dispose() }
}

function Save-Origin([string]$Root,$Receipt) {
    Set-StrictMode -Version 2
    $directory = Get-OriginLocation $Root
    Assert-PlainPath $directory
    $path = Join-Path $directory 'receipt.json'
    $temporary = Join-Path $directory ('receipt-' + [guid]::NewGuid().ToString('N') + '.tmp')
    [IO.File]::WriteAllText($temporary,($Receipt | ConvertTo-Json -Depth 20),(New-Object Text.UTF8Encoding($false)))
    Move-Item -LiteralPath $temporary -Destination $path -Force
}

function Read-Origin([string]$Root) {
    Set-StrictMode -Version 2
    $owner = Join-Path $Root '.deployment-state/owner'
    Assert-PlainPath $owner
    if ((Test-Path -LiteralPath $owner) -and (Get-Content -LiteralPath $owner -Raw).Trim() -cne 'windows') { throw '原点属于另一个操作系统，请使用该系统的反部署入口。' }
    $path = Join-Path (Get-OriginLocation $Root) 'receipt.json'
    Assert-PlainPath $path
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    $receipt = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($receipt.schema -ne 1 -or $receipt.root -cne $Root -or $receipt.id -notmatch '^[a-f0-9]{32}$') { throw '部署原点与当前工程不匹配，未修改。' }
    foreach ($row in @(@($receipt.before) + @($receipt.after) | Where-Object { $null -ne $_ })) {
        if ($row.path -notmatch '^(\.runtime|\.tools)(/[^/]+)*$' -or $row.path -match '(^|/)\.\.?(/|$)' -or $row.path.Contains('\') -or $row.path.Contains(':')) { throw '原点含越界路径。' }
        if ($row.hash -notmatch '^(directory|[A-F0-9]{64})$') { throw '原点摘要无效。' }
    }
    return $receipt
}

function Copy-OriginFiles([string]$Root,$Rows,[string]$Destination) {
    Set-StrictMode -Version 2
    foreach ($row in @($Rows | Where-Object { $null -ne $_ } | Sort-Object { $_.path.Length })) {
        $source = Join-Path $Root $row.path
        $target = Join-Path $Destination $row.path
        Assert-PlainPath $source
        Assert-PlainPath $target
        if ($row.hash -eq 'directory') { $null = New-Item -ItemType Directory -Path $target -Force }
        else {
            $null = New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($target)) -Force
            Copy-Item -LiteralPath $source -Destination $target
            if ((Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash -cne $row.hash -or (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -cne $row.hash) { throw '原点复制时文件变化，未开始部署。' }
        }
    }
}

function Start-Origin([string]$Root) {
    Set-StrictMode -Version 2
    $receipt = Read-Origin $Root
    if ($receipt -and $receipt.status -ne 'complete') {
        if ($receipt.status -ne 'deployed') { throw '上轮部署或反部署未完成，请先按原点核对恢复；禁止覆盖依据。' }
        $current = Get-ArtifactInventory $Root
        if ((Get-InventoryDigest $current -IncludeAcl) -cne (Get-InventoryDigest $receipt.after -IncludeAcl)) { throw '上轮产物已被后续修改，请先核对反部署原点，不覆盖后续内容。' }
        $receipt.status = 'deploying'
        Save-Origin $Root $receipt
        return
    }
    $directory = Get-OriginLocation $Root
    Assert-PlainPath $directory
    if ($receipt) {
        throw '此原点已完成反部署。重新部署前请把整个 .deployment-state 私密归档到项目外，保留审计；不自动覆盖或复用旧原点。'
    } elseif (Test-Path -LiteralPath $directory) { throw '原点目录无有效收据，保留以供人工核查。' }
    $before = @(Get-ArtifactInventory $Root)
    $null = New-Item -ItemType Directory -Path $directory
    Protect-Origin $directory
    $receipt = [pscustomobject]@{ schema=1; id=[guid]::NewGuid().ToString('N'); root=$Root; status='preparing'; before=$before; after=@(); dataExisted=(Test-Path -LiteralPath (Join-Path $Root 'data')); database='file'; processes=@(); undo=$null }
    Save-Origin $Root $receipt
    Copy-OriginFiles $Root $before (Join-Path $directory 'original')
    $receipt.status = 'deploying'
    Save-Origin $Root $receipt
}

function Complete-Origin([string]$Root,[string]$DatabaseURL) {
    Set-StrictMode -Version 2
    $receipt = Read-Origin $Root
    if (-not $receipt -or $receipt.status -ne 'deploying') { throw '部署原点未开始，禁止伪造完成记录。' }
    $receipt.after = @(Get-ArtifactInventory $Root)
    $receipt.database = $(if ($DatabaseURL) { 'postgresql-external' } else { 'file' })
    $receipt | Add-Member -MemberType NoteProperty -Name stoppedMarker -Value (Get-OwnedStoppedMarker $Root $receipt) -Force
    $receipt.status = 'deployed'
    Save-Origin $Root $receipt
}

# Windows强制结束子进程可能留下O_EXCL标记；仅封存同一收据进程所写且已死亡的标记。
function Get-OwnedStoppedMarker([string]$Root,$Receipt) {
    Set-StrictMode -Version 2
    $marker = Join-Path $Root 'data/.server-lock'
    Assert-PlainPath $marker
    if (-not (Test-Path -LiteralPath $marker -PathType Leaf)) { return $null }
    $hash = Get-OriginFileHash $marker
    $text = [IO.File]::ReadAllText($marker)
    $match = [regex]::Match($text,'\Apid=([0-9]+)\r?\nstarted=([^\r\n]+)\r?\n\z')
    if (-not $match.Success) { return $null }
    $markerPid = 0
    if (-not [int]::TryParse($match.Groups[1].Value,[ref]$markerPid) -or $markerPid -lt 1) { return $null }
    $rows = @($Receipt.processes | Where-Object { $_.pid -eq $markerPid -and $_.path -ieq (Join-Path $Root '.runtime/bin/server.exe') })
    if ($rows.Count -ne 1 -or (Get-Process -Id $markerPid -ErrorAction SilentlyContinue)) { return $null }
    $time = [DateTimeOffset]::MinValue
    $stamp = [regex]::Replace($match.Groups[2].Value,'(\.\d{7})\d+','$1')
    if (-not [DateTimeOffset]::TryParse($stamp,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::AssumeUniversal,[ref]$time)) { return $null }
    $processTicks = 0L
    if (-not [long]::TryParse($rows[0].started,[ref]$processTicks) -or $time.UtcDateTime.Ticks -lt $processTicks -or $time.UtcDateTime -gt [DateTime]::UtcNow.AddSeconds(1)) { return $null }
    if ((Get-OriginFileHash $marker) -cne $hash) { return $null }
    return [pscustomobject]@{ pid=$markerPid; hash=$hash; started=$rows[0].started }
}

function Add-OriginProcess([string]$Root,$Process) {
    Set-StrictMode -Version 2
    $receipt = Read-Origin $Root
    $Process.Refresh()
    if ($Process.HasExited) { return }
    $receipt.processes = @($receipt.processes) + @([pscustomobject]@{ pid=$Process.Id; started=$Process.StartTime.ToUniversalTime().Ticks.ToString(); path=$Process.Path })
    Save-Origin $Root $receipt
}

function Stop-OriginProcesses([string]$Root,$Receipt) {
    Set-StrictMode -Version 2
    foreach ($row in @($Receipt.processes)) {
        $process = Get-Process -Id ([int]$row.pid) -ErrorAction SilentlyContinue
        if (-not $process) { continue }
        try {
            if ($process.StartTime.ToUniversalTime().Ticks.ToString() -cne $row.started -or $process.Path -cne $row.path) { throw 'PID已复用或身份无法证明，保留进程并停止反部署。' }
            Stop-Process -InputObject $process -ErrorAction Stop
            if (-not $process.WaitForExit(5000)) { throw '本次进程未在5秒内停止。' }
        } finally { $process.Dispose() }
    }
    # 非本入口启动的实例没有进程收据，保守阻断，不按PID文本或名称强杀。
    $data = Join-Path $Root 'data'
    $marker = Join-Path $data '.server-lock'
    if ((Test-Path -LiteralPath $marker) -and $Receipt.PSObject.Properties.Name -contains 'stoppedMarker' -and $Receipt.stoppedMarker) {
        $proof = $Receipt.stoppedMarker
        if (Get-Process -Id ([int]$proof.pid) -ErrorAction SilentlyContinue) { throw '已记录标记PID重新存活，保留锁并停止。' }
        if ((Get-OriginFileHash $marker) -cne $proof.hash) { throw '服务锁已偏离部署封存证据，保留。' }
        $retired = Join-Path (Get-OriginLocation $Root) ('stopped-server-lock-' + $Receipt.id)
        Assert-PlainPath $retired
        if (Test-Path -LiteralPath $retired) { throw '服务锁审计位置已有内容，保留并停止。' }
        [IO.File]::Move($marker,$retired)
        if ((Get-OriginFileHash $retired) -cne $proof.hash) { throw '隔离服务锁不匹配，保留审计与数据，不清理。' }
    }
    foreach ($name in @('.server-lock','.server-guard')) {
        if (Test-Path -LiteralPath (Join-Path $data $name)) { throw '数据锁仍存在；请先关闭实例并核对锁，未删除数据。' }
    }
}

function Assert-FileDatabase([string]$Root,$Receipt) {
    Set-StrictMode -Version 2
    if ($Receipt.database -ne 'file') { throw '该部署使用外部 PostgreSQL；当前入口没有数据库原生备份/清零能力，全部保留。' }
    $config = Join-Path $Root '.runtime/config.env'
    Assert-PlainPath $config
    if (Test-Path -LiteralPath $config) {
        foreach ($line in [IO.File]::ReadAllLines($config)) {
            if ($line -match '^DATABASE_URL=(.+)$') { throw '当前配置使用外部 PostgreSQL，未处理数据或产物。' }
        }
    }
}

function New-UndoBackup([string]$Root,$Receipt) {
    Set-StrictMode -Version 2
    $base = Join-Path ([IO.Path]::GetDirectoryName($Root)) 'UndeploymentBackups'
    Assert-PlainPath $base
    $target = Join-Path $base ('Windows-' + $Receipt.id)
    if (Test-Path -LiteralPath $target) { throw '备份位置已存在但未登记，保留且停止，不覆盖。' }
    $null = New-Item -ItemType Directory -Path $target -Force
    Protect-Origin $target
    $rows = @(Get-ArtifactInventory $Root @('data','.runtime/config.env'))
    Copy-OriginFiles $Root $rows $target
    $copy = @(Get-ArtifactInventory $target @('data','.runtime/config.env'))
    if ((Get-InventoryDigest $rows) -cne (Get-InventoryDigest $copy)) { throw '数据备份完整性核验失败，源数据与现有备份保留。' }
    return [pscustomobject]@{ path=$target; rows=$rows; hash=(Get-InventoryDigest $rows) }
}

function Assert-UndoSnapshot([string]$Root,$Receipt) {
    Set-StrictMode -Version 2
    if ((Get-InventoryDigest (Get-ArtifactInventory $Root) -IncludeAcl) -cne (Get-InventoryDigest $Receipt.after -IncludeAcl)) { throw '产物清单含后续变化或未知对象，保留全部业务数据与产物。' }
    foreach ($row in @($Receipt.after)) {
        $before = @($Receipt.before | Where-Object { $_.path -ceq $row.path })
        if ($before.Count -eq 1 -and $before[0].hash -ceq $row.hash -and $before[0].acl -ceq $row.acl) { continue }
        $path = Join-Path $Root $row.path
        Assert-PlainPath $path
        if ($env:OS -eq 'Windows_NT' -and (Test-Path -LiteralPath $path) -and (Get-Acl -LiteralPath $path).Sddl -cne $row.acl) { throw ('产物权限发生后续变化，已保留：' + $row.path) }
        if ($row.hash -eq 'directory') { continue }
        if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -cne $row.hash) { throw "产物已改变或缺失，保留并停止：$($row.path)" }
    }
}

function Move-UndoData([string]$Root,$Receipt,[string]$Policy) {
    Set-StrictMode -Version 2
    $data = Join-Path $Root 'data'
    $retired = Join-Path $Root ('.data-retired-' + $Receipt.id)
    Assert-PlainPath $data
    Assert-PlainPath $retired
    if ($Receipt.dataExisted) { return } # 原有业务数据不属于本轮新建资源。
    if ($Receipt.undo.dataDone) {
        if (Test-Path -LiteralPath $data) { throw '反部署后原数据路径被重建，已保留。' }
        return
    }
    if ((Test-Path -LiteralPath $data) -and (Test-Path -LiteralPath $retired)) { throw '源与隔离目录同时存在，保留并停止。' }
    $source = $(if (Test-Path -LiteralPath $retired) { $retired } else { $data })
    $actual = @(Get-ArtifactInventory $Root @([IO.Path]::GetFileName($source)))
    # 统一相对根名后比较，隔离重命名不改变已确认的内容摘要。
    $normalized = @($actual | ForEach-Object { [pscustomobject]@{ path=('data' + $_.path.Substring([IO.Path]::GetFileName($source).Length)); hash=$_.hash; acl=$_.acl } })
    if ((Get-InventoryDigest $normalized) -cne $Receipt.undo.dataHash) { throw '数据已偏离确认快照，保留源与原备份，不重新备份后清零。' }
    if (Test-Path -LiteralPath $data) { [IO.Directory]::Move($data,$retired) }
    if (Test-Path -LiteralPath $retired) {
        # 移至唯一收据归属隔离目录，删除前再校验；发生改变即保留。
        $verify = @(Get-ArtifactInventory $Root @([IO.Path]::GetFileName($retired)) | ForEach-Object { [pscustomobject]@{ path=('data' + $_.path.Substring([IO.Path]::GetFileName($retired).Length)); hash=$_.hash; acl=$_.acl } })
        if ((Get-InventoryDigest $verify) -cne $Receipt.undo.dataHash) { throw '隔离数据发生变化，未删除。' }
        Remove-Item -LiteralPath $retired -Recurse -Force
    }
    $Receipt.undo.dataDone = $true
    Save-Origin $Root $Receipt
}

function Get-OriginFileHash([string]$Path) {
    Set-StrictMode -Version 2
    Assert-PlainPath $Path
    if (-not (Test-Path -LiteralPath $Path)) { return 'absent' }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw '预期文件位置出现了目录，保留。' }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

# 先准备和校验原件，再以同卷重命名替换；每个窗口都有持久化阶段可核对。
function Restore-OriginFile([string]$Root,$Receipt,[string]$Relative,[string]$OldHash,[string]$NewHash) {
    Set-StrictMode -Version 2
    $path = Join-Path $Root $Relative
    $parent = [IO.Path]::GetDirectoryName($path)
    $stage = Join-Path $parent ('.academic-restore-' + $Receipt.id)
    $retired = Join-Path $parent ('.academic-retired-' + $Receipt.id)
    $current = Get-OriginFileHash $path
    $journal = $null
    if ($Receipt.undo.PSObject.Properties.Name -contains 'fileJournal') { $journal = $Receipt.undo.fileJournal }
    if (-not $journal -or $journal.path -cne $Relative) {
        if ($journal -and $journal.phase -ne 'done') { throw '另一个文件恢复尚未结束，保留暂存现场。' }
        if ($current -ceq $OldHash) { return }
        if ($current -cne $NewHash) { throw "恢复前文件变化，已保留：$Relative" }
        if ((Get-OriginFileHash $stage) -cne 'absent' -or (Get-OriginFileHash $retired) -cne 'absent') { throw '恢复暂存名已被占用，保留且停止。' }
        $journal = [pscustomobject]@{ path=$Relative; old=$OldHash; after=$NewHash; phase='preparing' }
        $Receipt.undo | Add-Member -MemberType NoteProperty -Name fileJournal -Value $journal -Force
        Save-Origin $Root $Receipt
    }
    if ($journal.old -cne $OldHash -or $journal.after -cne $NewHash -or $journal.phase -notin @('preparing','prepared','retired','installed','done')) { throw '文件恢复阶段不匹配，保留。' }
    if ($journal.phase -eq 'preparing') {
        if ($current -cne $NewHash -or (Get-OriginFileHash $retired) -cne 'absent') { throw '准备原件前现场发生变化。' }
        if ($OldHash -ne 'absent') {
            $original = Join-Path (Get-OriginLocation $Root) ('original/' + $Relative)
            if ((Get-OriginFileHash $original) -cne $OldHash) { throw '原点副本损坏，禁止覆盖。' }
            $stageHash = Get-OriginFileHash $stage
            if ($stageHash -eq 'absent') {
                $null = New-Item -ItemType Directory -Path $parent -Force
                Copy-Item -LiteralPath $original -Destination $stage
                $stageHash = Get-OriginFileHash $stage
            }
            if ($stageHash -cne $OldHash) { throw '准备副本未通过完整性验证，原产物保留。' }
        }
        $journal.phase = 'prepared'
        Save-Origin $Root $Receipt
    }
    if ($journal.phase -eq 'prepared') {
        if ($OldHash -ne 'absent' -and (Get-OriginFileHash $stage) -cne $OldHash) { throw '退休产物前准备副本缺失或变化，保留原产物。' }
        $current = Get-OriginFileHash $path
        $retiredHash = Get-OriginFileHash $retired
        if ($current -ceq $NewHash -and $retiredHash -eq 'absent' -and $NewHash -ne 'absent') { [IO.File]::Move($path,$retired) }
        elseif ($current -ne 'absent' -or ($NewHash -ne 'absent' -and $retiredHash -cne $NewHash)) { throw '退休产物现场与已记录内容不符。' }
        $journal.phase = 'retired'
        Save-Origin $Root $Receipt
    }
    if ($journal.phase -eq 'retired') {
        $current = Get-OriginFileHash $path
        $stageHash = Get-OriginFileHash $stage
        if ($OldHash -ne 'absent') {
            if ($current -eq 'absent' -and $stageHash -ceq $OldHash) { [IO.File]::Move($stage,$path) }
            elseif ($current -cne $OldHash -or $stageHash -ne 'absent') { throw '安装原件现场不符，未覆盖。' }
        } elseif ($current -ne 'absent') { throw '目标位置被重建，已保留。' }
        $journal.phase = 'installed'
        Save-Origin $Root $Receipt
    }
    if ($journal.phase -eq 'installed') {
        if ((Get-OriginFileHash $path) -cne $OldHash -or (Get-OriginFileHash $stage) -ne 'absent') { throw '原件安装结果不匹配。' }
        $retiredHash = Get-OriginFileHash $retired
        if ($retiredHash -ne 'absent') {
            if ($retiredHash -cne $NewHash) { throw '退休产物被修改，已保留。' }
            Remove-Item -LiteralPath $retired -Force
        }
        $journal.phase = 'done'
        Save-Origin $Root $Receipt
    }
    if ((Get-OriginFileHash $path) -cne $OldHash -or (Get-OriginFileHash $stage) -ne 'absent' -or (Get-OriginFileHash $retired) -ne 'absent') { throw '文件恢复仍有遗留差异。' }
}

function Restore-OriginArtifacts([string]$Root,$Receipt) {
    Set-StrictMode -Version 2
    $all = @(@($Receipt.before | ForEach-Object { $_.path }) + @($Receipt.after | ForEach-Object { $_.path }) | Sort-Object -Unique | Sort-Object Length -Descending)
    foreach ($relative in $all) {
        if (@($Receipt.undo.done) -contains $relative) { continue }
        $old = @($Receipt.before | Where-Object { $_.path -ceq $relative })
        $new = @($Receipt.after | Where-Object { $_.path -ceq $relative })
        $path = Join-Path $Root $relative
        Assert-PlainPath $path
        if ($old.Count -and $new.Count -and $old[0].hash -ceq $new[0].hash -and $old[0].acl -ceq $new[0].acl) { continue }
        if (($new.Count -and $new[0].hash -eq 'directory') -or ($old.Count -and $old[0].hash -eq 'directory')) {
            if (-not $old.Count -and (Test-Path -LiteralPath $path)) {
                if (@(Get-ChildItem -LiteralPath $path -Force).Count) { throw "目录含未知或共享资料，已保留：$relative" }
                Remove-Item -LiteralPath $path -Force
            } elseif ($old.Count -and -not (Test-Path -LiteralPath $path)) { $null = New-Item -ItemType Directory -Path $path -Force }
        } else {
            $oldHash = $(if ($old.Count) { $old[0].hash } else { 'absent' })
            $newHash = $(if ($new.Count) { $new[0].hash } else { 'absent' })
            Restore-OriginFile $Root $Receipt $relative $oldHash $newHash
        }
        if ($old.Count -and $old[0].acl -and $env:OS -eq 'Windows_NT') {
            $acl = Get-Acl -LiteralPath $path
            $acl.SetSecurityDescriptorSddlForm($old[0].acl)
            Set-Acl -LiteralPath $path -AclObject $acl
        }
        $Receipt.undo.done = @($Receipt.undo.done) + @($relative)
        Save-Origin $Root $Receipt
    }
}

function Invoke-OriginUndo([string]$Root,[ValidateSet('backup','clear')][string]$Policy) {
    Set-StrictMode -Version 2
    $lock = Enter-OriginLock $Root
    try {
        $receipt = Read-Origin $Root
        if (-not $receipt) { throw '没有部署前原点，未猜测或删除旧部署资源。' }
        if ($receipt.status -eq 'complete') { Write-Host '此原点已完成，无需重复清理。'; return }
        if ($receipt.status -notin @('deployed','undoing')) { throw '部署未封存，保留全部现场，先核对原点。' }
        Assert-FileDatabase $Root $receipt
        Stop-OriginProcesses $Root $receipt
        if (-not $receipt.undo) {
            Assert-UndoSnapshot $Root $receipt
            $receipt.undo = [pscustomobject]@{ policy=$Policy; backup=$null; dataHash=(Get-InventoryDigest (Get-ArtifactInventory $Root @('data'))); dataDone=$false; done=@() }
            $receipt.status = 'undoing'
            Save-Origin $Root $receipt
        } elseif ($receipt.undo.policy -cne $Policy) { throw '重试须沿用已经确认的数据策略。' }
        if ($Policy -eq 'backup') {
            if (-not $receipt.undo.backup) {
                $receipt.undo.backup = New-UndoBackup $Root $receipt
                Save-Origin $Root $receipt
            }
            $backup = $receipt.undo.backup
            if ((Get-InventoryDigest (Get-ArtifactInventory $backup.path @('data','.runtime/config.env'))) -cne $backup.hash) { throw '原备份已改变，保留全部剩余对象。' }
        }
        Move-UndoData $Root $receipt $Policy
        Restore-OriginArtifacts $Root $receipt
        Restore-DependencyCache $Root
        if ($receipt.dataExisted) { throw '本轮产物已逆向处理；部署前已存在的data已保留，属于部分恢复。原点继续保留供核对。' }
        if ((Get-InventoryDigest (Get-ArtifactInventory $Root) -IncludeAcl) -cne (Get-InventoryDigest $receipt.before -IncludeAcl)) { throw '仍有未知或变更产物，部分恢复；原点保留。' }
        $receipt.status = 'complete'
        Save-Origin $Root $receipt
        Write-Host ('反部署完成；原点：' + (Get-OriginLocation $Root))
        if ($receipt.undo.backup) { Write-Host ('数据备份：' + $receipt.undo.backup.path) }
    } finally { Exit-OriginLock $lock }
}
# 外置缓存位置由项目路径标识，保留原有工具与真正共享资源。
function Get-DependencyCacheRoot([string]$Root) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $id = ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Root)))).Replace('-','').ToLowerInvariant() }
    finally { $sha.Dispose() }
    $base = $env:LOCALAPPDATA
    if (-not $base) { $base = Join-Path ([Environment]::GetFolderPath('UserProfile')) '.cache' }
    $cache = [IO.Path]::GetFullPath((Join-Path $base "AcademicServices/deployment/project-$id"))
    Assert-PlainPath $cache
    if ($cache.StartsWith($Root.TrimEnd('\','/') + [IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) { throw '依赖缓存必须位于项目外。' }
    return $cache
}
# 缓存也有独立before/after和原件，普通共享或后改内容阻断恢复。
function Restore-DependencyCache([string]$Root) {
    $pointer = Join-Path (Get-OriginLocation $Root) 'dependency-cache-root.txt'
    Assert-PlainPath $pointer
    if (-not (Test-Path -LiteralPath $pointer)) { return }
    $cache = Get-DependencyCacheRoot $Root
    if ([IO.File]::ReadAllText($pointer).Trim() -cne $cache) { throw '外置缓存所属项目位置已变化，保留原件。' }
    foreach ($process in @(Get-Process)) {
        try { $path=$process.Path } catch { continue }
        if ($path -and $path.StartsWith($cache.TrimEnd('\','/') + [IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) { throw '专属依赖缓存仍有进程使用，未清理。' }
    }
    Invoke-OriginUndo $cache 'clear'
}
# END JOBS DEPLOYMENT LIFECYCLE

function Show-UndoIntroduction {
    Write-Host '知序服务 | Windows 反部署' -ForegroundColor Red
    Write-Host '按部署原点核对 .runtime、.tools、data 及登记的项目外专属缓存，默认备份至后端实现目录外的 UndeploymentBackups，再清理本次新建的数据。' -ForegroundColor Blue
    Write-Host '先关闭部署运行窗口。原有数据/共享或已改变资源保留，外部PostgreSQL没有原生备份能力时停止全部操作。'
    Write-Host 'fzf方向键/Tab选择；Esc取消。最后确认默认取消，选中执行后还须按空格复核。'
    Write-Host '取消不停止进程、不创建日志/备份或修改业务。原点及重试记录保留在 .deployment-state/windows。'
    Write-Host ('目标：' + $ServerRoot)
    if ($Check -or $Plan) { return }
    if ([Console]::IsInputRedirected) { throw '请使用交互终端。' }
    if ((Read-JobsEnterChoiceHost '按回车审阅；任意字符取消').Length) { throw '已取消。' }
}

function Find-UndoSelector {
    $candidates = @($env:FZF_BIN)
    $command = Get-Command fzf -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) { $candidates += $command.Source }
    $candidates += @(Get-ChildItem -LiteralPath (Join-Path $ServerRoot '.tools') -Filter 'fzf.exe' -Recurse -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
    $pointer=Join-Path (Get-OriginLocation $ServerRoot) 'dependency-cache-root.txt'
    if (Test-Path -LiteralPath $pointer) {
        $cache=Get-DependencyCacheRoot $ServerRoot
        Assert-PlainPath $pointer
        if ([IO.File]::ReadAllText($pointer).Trim() -cne $cache) { throw '外置缓存路径归属不符，未运行缓存工具。' }
        $cacheReceipt=Read-Origin $cache
        if ($cacheReceipt) {
            foreach ($row in @($cacheReceipt.after)) {
                if ($row.path -notmatch '^\.tools/fzf/windows-(amd64|arm64)/[^/]+/fzf\.exe$') { continue }
                $candidate=Join-Path $cache $row.path
                Assert-PlainPath $candidate
                if ((Test-Path -LiteralPath $candidate -PathType Leaf) -and (Get-FileHash -LiteralPath $candidate -Algorithm SHA256).Hash -ceq $row.hash) { $candidates += $candidate }
            }
        }
    }
    foreach ($candidate in $candidates) {
        if (-not $candidate -or -not (Test-Path -LiteralPath $candidate -PathType Leaf)) { continue }
        Assert-PlainPath $candidate
        & $candidate --version 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) { return $candidate }
    }
    throw '缺少健康fzf；请复用部署准备的工具或提供FZF_BIN。本入口不为反部署联网安装。'
}

function Select-UndoOption([string]$Fzf,[string[]]$Rows,[string]$Title) {
    $keys = @('FZF_DEFAULT_OPTS','FZF_DEFAULT_OPTS_FILE','FZF_DEFAULT_COMMAND')
    $saved = @{}
    $oldOutput = $OutputEncoding
    $oldIn = [Console]::InputEncoding
    $oldOut = [Console]::OutputEncoding
    try {
        foreach ($key in $keys) { $saved[$key] = [Environment]::GetEnvironmentVariable($key,'Process'); [Environment]::SetEnvironmentVariable($key,'','Process') }
        $utf8 = New-Object Text.UTF8Encoding($false)
        $OutputEncoding = $utf8
        [Console]::InputEncoding = $utf8
        [Console]::OutputEncoding = $utf8
        $selection = $Rows | & $Fzf --no-multi --layout=reverse --height=45% --border '--delimiter=|' --with-nth=2 '--bind=tab:down,btab:up' "--header=$Title"
        $code = $LASTEXITCODE
    } finally {
        foreach ($key in $keys) { [Environment]::SetEnvironmentVariable($key,$saved[$key],'Process') }
        $OutputEncoding = $oldOutput
        [Console]::InputEncoding = $oldIn
        [Console]::OutputEncoding = $oldOut
    }
    if ($code -in @(1,130)) { return 'cancel' }
    if ($code -ne 0 -or @($selection).Count -ne 1 -or $Rows -cnotcontains $selection) { throw '选择器错误、空选或非法输出，未执行。' }
    return ($selection -split '\|',2)[0]
}

function Main {
    Show-UndoIntroduction
    if ($Check -and $Plan) { throw '-Check与-Plan不能同时使用。' }
    $receipt = Read-Origin $ServerRoot
    if (-not $receipt) { throw '没有本工程Windows原点；旧部署归属无法证明，未删除。' }
    if ($Check -or $Plan) {
        Write-Host ('原点状态：' + $receipt.status)
        Write-Host ('原有data：' + $receipt.dataExisted + '；数据库：' + $receipt.database)
        Write-Host '计划：只核对清单内资源；备份完整data及账户配置。备份损坏、内容变化、未知锁、外部数据库均保留并停止。'
        return
    }
    if ($env:OS -ne 'Windows_NT') { throw '实际反部署仅支持Windows；当前系统仅支持-Check/-Plan。' }
    if ($receipt.status -eq 'complete') { Write-Host '此原点已完成，无需重复清理。'; return }
    $selector = Find-UndoSelector
    $policy = Select-UndoOption $selector @('backup|数据库数据备份（默认）：完整data和配置，验证后清理本次新建源数据','clear|数据库数据清零：不备份，不可恢复','cancel|取消并保留当前状态') '选择数据策略；Esc取消'
    if ($policy -eq 'cancel') { return }
    Write-Host ('准确数据范围：' + (Join-Path $ServerRoot 'data'))
    Write-Host ('程序/配置/依赖范围：' + (Join-Path $ServerRoot '.runtime') + '；' + (Join-Path $ServerRoot '.tools'))
    $cachePointer=Join-Path (Get-OriginLocation $ServerRoot) 'dependency-cache-root.txt'
    if (Test-Path -LiteralPath $cachePointer) { Write-Host ('外置专属依赖范围：' + [IO.File]::ReadAllText($cachePointer).Trim() + '；仅按子收据精确恢复。') }
    Write-Host ('原有data：' + $receipt.dataExisted + '；原有/共享/未知对象保留；原点文件不清除。')
    $confirm = Select-UndoOption $selector @('cancel|取消，保留当前状态','execute|确认按上述数据策略反部署') '危险操作：默认取消；请核对范围'
    if ($confirm -ne 'execute') { return }
    Write-Host '最后复核：按空格执行；其它键取消。' -ForegroundColor Red
    if ([Console]::ReadKey($true).Key -ne [ConsoleKey]::Spacebar) { return }
    Invoke-OriginUndo $ServerRoot $policy
}

if ($MyInvocation.InvocationName -ne '.') {
    try { Main } catch { Write-Host $_.Exception.Message -ForegroundColor Red; exit 1 }
}

# END JOBS_TERMINAL_STYLE_ORIGINAL_BODY
} finally {
    Stop-JobsTerminalStyle $__jobsTerminalStyleState
}
