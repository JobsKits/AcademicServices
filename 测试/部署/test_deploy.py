"""Read-only/sandbox deployment regressions, never installs system packages."""
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
            p=Path(temp);fake=p/'fake';fake.mkdir();log=p/'calls';log.write_text('')
            if fake_go:
                f=fake/'go';f.write_text('#!/bin/sh\n'+fake_go);f.chmod(0o755)
            prefix=MAC_ENTRY.read_text().rsplit('main "$@"',1)[0]
            script=p/'fixture.zsh';script.write_text(prefix+f'\nSERVER_ROOT="{p}"\nLOG_FILE="{log}"\n'+body+'\n')
            env={**os.environ,'GO_BIN':str(fake/'go') if fake_go else '', 'PATH':str(fake)+':/usr/bin:/bin:/usr/sbin:/sbin'}
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
            lines=p.read_text().split('\nmain() {',1)[1].split('}',1)[0].strip().splitlines()
            self.assertTrue(lines[0].strip().startswith('show_script_intro_and_wait'),p)
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
        self.assertNotEqual(result.returncode,0);self.assertIn('Go下载失败',log);self.assertNotIn('unexpected',result.stdout)
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
