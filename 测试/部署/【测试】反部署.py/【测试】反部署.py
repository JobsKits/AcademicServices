#!/usr/bin/env python3
"""隔离验证反部署：仅操作临时工程，不安装依赖、不连接真实数据库。"""

from __future__ import annotations

import os
import importlib.util
import hashlib
from pathlib import Path
import pty
import select
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import unittest


ROOT = next(parent for parent in Path(__file__).resolve().parents
            if (parent / "代码").is_dir() and (parent / "测试").is_dir())
DEPLOY = ROOT / "部署"
PLATFORMS = ("MacOS", "Ubuntu", "Debian", "RockyLinux", "AlibabaCloudLinux", "Alpine", "FreeBSD")
BEGIN_LIFECYCLE = "# BEGIN JOBS DEPLOYMENT LIFECYCLE"
END_LIFECYCLE = "# END JOBS DEPLOYMENT LIFECYCLE"


def platform_entry(deploy, platform, *, undeploy=False):
    """定位真实平台实施脚本，不经过快捷入口。"""
    action = "反部署" if undeploy else "部署"
    brand = "MacOS" if platform == "MacOS" else "FreeBSD" if platform == "FreeBSD" else "Linux"
    suffix = "command" if platform == "MacOS" else "sh"
    name = f"【{brand}】{action}.{suffix}"
    return deploy / platform / name / name


def embedded_lifecycle(entry):
    """只提取标记内函数定义，绝不执行真实入口的 main。"""
    lines = entry.read_text(encoding="utf-8").splitlines()
    if lines.count(BEGIN_LIFECYCLE) != 1 or lines.count(END_LIFECYCLE) != 1:
        raise ValueError(f"生命周期内嵌标记缺失或重复：{entry}")
    begin, end = lines.index(BEGIN_LIFECYCLE), lines.index(END_LIFECYCLE)
    if begin >= end:
        raise ValueError(f"生命周期内嵌标记顺序错误：{entry}")
    block = "\n".join(lines[begin + 1:end]) + "\n"
    for function in ("lc_context", "lc_begin", "lc_checkpoint", "lc_finalize", "lc_undeploy_main"):
        if f"\n{function}() {{" not in "\n" + block:
            raise ValueError(f"内嵌块缺少{function}：{entry}")
    if '\nmain "$@"' in block or "\nmain() {" in block:
        raise ValueError(f"内嵌块混入入口执行：{entry}")
    return block


class UndeploymentTests(unittest.TestCase):
    """运行真实生命周期函数，业务文件和选择器均来自独立临时目录。"""

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="反部署 中文 空格 ")
        self.addCleanup(self.temp.cleanup)
        self.work = Path(self.temp.name).resolve()
        self.project = self.work / "改名工程 ! $ ` ' (测试)"
        self.server = self.project / "代码/后端/后端代码"
        (self.server / "cmd/server").mkdir(parents=True)
        (self.server / "go.mod").write_text("module fixture\ngo 1.27\n", encoding="utf-8")
        self.deploy = self.project / "部署"
        shutil.copytree(DEPLOY, self.deploy)
        self.helper = self.work / "extracted-lifecycle.sh"
        self.helper.write_text(embedded_lifecycle(platform_entry(self.deploy, "MacOS", undeploy=True)), encoding="utf-8")
        self.tools = self.work / "假工具"
        self.tools.mkdir()
        self.backups = self.server.parent / "反部署备份"
        self.env = {**os.environ, "SERVER_ROOT": str(self.server),
                    "DEPLOY_ROOT": str(self.deploy), "PLATFORM_ID": "MacOS",
                    "LIFECYCLE_HELPER": str(self.helper),
                    "LOG_FILE": str(self.server / ".runtime/logs/deploy-fixture.log"),
                    "PATH": str(self.tools) + os.pathsep + os.environ["PATH"],
                    "TERM": "dumb", "NO_COLOR": "1", "LC_ALL": "C",
                    "FZF_DEFAULT_OPTS": "--filter=apply --bind=start:execute(touch forbidden)",
                    "FZF_DEFAULT_OPTS_FILE": "/not/a/user/file",
                    "FZF_DEFAULT_COMMAND": "touch forbidden"}
        for name in ("DATABASE_URL", "PGSERVICE", "PGPASSWORD"):
            self.env.pop(name, None)

    def run_shell(self, body, *, shell="sh", check=False, changes=None):
        script = self.work / ("fixture-" + shell + ".sh")
        script.write_text('set -eu\n. "$LIFECYCLE_HELPER"\n' + body + "\n", encoding="utf-8")
        result = subprocess.run([shell, str(script)], cwd="/", env={**self.env, **(changes or {})},
                                text=True, capture_output=True, timeout=30)
        if check:
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return result

    def baseline(self):
        for directory in (".runtime/bin", ".runtime/logs", ".tools/shared", "data"):
            (self.server / directory).mkdir(parents=True, exist_ok=True)
        for file, text in {".runtime/bin/server": "original-program\n",
                           ".runtime/config.env": "DATABASE_URL=\nADMIN_PASSWORD=fixture-original\n",
                           ".runtime/logs/prior.log": "previous-log\n",
                           ".tools/shared/other-project": "shared-sdk\n",
                           "data/state.json": '{"fixture":"business-with-attachment"}\n'}.items():
            (self.server / file).write_text(text, encoding="utf-8")

    def create_deployment(self):
        return self.run_shell('''lc_begin
mkdir -p "$SERVER_ROOT/.runtime/bin" "$SERVER_ROOT/.runtime/logs" "$SERVER_ROOT/.tools/new-tool"
printf 'deployed-program\\n' > "$SERVER_ROOT/.runtime/bin/server"
printf 'DATABASE_URL=\\nADMIN_PASSWORD=fixture-deployed\\n' > "$SERVER_ROOT/.runtime/config.env"
printf 'owned-tool\\n' > "$SERVER_ROOT/.tools/new-tool/owned"
printf 'current-log\\n' > "$LOG_FILE"
lc_checkpoint
lc_finalize''', check=True)

    def inventory(self):
        return {str(path.relative_to(self.project)): path.read_bytes()
                for path in self.project.rglob("*") if path.is_file() and not path.is_symlink()}

    def selector(self, choices, *, exit_code=0):
        selection = self.tools / 'fzf'
        selection.write_text('#!' + sys.executable + '\n' + '''import os, pathlib, sys
if any(os.environ.get(name) for name in ('FZF_DEFAULT_OPTS', 'FZF_DEFAULT_OPTS_FILE', 'FZF_DEFAULT_COMMAND')):
    sys.exit(91)
if '--help' in sys.argv:
    print('--accept-nth --height')
    sys.exit(0)
sys.stdin.read()
counter = pathlib.Path(os.environ['SELECTOR_COUNTER'])
index = int(counter.read_text()) if counter.exists() else 0
counter.write_text(str(index + 1))
choices = os.environ['SELECTOR_CHOICES'].split('|')
print(choices[min(index, len(choices) - 1)])
sys.exit(int(os.environ['SELECTOR_EXIT']))
''', encoding='utf-8')
        selection.chmod(0o755)
        return {'FZF_BIN': str(selection), 'SELECTOR_COUNTER': str(self.tools / 'counter'),
                'SELECTOR_CHOICES': '|'.join(choices), 'SELECTOR_EXIT': str(exit_code)}

    def run_terminal(self, body, *, answers='\n \n', changes=None):
        script = self.work / 'terminal-fixture.sh'
        script.write_text('set -eu\n. "$LIFECYCLE_HELPER"\n' + body + '\n', encoding='utf-8')
        master, slave = pty.openpty()
        process = subprocess.Popen(['sh', str(script)], cwd='/', env={**self.env, **(changes or {})},
                                   stdin=slave, stdout=slave, stderr=slave)
        os.close(slave)
        output = bytearray()
        try:
            os.write(master, answers.encode())
            deadline = time.monotonic() + 20
            while time.monotonic() < deadline:
                if select.select([master], [], [], .1)[0]:
                    try:
                        part = os.read(master, 65536)
                    except OSError:
                        break
                    if not part:
                        break
                    output.extend(part)
                elif process.poll() is not None:
                    break
            try:
                process.wait(timeout=1)
            except subprocess.TimeoutExpired:
                process.kill()
                self.fail('反部署隔离终端超时：' + output.decode(errors='replace'))
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()
            os.close(master)
        return process.returncode, output.decode(errors='replace')

    def test_01_all_platforms_embed_equivalent_portable_functions(self):
        self.assertTrue(self.helper.is_file())
        expected = self.helper.read_text()
        self.assertFalse((self.deploy / "公共组件/部署生命周期.sh").exists())
        for platform in PLATFORMS:
            for undeploy in (False, True):
                with self.subTest(platform=platform, undeploy=undeploy):
                    entry = platform_entry(self.deploy, platform, undeploy=undeploy)
                    self.assertEqual(embedded_lifecycle(entry), expected)
                    self.assertNotIn('公共组件/部署生命周期.sh', entry.read_text())
        for shell in ("sh", "bash", "zsh"):
            if not shutil.which(shell):
                continue
            result = self.run_shell('command -v lc_begin\ncommand -v lc_checkpoint\ncommand -v lc_undeploy_main', shell=shell)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_02_restore_original_program_config_and_keep_shared_tools(self):
        self.baseline()
        self.create_deployment()
        self.run_shell('lc_validate_owner\nlc_restore_resources', check=True)
        self.assertEqual((self.server / '.runtime/bin/server').read_text(), 'original-program\n')
        self.assertIn('fixture-original', (self.server / '.runtime/config.env').read_text())
        self.assertEqual((self.server / '.tools/shared/other-project').read_text(), 'shared-sdk\n')
        self.assertFalse((self.server / '.tools/new-tool').exists())
        self.assertTrue((self.server / 'data/state.json').is_file())
        self.run_shell('lc_validate_owner\nlc_restore_resources', check=True)

    def test_03_later_changes_remain_and_restoration_reports_incomplete(self):
        self.baseline()
        self.create_deployment()
        binary = self.server / '.runtime/bin/server'
        binary.write_text('later-user-program\n')
        result = self.run_shell('lc_validate_owner\nlc_restore_resources')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(binary.read_text(), 'later-user-program\n')
        self.assertIn('保留', result.stdout + result.stderr)

    def test_04_unknown_file_in_preexisting_directory_is_preserved_and_reported(self):
        self.baseline()
        self.create_deployment()
        unknown = self.server / '.tools/shared/new-other-project'
        unknown.write_text('unowned-file\n')
        result = self.run_shell('lc_validate_owner\nlc_restore_resources')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(unknown.read_text(), 'unowned-file\n')
        self.assertIn('保留', result.stdout + result.stderr)

    def test_05_corrupt_original_backup_stops_overwrite(self):
        self.baseline()
        self.create_deployment()
        original = self.server / '.deployment-state/posix/originals/.runtime/bin/server'
        original.write_text('corrupted-original\n')
        result = self.run_shell('lc_validate_owner\nlc_restore_resources')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((self.server / '.runtime/bin/server').read_text(), 'deployed-program\n')

    def test_06_symlink_resource_is_rejected_without_touching_target(self):
        self.baseline()
        self.create_deployment()
        outside = self.work / 'outside-program'
        outside.write_text('outside\n')
        binary = self.server / '.runtime/bin/server'
        binary.unlink()
        binary.symlink_to(outside)
        result = self.run_shell('lc_validate_owner\nlc_restore_resources')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(outside.read_text(), 'outside\n')
        self.assertTrue(binary.is_symlink())

    def test_07_backup_contains_business_and_matching_config_before_source_clear(self):
        self.baseline()
        self.create_deployment()
        source = (self.server / 'data/state.json').read_bytes()
        config = (self.server / '.runtime/config.env').read_bytes()
        self.run_shell('lc_validate_owner\nlc_backup_and_clear_data backup', check=True)
        self.assertFalse((self.server / 'data').exists())
        destinations = [path for path in self.backups.iterdir() if path.is_dir()]
        self.assertEqual(len(destinations), 1)
        self.assertEqual((destinations[0] / 'data/state.json').read_bytes(), source)
        self.assertEqual((destinations[0] / 'config.env').read_bytes(), config)
        self.assertEqual(destinations[0].stat().st_mode & 0o777, 0o700)

    def test_08_failed_backup_preserves_source_and_resources(self):
        self.baseline()
        self.create_deployment()
        source = (self.server / 'data/state.json').read_bytes()
        result = self.run_shell('lc_validate_owner\ncp() { return 81; }\nlc_backup_and_clear_data backup')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((self.server / 'data/state.json').read_bytes(), source)
        self.assertEqual((self.server / '.runtime/bin/server').read_text(), 'deployed-program\n')
        self.assertFalse((self.server / '.deployment-state/posix/data-completed').exists())

    def test_09_source_change_during_backup_preserves_source_and_original_backup(self):
        self.baseline()
        self.create_deployment()
        before = (self.server / 'data/state.json').read_bytes()
        result = self.run_shell('''lc_validate_owner
cp() {
  command cp "$@" || return
  if [ "$1" = -pR ]; then printf 'changed-during-backup\\n' >> "$SERVER_ROOT/data/state.json"; fi
}
lc_backup_and_clear_data backup''')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((self.server / 'data/state.json').read_bytes(), before + b'changed-during-backup\n')
        backups = list(self.backups.glob('*/data/state.json'))
        self.assertEqual(len(backups), 1)
        self.assertEqual(backups[0].read_bytes(), before)
        self.assertFalse((self.server / '.deployment-state/posix/data-completed').exists())

    def test_10_external_database_or_active_marker_prevents_any_source_clear(self):
        for reason in ('database', 'marker'):
            with self.subTest(reason=reason):
                self.baseline()
                if reason == 'database':
                    (self.server / '.runtime/config.env').write_text('DATABASE_URL=postgres://synthetic.invalid/fixture\n')
                else:
                    (self.server / 'data/.server-lock').write_text('pid=' + str(os.getpid()) + '\nstarted=2026-11-04T00:00:00Z\n')
                result = self.run_shell('lc_context\nmkdir -p "$LC_STATE"\nlc_backup_and_clear_data backup')
                self.assertNotEqual(result.returncode, 0)
                self.assertTrue((self.server / 'data/state.json').is_file())
                self.assertFalse(self.backups.exists())
                if reason == 'database':
                    (self.server / '.runtime/config.env').write_text('DATABASE_URL=\n')

    def test_11_read_only_and_eof_do_not_write_or_stop_processes(self):
        self.baseline()
        self.create_deployment()
        before = self.inventory()
        for argument in ('--check', '--plan'):
            result = self.run_shell('lc_undeploy_main ' + argument)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertEqual(self.inventory(), before)
        result = self.run_shell('lc_undeploy_main')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.inventory(), before)

    def test_12_failure_before_checkpoint_remains_recoverable_and_unlocks(self):
        result = self.run_shell('''lc_begin
mkdir -p "$SERVER_ROOT/.tools/partial"
printf 'download-interrupted\\n' > "$SERVER_ROOT/.tools/partial/archive"
lc_finalize''')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse((self.server / '.deployment-state/operation-lock').exists())
        self.run_shell('lc_validate_owner\nlc_restore_resources', check=True)
        self.assertFalse((self.server / '.tools/partial/archive').exists())

    def test_13_selector_cancel_empty_unknown_and_failure_do_not_write(self):
        self.baseline()
        self.create_deployment()
        before = self.inventory()
        for choices, exit_code in ((['cancel'], 0), ([''], 0), (['unknown'], 0),
                                   (['backup\nclear'], 0), (['backup'], 2),
                                   (['backup', 'cancel'], 0)):
            with self.subTest(choices=choices, exit_code=exit_code):
                (self.tools / 'counter').unlink(missing_ok=True)
                code, output = self.run_terminal('lc_undeploy_main',
                                                changes=self.selector(choices, exit_code=exit_code))
                self.assertNotEqual(code, 0, output)
                self.assertEqual(self.inventory(), before)
                self.assertFalse(self.backups.exists())

    def test_14_clear_requires_explicit_choice_and_space_before_any_source_write(self):
        self.baseline()
        self.create_deployment()
        before = self.inventory()
        code, output = self.run_terminal('lc_undeploy_main', answers='\n\n',
                                        changes=self.selector(['clear', 'apply']))
        self.assertNotEqual(code, 0, output)
        self.assertEqual(self.inventory(), before)
        (self.tools / 'counter').unlink(missing_ok=True)
        code, output = self.run_terminal('lc_undeploy_main',
                                        changes=self.selector(['clear', 'apply']))
        self.assertEqual(code, 0, output)
        self.assertFalse((self.server / 'data').exists())
        self.assertEqual((self.server / '.runtime/bin/server').read_text(), 'original-program\n')
        self.assertEqual(list(self.backups.glob('*/data/state.json')), [])
        self.assertTrue((self.server / '.deployment-state/posix/completed').is_file())
        before = self.inventory()
        code, output = self.run_terminal('lc_undeploy_main', answers='\n')
        self.assertEqual(code, 0, output)
        self.assertEqual(self.inventory(), before)

    def test_15_pid_identity_mismatch_never_signals_process(self):
        self.baseline()
        self.create_deployment()
        state = self.server / '.deployment-state/posix/processes'
        (state / 'server.pid').write_text(str(os.getpid()) + '\n')
        (state / 'server.identity').write_text('not-the-current-process-identity\n')
        result = self.run_shell('lc_validate_owner\nlc_stop_recorded')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('身份', result.stdout + result.stderr)
        self.assertTrue((self.server / 'data/state.json').is_file())

    def test_16_zsh_seals_runtime_and_tools_as_separate_trees(self):
        if not shutil.which('zsh'):
            self.skipTest('zsh is unavailable')
        self.run_shell('''lc_begin
mkdir -p "$SERVER_ROOT/.runtime/bin" "$SERVER_ROOT/.tools/tool"
printf 'binary\\n' > "$SERVER_ROOT/.runtime/bin/server"
printf 'tool\\n' > "$SERVER_ROOT/.tools/tool/binary"
lc_checkpoint
lc_finalize''', shell='zsh', check=True)
        manifest = (self.server / '.deployment-state/posix/after.tsv').read_text()
        self.assertIn('.runtime/bin/server', manifest)
        self.assertIn('.tools/tool/binary', manifest)

    def test_17_finalize_keeps_conflicting_previous_quick_config_outside_own_logs(self):
        self.baseline()
        quick = self.server / '.runtime/logs/quick-config.previous'
        quick.write_text('previous-config\n')
        self.run_shell('''lc_begin
printf 'current-log\\n' > "$LOG_FILE"
lc_checkpoint
printf 'outside-modification\\n' > "$SERVER_ROOT/.runtime/logs/quick-config.previous"
lc_finalize''', check=True)
        result = self.run_shell('lc_validate_owner\nlc_restore_resources')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(quick.read_text(), 'outside-modification\n')

    def test_18_retry_keeps_original_confirmation_instead_of_rebackup_changed_source(self):
        self.baseline()
        self.create_deployment()
        before = (self.server / 'data/state.json').read_bytes()
        result = self.run_shell('''lc_validate_owner
cp() {
  command cp "$@" || return
  if [ "$1" = -pR ]; then printf 'later-change\\n' >> "$SERVER_ROOT/data/state.json"; fi
}
lc_backup_and_clear_data backup''')
        self.assertNotEqual(result.returncode, 0)
        stage = next(path for path in self.backups.iterdir() if path.is_dir())
        result = self.run_shell('lc_validate_owner\nlc_backup_and_clear_data backup')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(len(list(self.backups.iterdir())), 1)
        self.assertEqual((stage / 'data/state.json').read_bytes(), before)
        self.assertEqual((self.server / 'data/state.json').read_bytes(), before + b'later-change\n')

    def test_19_interrupted_move_resumes_the_same_verified_backup(self):
        self.baseline()
        self.create_deployment()
        before = (self.server / 'data/state.json').read_bytes()
        result = self.run_shell('''lc_validate_owner
mv() {
  command mv "$@" || return
  if [ "$1" = "$SERVER_ROOT/data" ]; then return 88; fi
}
lc_backup_and_clear_data backup''')
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.server / 'data').exists())
        stage = next(path for path in self.backups.iterdir() if path.is_dir())
        self.assertEqual((stage / 'check-tree/data/state.json').read_bytes(), before)
        self.run_shell('lc_validate_owner\nlc_backup_and_clear_data backup', check=True)
        self.assertEqual(len(list(self.backups.iterdir())), 1)
        self.assertEqual((stage / 'data/state.json').read_bytes(), before)
        self.assertFalse((stage / 'check-tree/data').exists())

    def test_20_mac_full_deployment_exit_then_backup_undeployment(self):
        if sys.platform != 'darwin':
            self.skipTest('MacOS lifecycle integration requires MacOS')
        location = ROOT / '测试/部署/【测试】部署双模式.py/【测试】部署双模式.py'
        spec = importlib.util.spec_from_file_location('academic_mode_fixture', location)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        mode = module.ModeTests('test_03_local_health_then_url_and_interrupt_cleanup')
        mode.setUp()
        self.addCleanup(mode.tearDown)
        config_before = (mode.root / '.runtime/config.env').read_bytes()
        mode.start(NO_COLOR='1')
        mode.read_until('地址已生成不等于公网验收')
        (mode.root / 'data/state.json').write_text('{"fixture":"session-business"}\n')
        mode.process.send_signal(signal.SIGTERM)
        mode.read_until()
        mode.assert_children_stopped()
        self.assertFalse((mode.root / '.deployment-state/operation-lock').exists())
        self.assertTrue((mode.root / '.deployment-state/posix/after.tsv').is_file())
        mode_helper = self.work / 'mode-extracted-lifecycle.sh'
        mode_helper.write_text(embedded_lifecycle(platform_entry(mode.deploy_root, 'MacOS', undeploy=True)), encoding='utf-8')
        code, output = self.run_terminal('lc_undeploy_main', changes={
            **self.selector(['backup', 'apply']),
            'SERVER_ROOT': str(mode.root.resolve()), 'DEPLOY_ROOT': str(mode.deploy_root.resolve()),
            'LIFECYCLE_HELPER': str(mode_helper)})
        self.assertEqual(code, 0, output)
        self.assertEqual((mode.root / '.runtime/config.env').read_bytes(), config_before)
        self.assertFalse((mode.root / '.runtime/bin/server').exists())
        self.assertFalse((mode.root / 'data').exists())
        backups = list((mode.root.parent / '反部署备份').glob('*/data/state.json'))
        self.assertEqual(len(backups), 1)
        self.assertEqual(backups[0].read_text(), '{"fixture":"session-business"}\n')
        self.assertFalse((mode.root / '.deployment-state/operation-lock').exists())

    def test_21_finalize_seals_current_log_and_both_child_logs(self):
        self.baseline()
        self.run_shell('''lc_begin
printf 'before-run\\n' > "$LOG_FILE"
lc_checkpoint
printf 'after-run\\n' >> "$LOG_FILE"
printf 'server-output\\n' > "$LOG_FILE.server.log"
printf 'tunnel-output\\n' > "$LOG_FILE.tunnel.log"
lc_finalize''', check=True)
        self.run_shell('lc_validate_owner\nlc_restore_resources', check=True)

    def test_23_real_platform_undeployment_entries_read_existing_state_without_helper(self):
        for platform in PLATFORMS:
            with self.subTest(platform=platform):
                project = self.work / platform / '迁移 中文 空格 工程'
                server = project / '代码/后端/后端代码'
                state = server / '.deployment-state/posix'
                state.mkdir(parents=True)
                (server / 'go.mod').write_text('module fixture\ngo 1.27\n')
                (server / 'data').mkdir()
                (server / 'data/state.json').write_text('{"keep":"legacy-business"}\n')
                (state.parent / 'owner').write_text('posix\n')
                (state / 'platform').write_text(platform + '\n')
                (state / 'before.tsv').write_text('')
                (state / 'after.tsv').write_text('')
                deploy = project / '部署'
                shutil.copytree(DEPLOY / platform, deploy / platform)
                self.assertFalse((deploy / '公共组件/部署生命周期.sh').exists())
                tools = project / '假平台命令'
                tools.mkdir()
                system = 'Darwin' if platform == 'MacOS' else 'FreeBSD' if platform == 'FreeBSD' else 'Linux'
                distro = {'Ubuntu': 'ubuntu', 'Debian': 'debian', 'RockyLinux': 'rocky',
                          'AlibabaCloudLinux': 'alinux', 'Alpine': 'alpine'}.get(platform, '')
                (tools / 'uname').write_text('#!/bin/sh\nif [ "$1" = -s ]; then printf "%s\\n" "$FIXTURE_SYSTEM"; else exec /usr/bin/uname "$@"; fi\n')
                (tools / 'sed').write_text('#!/bin/sh\nif [ "$#" = 3 ] && [ "$1" = -n ] && [ "$3" = /etc/os-release ]; then printf "%s\\n" "$FIXTURE_DISTRO"; else exec /usr/bin/sed "$@"; fi\n')
                for command in tools.iterdir():
                    command.chmod(0o755)
                env = {**self.env, 'PATH': str(tools) + os.pathsep + self.env['PATH'],
                       'FIXTURE_SYSTEM': system, 'FIXTURE_DISTRO': distro}
                shell = 'zsh' if platform == 'MacOS' else 'sh' if platform in ('Alpine', 'FreeBSD') else 'bash'
                entry = platform_entry(deploy, platform, undeploy=True)
                before = {str(p.relative_to(project)): p.read_bytes() for p in project.rglob('*') if p.is_file()}
                for argument in ('--check', '--plan'):
                    result = subprocess.run([shell, str(entry), argument], cwd='/', env=env,
                                            input='', text=True, capture_output=True, timeout=15)
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                    self.assertIn('检查通过', result.stdout + result.stderr)
                result = subprocess.run([shell, str(entry)], cwd='/', env=env,
                                        input='', text=True, capture_output=True, timeout=15)
                self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn('请在交互终端运行', result.stdout + result.stderr)
                self.assertEqual(before, {str(p.relative_to(project)): p.read_bytes()
                                          for p in project.rglob('*') if p.is_file()})

    def test_24_existing_posix_manifests_resume_and_restore_without_schema_changes(self):
        self.baseline()
        state = self.server / '.deployment-state/posix'
        originals = state / 'originals'
        originals.mkdir(parents=True)

        def manifest():
            rows = []
            for name in ('.runtime', '.tools'):
                root = self.server / name
                for path in (root, *root.rglob('*')):
                    mode = format(path.stat().st_mode & 0o7777, 'o')
                    kind = 'D' if path.is_dir() else 'F'
                    digest = '-' if kind == 'D' else hashlib.sha256(path.read_bytes()).hexdigest()
                    rows.append(f'{kind}\t{digest}\t{mode}\t{path.relative_to(self.server)}\n')
            return ''.join(sorted(rows))

        before = manifest()
        for name in ('.runtime', '.tools'):
            shutil.copytree(self.server / name, originals / name, copy_function=shutil.copy2)
        (state.parent / 'owner').write_text('posix\n')
        (state / 'platform').write_text('MacOS\n')
        (state / 'before.tsv').write_text(before)
        (self.server / '.runtime/bin/server').write_text('prior-deployed-program\n')
        after = manifest()
        (state / 'after.tsv').write_text(after)
        (state / 'status').write_text('ready\n')
        deploy_helper = self.work / 'deployment-extracted-lifecycle.sh'
        deploy_helper.write_text(embedded_lifecycle(platform_entry(self.deploy, 'MacOS')), encoding='utf-8')
        self.run_shell('lc_begin\nlc_checkpoint\nlc_finalize',
                       changes={'LIFECYCLE_HELPER': str(deploy_helper)}, check=True)
        self.assertEqual((state / 'before.tsv').read_text(), before)
        self.assertEqual((state / 'after.tsv').read_text(), after)
        self.run_shell('lc_validate_owner\nlc_restore_resources', check=True)
        self.assertEqual((self.server / '.runtime/bin/server').read_text(), 'original-program\n')
        self.assertEqual((self.server / '.tools/shared/other-project').read_text(), 'shared-sdk\n')
        self.assertTrue((self.server / 'data/state.json').is_file())
        self.assertFalse((self.server / '.runtime/logs/deploy-fixture.log').exists())
        self.assertFalse((self.server / '.runtime/logs/deploy-fixture.log.server.log').exists())
        self.assertFalse((self.server / '.runtime/logs/deploy-fixture.log.tunnel.log').exists())

    def test_22_mac_unwrapped_failure_finalizes_and_releases_lock(self):
        if sys.platform != 'darwin':
            self.skipTest('MacOS failure integration requires MacOS')
        entry = DEPLOY / 'MacOS/【MacOS】部署.command/【MacOS】部署.command'
        prefix = entry.read_text().rsplit('main "$@"', 1)[0]
        script = self.work / 'unwrapped-failure.zsh'
        script.write_text(prefix + '''
SERVER_ROOT="$FIXTURE_SERVER"
DEPLOY_ROOT="$FIXTURE_DEPLOY"
LOG_FILE="$SERVER_ROOT/.runtime/logs/deploy-unwrapped.log"
simulate_main() {
  initialize_deployment_lifecycle
  initialize_runtime
  false
  printf 'unexpected-success\\n'
}
simulate_main
''')
        result = subprocess.run(['zsh', str(script)], cwd='/', env={**self.env,
            'FIXTURE_SERVER': str(self.server), 'FIXTURE_DEPLOY': str(self.deploy)},
            text=True, capture_output=True, timeout=20)
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn('unexpected-success', result.stdout)
        self.assertFalse((self.server / '.deployment-state/operation-lock').exists(), result.stdout + result.stderr)
        self.assertTrue((self.server / '.deployment-state/posix/after.tsv').is_file())
        self.run_shell('lc_validate_owner\nlc_restore_resources', check=True)


if __name__ == "__main__":
    print("反部署隔离测试：只使用临时工程／假选择器；不安装依赖、不连接真实数据库。", flush=True)
    unittest.main(verbosity=2)
