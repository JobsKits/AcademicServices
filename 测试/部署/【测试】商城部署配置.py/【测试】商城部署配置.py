#!/usr/bin/env python3
"""仅在临时目录执行真实部署配置函数；不执行部署主流程或连接公网。"""

from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[3]
PLATFORMS = ("MacOS", "Windows", "Ubuntu", "Debian", "RockyLinux", "AlibabaCloudLinux", "Alpine", "FreeBSD")


def entry(platform: str) -> Path:
    name = {"MacOS": "【MacOS】部署.command", "Windows": "【Windows】部署.ps1", "FreeBSD": "【FreeBSD】部署.sh"}.get(platform, "【Linux】部署.sh")
    return ROOT / "部署" / platform / name / name


def shell_function(source: str, name: str) -> str:
    lines = source.splitlines()
    first = lines.index(name + "() {")
    last = next(index for index in range(first + 1, len(lines)) if lines[index] == "}")
    return "\n".join(lines[first:last + 1])


def hashes(root: Path) -> dict[str, str]:
    return {str(path.relative_to(root)): hashlib.sha256(path.read_bytes()).hexdigest()
            for path in root.rglob("*") if path.is_file()}


class ShopDeploymentTests(unittest.TestCase):
    def fixture(self, root: Path, client: bool, admin: bool):
        code = root / "中文 空格 改名工程/代码"
        server = code / "后端/后端代码"
        config = server / ".runtime/config.env"
        config.parent.mkdir(parents=True)
        config.write_text("APP_ENV=production\nLISTEN_ADDR=0.0.0.0:18080\n"
                          "ADMIN_PASSWORD=fixture-admin-only\nDEMO_CUSTOMER_PASSWORD=fixture-customer-only\n"
                          "DATABASE_URL=\nCORS_ORIGINS=https://fixture.invalid\n")
        paths = {
            "client": code / "前端/移动端/Flutter/Dist/ShopClient",
            "admin": code / "前端/后台管理端/Flutter/Dist/ShopAdmin",
            "fallback_client": server / "client-web",
            "fallback_admin": server / "admin-web",
        }
        for key, path in paths.items():
            path.mkdir(parents=True)
            if key.startswith("fallback_") or (key == "client" and client) or (key == "admin" and admin):
                (path / "index.html").write_text(key)
        (server / "data").mkdir()
        (server / "data/state.json").write_text('{"fixture":"must remain unchanged"}')
        return code, server, paths

    def run_case(self, platform: str, mode: str, client: bool, admin: bool):
        with tempfile.TemporaryDirectory(prefix="商城部署 只读配置 ") as temp:
            root = Path(temp)
            code, server, paths = self.fixture(root, client, admin)
            env = {**os.environ, "DEMO_MODE": "1" if mode == "server" else "0", "PAYMENT_MODE": "real"}
            if platform == "Windows":
                executable = shutil.which("pwsh")
                if not executable:
                    self.skipTest("未安装PowerShell；不把静态检查计为Windows配置行为通过")
                source = r'''
param($Source, $Code, $Server, $Mode)
$ErrorActionPreference = 'Stop'
$tokens=$null; $errors=$null
$ast=[System.Management.Automation.Language.Parser]::ParseFile($Source,[ref]$tokens,[ref]$errors)
if ($errors.Count) { throw ($errors | Out-String) }
foreach ($name in @('Select-StaticRoots','Configure-Server','Prepare-SelectedMode')) {
    $definition=$ast.Find({param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name},$true)
    if (-not $definition) { throw "Missing function: $name" }
    Invoke-Expression $definition.Extent.Text
}
function Ensure-LocalTool { 'fixture-cloudflared-never-executed' }
function Write-TerminalLifetimeNotice {}
function Read-Host { '' }
$CodeRoot=$Code; $ServerRoot=$Server; $DeployMode=$Mode
Configure-Server
Prepare-SelectedMode
@{demo=$env:DEMO_MODE; payment=$env:PAYMENT_MODE; client=$env:CLIENT_STATIC_DIR; admin=$env:ADMIN_STATIC_DIR;
  listen=$env:LISTEN_ADDR; cors=$env:CORS_ORIGINS} | ConvertTo-Json -Compress | ForEach-Object { 'RESULT:' + $_ }
'''
                script = root / "配置夹具.ps1"
                script.write_text(source)
                command = [executable, "-NoLogo", "-NoProfile", "-File", str(script), str(entry(platform)), str(code), str(server), mode]
            else:
                executable = shutil.which("zsh" if platform == "MacOS" else "sh" if platform in {"Alpine", "FreeBSD"} else "bash")
                self.assertIsNotNone(executable)
                source = entry(platform).read_text()
                names = ["select_static_roots", "configure_server", "prepare_selected_mode"]
                if platform == "MacOS":
                    names += ["prepare_password_policy", "ensure_configured_passwords", "read_password", "save_configured_passwords"]
                script = root / "配置夹具.sh"
                script.write_text("\n".join(shell_function(source, name) for name in names) + '''
log() { printf '%s\\n' "$1"; }
fail() { printf '%s\\n' "$1" >&2; exit 91; }
ensure_local_tool() { :; }
log_terminal_lifetime_notice() { :; }
CODE_ROOT="$1"; SERVER_ROOT="$2"; DEPLOY_MODE="$3"
configure_server
prepare_selected_mode
printf '\\n'
printf 'RESULT:%s\\n' "$DEMO_MODE" "$PAYMENT_MODE" "$CLIENT_STATIC_DIR" "$ADMIN_STATIC_DIR" "$LISTEN_ADDR" "$CORS_ORIGINS"
''')
                command = [executable, str(script), str(code), str(server), mode]
            # 夹具脚本属于测试准备文件；业务配置函数执行期间不应再写任何文件。
            before = hashes(root)
            completed = subprocess.run(command, cwd="/", env=env, input="\n", capture_output=True, text=True, timeout=20)
            self.assertEqual(completed.returncode, 0, completed.stdout + completed.stderr)
            self.assertEqual(before, hashes(root), "配置/数据/静态页面不应被覆盖或增加文件")
            self.assertNotIn("fixture-admin-only", completed.stdout + completed.stderr)
            self.assertNotIn("fixture-customer-only", completed.stdout + completed.stderr)
            values = [line.removeprefix("RESULT:") for line in completed.stdout.splitlines() if line.startswith("RESULT:")]
            if platform == "Windows":
                result = json.loads(values[0])
            else:
                result = dict(zip(("demo", "payment", "client", "admin", "listen", "cors"), values))
            self.assertEqual(result["demo"], "1" if mode == "local" else "0")
            self.assertEqual(result["payment"], "mock" if mode == "local" else "real")
            self.assertEqual(Path(result["client"]), paths["client" if client else "fallback_client"])
            self.assertEqual(Path(result["admin"]), paths["admin" if admin else "fallback_admin"])
            self.assertEqual(result["listen"], "127.0.0.1:18080" if mode == "local" else "0.0.0.0:18080")
            self.assertEqual(result["cors"] or "", "" if mode == "local" else "https://fixture.invalid")

    def windows_restore(self, mode: str, inherited: bool):
        executable = shutil.which("pwsh")
        if not executable:
            self.skipTest("未安装PowerShell；环境恢复行为待原生验证")
        source = r'''
param($Source, $Mode, $Inherited)
$ErrorActionPreference='Stop'
$t=$null; $e=$null
$ast=[System.Management.Automation.Language.Parser]::ParseFile($Source,[ref]$t,[ref]$e)
foreach ($name in @('Prepare-SelectedMode','Main')) {
    $definition=$ast.Find({param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name},$true)
    Invoke-Expression $definition.Extent.Text
}
foreach ($name in @('Show-Intro','Test-Source','Start-Origin','Initialize-Runtime','Ensure-Go','Build-AccessQr',
                   'Start-Server','Start-LocalTunnel','Stop-OwnedProcesses','Expire-AccessQr','Stop-Transcript',
                   'Complete-Origin','Exit-OriginLock','Write-TerminalLifetimeNotice')) {
    Set-Item -Path "Function:$name" -Value { }
}
function Enter-OriginLock { 'fixture-lock' }
function Ensure-LocalTool { 'fixture-cloudflared' }
function Read-Host { '' }
function Select-DeploymentMode { $script:DeployMode=$Mode }
function Configure-Server { $env:LISTEN_ADDR='127.0.0.1:18080' }
function Build-Server { if ($Mode -eq 'local') { throw 'fixture-build-failure' } }
$ServerRoot=Join-Path ([IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString()); $Check=$false; $Plan=$false
if ($Inherited -eq '1') { $env:DEMO_MODE='inherited-demo'; $env:PAYMENT_MODE='inherited-payment' }
else { Remove-Item Env:DEMO_MODE,Env:PAYMENT_MODE -ErrorAction SilentlyContinue }
$before=@{}; foreach ($key in @('DEMO_MODE','PAYMENT_MODE')) { $before[$key]=[Environment]::GetEnvironmentVariable($key,'Process') }
try {
    try { Main } catch { if ($_.Exception.Message -ne 'fixture-build-failure') { throw } }
    foreach ($key in @('DEMO_MODE','PAYMENT_MODE')) {
        if ([Environment]::GetEnvironmentVariable($key,'Process') -cne $before[$key]) { throw "Environment leaked: $key" }
    }
    'RESTORED'
} finally { if (Test-Path -LiteralPath $ServerRoot) { Remove-Item -LiteralPath $ServerRoot -Recurse -Force } }
'''
        with tempfile.TemporaryDirectory(prefix="商城 Windows 环境恢复 ") as temp:
            script = Path(temp) / "环境恢复.ps1"
            script.write_text(source)
            result = subprocess.run([executable, "-NoLogo", "-NoProfile", "-File", str(script), str(entry("Windows")), mode, "1" if inherited else "0"],
                                    capture_output=True, text=True, timeout=20)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("RESTORED", result.stdout)


def syntax_test(platform):
    def test(self):
        if platform == "Windows":
            executable = shutil.which("pwsh")
            if not executable:
                self.skipTest("未安装PowerShell Parser")
            quoted = str(entry(platform)).replace("'", "''")
            command = [executable, "-NoLogo", "-NoProfile", "-Command", "$t=$null;$e=$null;[System.Management.Automation.Language.Parser]::ParseFile('" + quoted + "',[ref]$t,[ref]$e)|Out-Null;$e|ForEach-Object {$_.Message};if($e.Count){exit 1}"]
        else:
            executable = shutil.which("zsh" if platform == "MacOS" else "sh" if platform in {"Alpine", "FreeBSD"} else "bash")
            self.assertIsNotNone(executable)
            command = [executable, "-n", str(entry(platform))]
        result = subprocess.run(command, capture_output=True, text=True, timeout=20)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
    return test


def configuration_test(platform, mode, client, admin):
    def test(self):
        self.run_case(platform, mode, client, admin)
    return test


def restore_test(mode, inherited):
    def test(self):
        self.windows_restore(mode, inherited)
    return test


for platform in PLATFORMS:
    setattr(ShopDeploymentTests, f"test_{platform}_syntax", syntax_test(platform))
    for mode in ("local", "server"):
        setattr(ShopDeploymentTests, f"test_{platform}_{mode}", configuration_test(platform, mode, True, True))
    for client, admin in ((False, False), (True, False), (False, True)):
        setattr(ShopDeploymentTests, f"test_{platform}_static_{int(client)}{int(admin)}", configuration_test(platform, "server", client, admin))
for mode in ("local", "server"):
    for inherited in (False, True):
        setattr(ShopDeploymentTests, f"test_Windows_restore_{mode}_{int(inherited)}", restore_test(mode, inherited))


if __name__ == "__main__":
    unittest.main(verbosity=2)
