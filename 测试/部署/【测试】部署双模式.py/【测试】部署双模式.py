"""Deployment lifecycle checks: fake tools, a disposable loopback service, and a real PTY."""
from pathlib import Path
import json
import os
import pty
import select
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import time
import unittest
import urllib.request

ROOT = next(parent for parent in Path(__file__).resolve().parents if (parent / '代码').is_dir() and (parent / '测试').is_dir())
DEPLOY = ROOT / '部署'
MAC_ENTRY = Path('MacOS/【MacOS】部署.command/【MacOS】部署.command')


class ModeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='知序 双模式 测试 ')
        # MacOS框架Python的启动器会二次exec；假工具直接使用已运行解释器，保持登记身份稳定。
        self.python_bin = subprocess.check_output(['ps', '-p', str(os.getpid()), '-o', 'comm='], text=True).strip()
        self.code_root = Path(self.temp.name) / '中文 空格 工程/代码'
        self.root = self.code_root / '后端/后端代码'
        self.root.mkdir(parents=True)
        self.deploy_root = self.code_root.parent / '部署'
        shutil.copytree(DEPLOY, self.deploy_root)
        (self.root / 'cmd/server').mkdir(parents=True)
        (self.root / 'go.mod').write_text('module fixture\ngo 1.27\n')
        (self.root / '.runtime').mkdir()
        self.port = self.free_port()
        (self.root / '.runtime/config.env').write_text(
            'APP_ENV=production\nLISTEN_ADDR=127.0.0.1:' + str(self.port)
            + '\nADMIN_PASSWORD=fixture-admin-password\nDEMO_CUSTOMER_PASSWORD=fixture-customer-password\nDATABASE_URL=\nCORS_ORIGINS=\n')
        self.tools = Path(self.temp.name) / '假工具 有空格'
        self.tools.mkdir()
        self.calls = Path(self.temp.name) / 'calls'
        self.calls.write_text('')
        self.write_tool('fzf', """
import json, os, sys
if os.environ.get('FZF_DEFAULT_OPTS') or os.environ.get('FZF_DEFAULT_OPTS_FILE') or os.environ.get('FZF_DEFAULT_COMMAND'): sys.exit(91)
if '--version' in sys.argv: print('0.74.5 fixture'); sys.exit(0)
if '--help' in sys.argv: print('--height --accept-nth'); sys.exit(0)
sys.stdin.read()
with open(os.environ['CALLS'], 'a') as f: f.write('fzf:' + json.dumps([os.environ.get('FZF_DEFAULT_OPTS'), os.environ.get('FZF_DEFAULT_OPTS_FILE')]) + '\\n')
print(os.environ.get('FZF_OUT', 'local'))
sys.exit(int(os.environ.get('FZF_EXIT', '0')))
""")
        self.write_tool('go', """
import os, shutil, sys
if sys.argv[1:] == ['version']: print('go version go1.27.3 darwin/arm64'); sys.exit(0)
with open(os.environ['CALLS'], 'a') as f: f.write('build\\n')
if os.path.basename(os.getcwd()) == '地址二维码':
    if os.environ.get('QR_BUILD_FAIL') == '1': sys.exit(29)
    source = os.environ['QR_TEMPLATE']
else: source = os.environ['SERVER_TEMPLATE']
shutil.copy2(source, sys.argv[sys.argv.index('-o') + 1])
""")
        self.write_tool('cloudflared', """
import os, signal, sys, time
if '--version' in sys.argv: print('cloudflared fixture'); sys.exit(0)
if '--help' in sys.argv: print('--url --config --no-autoupdate'); sys.exit(0)
assert '--config' in sys.argv
assert not any(key.startswith('TUNNEL_') for key in os.environ)
with open(sys.argv[sys.argv.index('--config') + 1]) as config: assert config.read() == '{}\\n'
with open(os.environ['CALLS'], 'a') as f: f.write('tunnel:' + str(os.getpid()) + '\\n')
if os.environ.get('IGNORE_TERM') == '1': signal.signal(signal.SIGTERM, signal.SIG_IGN)
if os.environ.get('NO_URL') != '1': print('https://academic-fixture.trycloudflare.com', flush=True)
if os.environ.get('QR_CHANGE') == '1': time.sleep(1); print('https://fixture-changed.trycloudflare.com', flush=True)
if os.environ.get('FIXTURE_TUNNEL_EXIT') == '1': time.sleep(.3); sys.exit(17)
while True: time.sleep(.1)
""")
        self.write_tool('server-template', """
import http.server, os, signal, socketserver, sys, time
with open(os.environ['CALLS'], 'a') as f: f.write('server:' + str(os.getpid()) + '\\n')
if os.environ.get('SERVER_EXIT') == '1':
    print('data directory is already locked; fixture startup failure', flush=True)
    print('credentials: ' + os.environ['ADMIN_PASSWORD'] + ' ' + os.environ['DEMO_CUSTOMER_PASSWORD'], flush=True)
    sys.exit(19)
if os.environ.get('IGNORE_TERM') == '1': signal.signal(signal.SIGTERM, signal.SIG_IGN)
class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200); self.end_headers(); self.wfile.write(b'{"status":"ok"}')
    def log_message(self, *args): pass
class Server(socketserver.TCPServer): allow_reuse_address=True
with Server(('127.0.0.1', int(os.environ['LISTEN_ADDR'].split(':')[-1])), Handler) as server: server.serve_forever(poll_interval=.1)
""")
        self.write_tool('qr-template', """
import os, pathlib, sys
out = pathlib.Path(sys.argv[sys.argv.index('--output-dir') + 1]); out.mkdir(exist_ok=True)
if '--expire' in sys.argv:
    (out / 'index.html').write_text('expired')
else:
    if os.environ.get('QR_GENERATE_FAIL') == '1': sys.exit(31)
    entries = [sys.argv[i+1] for i, arg in enumerate(sys.argv) if arg == '--entry']
    (out / 'index.html').write_text('\\n'.join(entries))
    (out / '01.svg').write_text('fixture-svg')
    print('本地二维码页面（浏览器打开）：' + str(out / 'index.html'), flush=True)
""")
        self.env = {**os.environ, 'GO_BIN': str(self.tools / 'go'), 'FZF_BIN': str(self.tools / 'fzf'),
                    'CLOUDFLARED_BIN': str(self.tools / 'cloudflared'), 'CALLS': str(self.calls),
                    'SERVER_TEMPLATE': str(self.tools / 'server-template'), 'QR_TEMPLATE': str(self.tools / 'qr-template'), 'TERM': 'xterm',
                    'FZF_DEFAULT_OPTS': '--filter=server --bind=start:execute(touch invalid)',
                    'FZF_DEFAULT_OPTS_FILE': '/not/a/real/file', 'TUNNEL_START_TIMEOUT': '15', 'TUNNEL_NAME': 'must-not-reach-cloudflared',
                    'TUNNEL_HOSTNAME': 'fixture.invalid', 'TUNNEL_TOKEN': 'synthetic-test-value', 'TUNNEL_CONFIG': '/not/a/user/file'}
        self.process = None
        self.master = None
        self.output = ''
        self.sessions = []

    @staticmethod
    def free_port():
        with socket.socket() as sock:
            sock.bind(('127.0.0.1', 0))
            return sock.getsockname()[1]

    def write_tool(self, name, source):
        target = self.tools / name
        target.write_text('#!' + self.python_bin + '\n' + source)
        target.chmod(0o755)

    def start(self, mode='local', *, controlling_terminal=False, terminal_parent=False, **changes):
        master, slave = pty.openpty()
        self.master = master
        env = {**self.env, 'FZF_OUT': mode, **changes}
        command = ['zsh', str(self.deploy_root / MAC_ENTRY)]
        if controlling_terminal:
            command = [sys.executable, '-c',
                       'import fcntl, os, sys, termios; '
                       'fcntl.ioctl(0, termios.TIOCSCTTY, 0); '
                       'os.tcsetpgrp(0, os.getpgrp()); '
                       'os.execvp(sys.argv[1], sys.argv[1:])', *command]
        if terminal_parent:
            command = [sys.executable, '-c',
                       'import subprocess, sys; '
                       'child = subprocess.Popen(sys.argv[1:]); '
                       'sys.exit(child.wait())', *command]
        self.process = subprocess.Popen(command,
                                        stdin=slave, stdout=slave, stderr=slave, cwd='/', env=env,
                                        start_new_session=True)
        os.close(slave)
        os.write(master, b'\n\n')
        self.sessions.append((self.process, master))
        return self.process

    def read_until(self, text=None, timeout=90):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            ready, _, _ = select.select([self.master], [], [], .1)
            if ready:
                try: data = os.read(self.master, 65536)
                except OSError: data = b''
                if data: self.output += data.decode('utf-8', errors='replace')
            if text and text in self.output: return
            if self.process.poll() is not None:
                if not text: return
                break
        if text: self.fail('Missing ' + text + '\n' + self.output)
        if self.process.poll() is None: self.fail('Process timeout\n' + self.output)

    def assert_children_stopped(self):
        for line in self.calls.read_text().splitlines():
            if line.startswith(('server:', 'tunnel:')):
                with self.assertRaises(ProcessLookupError, msg=line): os.kill(int(line.split(':')[1]), 0)

    def child_pids(self):
        return [int(line.split(':')[1]) for line in self.calls.read_text().splitlines()
                if line.startswith(('server:', 'tunnel:'))]

    def wait_until(self, predicate, description, timeout=20):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if predicate():
                return
            time.sleep(.05)
        self.fail(description + '\n' + self.output)

    @staticmethod
    def process_running(pid):
        result = subprocess.run(['ps', '-p', str(pid), '-o', 'stat='],
                                capture_output=True, text=True)
        return result.returncode == 0 and not result.stdout.strip().startswith('Z')

    def assert_health(self):
        with urllib.request.urlopen(f'http://127.0.0.1:{self.port}/healthz', timeout=2) as response:
            self.assertEqual(response.status, 200)

    def close_master(self):
        closed = self.master
        os.close(closed)
        self.sessions = [(process, None if master == closed else master)
                         for process, master in self.sessions]
        self.master = None

    def tearDown(self):
        for process, _ in self.sessions:
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()
        for line in self.calls.read_text().splitlines():
            if line.startswith(('server:', 'tunnel:')):
                try: os.kill(int(line.split(':')[1]), signal.SIGKILL)
                except ProcessLookupError: pass
        # 失败清理也只终止本临时工程记录且身份仍匹配的会话进程。
        state = self.root / '.deployment-state/posix'
        for pid_file in [state / 'processes/wrapper.pid', state / 'processes/guard.pid',
                         *state.glob('sessions/session.*/guard.pid')]:
            identity_file = pid_file.with_suffix('.identity')
            if not pid_file.is_file() or not identity_file.is_file():
                continue
            guard_pid = int(pid_file.read_text().strip())
            current = subprocess.run(['ps', '-p', str(guard_pid), '-o', 'lstart=', '-o', 'args='],
                                     capture_output=True, text=True).stdout
            is_fixture = (str(self.deploy_root / MAC_ENTRY) in current or
                          str((self.deploy_root / MAC_ENTRY).resolve()) in current)
            if current == identity_file.read_text() and is_fixture:
                try: os.kill(guard_pid, signal.SIGTERM)
                except ProcessLookupError: pass
        for _, master in self.sessions:
            if master is not None:
                try: os.close(master)
                except OSError: pass
        self.temp.cleanup()

    def test_01_read_only_check_and_plan(self):
        before = sorted(str(p.relative_to(self.code_root)) for p in self.code_root.rglob('*'))
        for arg in ('--check', '--plan'):
            result = subprocess.run(['zsh', str(self.deploy_root / MAC_ENTRY), arg], cwd='/', env=self.env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(before, sorted(str(p.relative_to(self.code_root)) for p in self.code_root.rglob('*')))
        self.assertEqual(self.calls.read_text(), '')

    def test_02_cancel_empty_unknown_multiline_and_failure(self):
        for mode, code in [('', '0'), ('unexpected', '0'), ('local\nserver', '0'), ('local', '130'), ('local', '2')]:
            with self.subTest(mode=mode, code=code):
                self.start(mode, FZF_EXIT=code)
                self.read_until()
                self.assertNotEqual(self.process.returncode, 0, self.output)
                self.assertNotIn('build', self.calls.read_text())
                self.assertFalse((self.root / 'data').exists())
                self.close_master(); self.process = None; self.output = ''

    def test_03_local_health_then_url_and_interrupt_cleanup(self):
        self.start(NO_COLOR='')
        self.read_until('地址已生成不等于公网验收')
        notice = '关闭此运行终端，服务将结束'
        self.assertEqual(self.output.count(notice), 2, self.output)
        self.assertEqual(self.output.count('\x1b[1;31m' + notice + '\x1b[0m'), 2, self.output)
        main_log = next(p for p in (self.root / '.runtime/logs').glob('deploy-*.log') if not p.name.endswith(('.server.log', '.tunnel.log')))
        logged = main_log.read_text()
        self.assertEqual(logged.count(notice), 2)
        self.assertNotIn('\x1b', logged)
        calls = self.calls.read_text()
        self.assertIn('fzf:["", ""]', calls)
        qr_page = next((self.root / '.runtime').glob('access-qr.*/index.html'))
        self.assertIn('用户端|https://academic-fixture.trycloudflare.com/client/', qr_page.read_text())
        self.assertIn('管理端|https://academic-fixture.trycloudflare.com/admin/', qr_page.read_text())
        self.assertLess(calls.index('server:'), calls.index('tunnel:'))
        os.kill(self.process.pid, signal.SIGINT)
        self.read_until(timeout=10)
        self.assertEqual(self.process.returncode, 130, self.output)
        self.assertEqual(qr_page.read_text(), 'expired')
        # 运行结束时，本轮新增二维码必须进入最终归属清单。
        manifests = list((self.root / '.deployment-state').rglob('after.tsv'))
        self.assertTrue(any('access-qr.' in item.read_text() for item in manifests))
        self.assert_children_stopped()

    def test_04_occupied_non_http_port_never_published(self):
        with socket.socket() as occupied:
            occupied.bind(('127.0.0.1', self.port)); occupied.listen()
            self.start(); self.read_until()
            self.assertNotEqual(self.process.returncode, 0)
            self.assertIn('端口已有', self.output)
            self.assertNotIn('server:', self.calls.read_text())
            self.assertNotIn('tunnel:', self.calls.read_text())

    def test_05_url_timeout_reaps_children(self):
        self.start(NO_URL='1', TUNNEL_START_TIMEOUT='2'); self.read_until()
        self.assertIn('隧道地址等待超时', self.output)
        self.assert_children_stopped()

    def test_06_tunnel_exit_reaps_backend(self):
        self.start(FIXTURE_TUNNEL_EXIT='1'); self.read_until()
        self.assertNotEqual(self.process.returncode, 0)
        self.assert_children_stopped()

    def test_07_backend_exit_never_starts_tunnel(self):
        self.start(SERVER_EXIT='1'); self.read_until(timeout=90)
        self.assertIn('data directory is already locked', self.output)
        self.assertIn('后端启动诊断', self.output)
        self.assertIn('[已隐藏]', self.output)
        self.assertNotIn('fixture-admin-password', self.output)
        self.assertNotIn('fixture-customer-password', self.output)
        main_log = next(p for p in (self.root / '.runtime/logs').glob('deploy-*.log') if not p.name.endswith(('.server.log', '.tunnel.log')))
        self.assertIn('data directory is already locked', main_log.read_text())
        self.assertNotIn('fixture-admin-password', main_log.read_text())
        self.assertNotIn('fixture-customer-password', main_log.read_text())
        self.assertNotIn('tunnel:', self.calls.read_text())
        self.assert_children_stopped()

    def test_local_hangup_reaps_children(self):
        self.start()
        self.read_until('地址已生成不等于公网验收')
        os.kill(self.process.pid, signal.SIGHUP)
        self.read_until(timeout=30)
        self.assertEqual(self.process.returncode, 130, self.output)
        self.assert_children_stopped()

    def test_08_ignored_term_has_bounded_cleanup(self):
        # 等待地址完整输出后再测退出，避免信号落在启动展示尚未结束时。
        self.start(IGNORE_TERM='1'); self.read_until('地址已生成不等于公网验收')
        began = time.monotonic(); os.kill(self.process.pid, signal.SIGTERM)
        self.read_until(timeout=10)
        self.assertLess(time.monotonic() - began, 9)
        self.assert_children_stopped()

    def test_09_server_mode_never_starts_tunnel(self):
        self.start('server'); self.read_until('启动｜监听')
        self.assertNotIn('关闭此运行终端，服务将结束', self.output)
        self.assertNotIn('tunnel:', self.calls.read_text())
        os.killpg(self.process.pid, signal.SIGINT)
        self.read_until(timeout=8)
        self.assert_children_stopped()


    def test_qr_address_change_replaces_previous_page(self):
        self.start(QR_CHANGE='1')
        self.read_until('fixture-changed.trycloudflare.com/admin/')
        deadline = time.monotonic() + 5
        pages = []
        while time.monotonic() < deadline:
            pages = list((self.root / '.runtime').glob('access-qr.*/index.html'))
            if pages:
                break
            time.sleep(.05)
        self.assertTrue(pages, self.output)
        qr_page = pages[0]
        while 'fixture-changed.trycloudflare.com' not in qr_page.read_text() and time.monotonic() < deadline:
            time.sleep(.05)
        self.assertIn('https://fixture-changed.trycloudflare.com/client/', qr_page.read_text())
        self.assertNotIn('academic-fixture.trycloudflare.com', qr_page.read_text())
        os.kill(self.process.pid, signal.SIGINT)
        self.read_until(timeout=10)
        self.assertEqual(qr_page.read_text(), 'expired')
        self.assert_children_stopped()

    def test_qr_build_failure_keeps_healthy_service(self):
        self.start(QR_BUILD_FAIL='1')
        self.read_until('地址已生成不等于公网验收')
        self.assertIsNone(self.process.poll(), self.output)
        self.assertIn('二维码辅助工具构建失败', self.output)
        self.assertIn('https://academic-fixture.trycloudflare.com/client/', self.output)
        os.kill(self.process.pid, signal.SIGINT)
        self.read_until(timeout=10)
        self.assert_children_stopped()

    def test_qr_failure_keeps_healthy_service(self):
        self.start(QR_GENERATE_FAIL='1')
        self.read_until('地址已生成不等于公网验收')
        self.assertIsNone(self.process.poll(), self.output)
        self.assertIn('二维码未生成', self.output)
        self.assertIn('https://academic-fixture.trycloudflare.com/client/', self.output)
        os.kill(self.process.pid, signal.SIGINT)
        self.read_until(timeout=10)
        self.assert_children_stopped()

    def test_10_quick_child_isolates_environment_parent_retained(self):
        config = self.root / '.runtime/empty-quick.yml'
        config.write_text('{}\n')
        prefix = (DEPLOY / MAC_ENTRY).read_text().rsplit('main "$@"', 1)[0]
        script = self.root / 'child-env-fixture.zsh'
        script.write_text(prefix + '\nCLOUDFLARED_EXE="$CLOUDFLARED_BIN"\nquick_config="$QUICK_CONFIG"\nLOCAL_URL=http://127.0.0.1:1\nstart_isolated_quick_child >/dev/null 2>&1 &\nchild_pid=$!\nwait "$child_pid" || [ "$?" -eq 17 ]\n[ "$TUNNEL_NAME" = must-not-reach-cloudflared ] && [ "$TUNNEL_CONFIG" = /not/a/user/file ] && [ "$TUNNEL_TOKEN" = synthetic-test-value ]\n')
        result = subprocess.run(['zsh', str(script)], env={**self.env, 'FIXTURE_TUNNEL_EXIT': '1', 'QUICK_CONFIG': str(config)}, capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('tunnel:', self.calls.read_text())
        self.assert_children_stopped()

    def test_restart_stops_previous_session_before_new_service(self):
        self.start()
        self.read_until('地址已生成不等于公网验收')
        previous = self.process
        previous_children = self.child_pids()
        previous_qr = next((self.root / '.runtime').glob('access-qr.*/index.html'))
        config_before = (self.root / '.runtime/config.env').read_bytes()
        marker = self.root / 'data/customer-data.txt'
        marker.write_text('retained business data')
        self.output = ''
        self.start()
        self.read_until('地址已生成不等于公网验收', timeout=45)
        previous.wait(timeout=10)
        self.assertIsNone(self.process.poll(), self.output)
        self.wait_until(lambda: all(not self.process_running(pid) for pid in previous_children),
                        'Previous service and tunnel must stop before restart completes')
        self.assertEqual(previous_qr.read_text(), 'expired')
        self.assertEqual(config_before, (self.root / '.runtime/config.env').read_bytes())
        self.assertEqual(marker.read_text(), 'retained business data')
        self.assert_health()
        os.kill(self.process.pid, signal.SIGINT)
        self.read_until(timeout=10)
        self.assert_children_stopped()

    def test_cancel_or_readonly_restart_keeps_previous_service(self):
        self.start()
        self.read_until('地址已生成不等于公网验收')
        previous = self.process
        previous_children = self.child_pids()
        lock_pid = self.root / '.deployment-state/operation-lock/pid'
        before_pid = lock_pid.read_bytes()
        for arg in ('--check', '--plan'):
            result = subprocess.run(['zsh', str(self.deploy_root / MAC_ENTRY), arg],
                                    cwd='/', env=self.env, capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIsNone(previous.poll())
            self.assert_health()
        self.output = ''
        self.start(FZF_EXIT='130')
        self.read_until(timeout=10)
        self.assertNotEqual(self.process.returncode, 0, self.output)
        self.assertIsNone(previous.poll())
        self.assertEqual(lock_pid.read_bytes(), before_pid)
        self.assertTrue(all(self.process_running(pid) for pid in previous_children))
        self.assert_health()
        os.kill(previous.pid, signal.SIGINT)
        previous.wait(timeout=10)
        self.assert_children_stopped()

    def test_restart_guard_contention_preserves_previous_service(self):
        self.start()
        self.read_until('地址已生成不等于公网验收')
        previous = self.process
        children = self.child_pids()
        lock_pid = self.root / '.deployment-state/operation-lock/pid'
        before_pid = lock_pid.read_bytes()
        restart_guard = self.root / '.deployment-state/restart.guard'
        holder = subprocess.Popen(
            ['zsh', '-c', 'zmodload zsh/system || exit 1; '
             'zsystem flock -f held_fd "$1" || exit 1; '
             'printf "locked\\n"; read -r answer', 'fixture-lock-holder', str(restart_guard)],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        try:
            ready, _, _ = select.select([holder.stdout], [], [], 5)
            self.assertTrue(ready, 'The fixture must hold the native restart lock')
            self.assertEqual(holder.stdout.readline().strip(), 'locked')
            self.output = ''
            self.start()
            self.read_until(timeout=10)
            self.assertNotEqual(self.process.returncode, 0, self.output)
            self.assertIn('另一入口正在接管旧实例', self.output)
            self.assertIsNone(previous.poll())
            self.assertEqual(lock_pid.read_bytes(), before_pid)
            self.assertEqual(self.child_pids(), children)
            self.assert_health()
        finally:
            holder.terminate()
            holder.communicate(timeout=5)
        os.kill(previous.pid, signal.SIGINT)
        previous.wait(timeout=10)
        self.assert_children_stopped()

    def test_closing_controlling_terminal_stops_session(self):
        self.start(controlling_terminal=True)
        self.read_until('地址已生成不等于公网验收')
        children = self.child_pids()
        qr_page = next((self.root / '.runtime').glob('access-qr.*/index.html'))
        self.close_master()
        self.process.wait(timeout=15)
        self.wait_until(lambda: all(not self.process_running(pid) for pid in children),
                        'Closing the controlling PTY must stop owned service and tunnel')
        self.wait_until(lambda: not (self.root / '.deployment-state/operation-lock').exists(),
                        'Closing the terminal must release the deployment lock')
        self.assertEqual(qr_page.read_text(), 'expired')

    def test_killed_wrapper_is_reaped_by_guard_and_can_restart(self):
        self.start()
        self.read_until('地址已生成不等于公网验收')
        children = self.child_pids()
        qr_page = next((self.root / '.runtime').glob('access-qr.*/index.html'))
        os.kill(self.process.pid, signal.SIGKILL)
        self.process.wait(timeout=5)
        self.wait_until(lambda: all(not self.process_running(pid) for pid in children),
                        'The session guard must reap children when the wrapper is killed')
        self.wait_until(lambda: not (self.root / '.deployment-state/operation-lock').exists(),
                        'The dead wrapper lock must be released after owned children stop')
        self.assertEqual(qr_page.read_text(), 'expired')
        self.close_master()
        self.output = ''
        self.start()
        self.read_until('地址已生成不等于公网验收', timeout=45)
        self.assert_health()
        os.kill(self.process.pid, signal.SIGINT)
        self.read_until(timeout=10)

    def test_dead_terminal_parent_stops_session_without_hangup(self):
        self.start(terminal_parent=True)
        self.read_until('地址已生成不等于公网验收')
        children = self.child_pids()
        qr_page = next((self.root / '.runtime').glob('access-qr.*/index.html'))
        wrapper_pid = int((self.root / '.deployment-state/operation-lock/pid').read_text())
        self.assertNotEqual(wrapper_pid, self.process.pid)
        # 父进程没有控制终端，结束它不会产生PTY关窗信号；仅靠会话守护检测。
        os.kill(self.process.pid, signal.SIGKILL)
        self.process.wait(timeout=5)
        self.wait_until(lambda: not self.process_running(wrapper_pid),
                        'The session guard must stop the wrapper after its terminal parent dies')
        self.wait_until(lambda: all(not self.process_running(pid) for pid in children),
                        'The parent-death fallback must stop owned service and tunnel')
        self.wait_until(lambda: not (self.root / '.deployment-state/operation-lock').exists(),
                        'The parent-death fallback must release the deployment lock')
        self.assertEqual(qr_page.read_text(), 'expired')

    def test_guard_survives_wrapper_kill_during_graceful_cleanup(self):
        self.start(IGNORE_TERM='1')
        self.read_until('地址已生成不等于公网验收')
        children = self.child_pids()
        state = self.root / '.deployment-state/posix'
        session = next((state / 'sessions').iterdir())
        qr_page = next((self.root / '.runtime').glob('access-qr.*/index.html'))
        os.kill(self.process.pid, signal.SIGTERM)
        self.wait_until(lambda: (session / 'stopping').exists(),
                        'Graceful cleanup must announce its stopping phase', timeout=10)
        self.assertIsNone(self.process.poll(), 'Ignored TERM must leave a real cleanup window')
        os.kill(self.process.pid, signal.SIGKILL)
        self.process.wait(timeout=5)
        self.wait_until(lambda: all(not self.process_running(pid) for pid in children),
                        'The guard must survive a wrapper killed during graceful cleanup')
        self.wait_until(lambda: not (self.root / '.deployment-state/operation-lock').exists(),
                        'Interrupted graceful cleanup must still seal resources and unlock')
        self.assertEqual(qr_page.read_text(), 'expired')

    def test_unrelated_or_reused_lock_identity_is_never_stopped(self):
        self.start()
        self.read_until('地址已生成不等于公网验收')
        os.kill(self.process.pid, signal.SIGINT)
        self.read_until(timeout=10)
        self.close_master()
        stranger = subprocess.Popen(['sleep', '60'])
        try:
            identity = subprocess.check_output(['ps', '-p', str(stranger.pid), '-o', 'lstart=', '-o', 'args='], text=True)
            state = self.root / '.deployment-state/posix'
            lock = self.root / '.deployment-state/operation-lock'
            for saved_identity in (identity, 'previous-process-identity\n'):
                with self.subTest(saved_identity_matches=saved_identity == identity):
                    lock.mkdir(exist_ok=True)
                    (lock / 'pid').write_text(str(stranger.pid) + '\n')
                    (lock / 'identity').write_text(saved_identity)
                    (state / 'processes/wrapper.pid').write_text(str(stranger.pid) + '\n')
                    (state / 'processes/wrapper.identity').write_text(saved_identity)
                    self.output = ''
                    self.start()
                    self.read_until(timeout=10)
                    self.assertNotEqual(self.process.returncode, 0, self.output)
                    self.assertIsNone(stranger.poll(), 'An unrelated or reused PID must remain untouched')
                    self.assertEqual((lock / 'identity').read_text(), saved_identity)
                    self.assertEqual(len(self.child_pids()), 2, self.calls.read_text())
                    self.close_master()
        finally:
            stranger.terminate()
            stranger.wait(timeout=5)


if __name__ == '__main__':
    unittest.main(verbosity=2)
