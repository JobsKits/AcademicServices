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
    block_lines = lines[begin + 1:end]
    # 部分平台把展示保护插入生命周期标记内；隔离测试仅加载原生生命周期函数。
    for first, last in (("# >>> Jobs terminal style protection v1 >>>",
                         "# <<< Jobs terminal style protection v1 <<<"),
                        ("# JOBS_INPUT_CHOICE_STYLE_BEGIN", "# JOBS_INPUT_CHOICE_STYLE_END")):
        if first not in block_lines and last not in block_lines:
            continue
        if block_lines.count(first) != 1 or block_lines.count(last) != 1:
            raise ValueError(f"展示保护标记缺失或重复：{entry}")
        first_index, last_index = block_lines.index(first), block_lines.index(last)
        if first_index >= last_index:
            raise ValueError(f"展示保护标记顺序错误：{entry}")
        block_lines = block_lines[:first_index] + block_lines[last_index + 1:]
    function_start = block_lines.index("lc_message() {")
    comments = [line for line in block_lines[:function_start] if line.strip()]
    if any(not line.startswith('#') for line in comments):
        raise ValueError(f"生命周期函数前混入未识别的执行逻辑：{entry}")
    block = "\n".join(comments + block_lines[function_start:]) + "\n"
    if sum(line.startswith('lc_') and '() {' in line for line in block.splitlines()) < 28:
        raise ValueError(f"生命周期函数数量不足：{entry}")
    for function in ("lc_context", "lc_begin", "lc_checkpoint", "lc_finalize", "lc_redeploy_matches", "lc_undeploy_main"):
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
        script.write_text('set -eu\njobs_prompt_output() { "$@"; }\n. "$LIFECYCLE_HELPER"\n' + body + "\n", encoding="utf-8")
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

    def run_terminal(self, body, *, answers='\n\n', changes=None, shell='sh'):
        script = self.work / 'terminal-fixture.sh'
        script.write_text('set -eu\njobs_prompt_output() { "$@"; }\n. "$LIFECYCLE_HELPER"\n' + body + '\n', encoding='utf-8')
        master, slave = pty.openpty()
        process = subprocess.Popen([shell, str(script)], cwd='/', env={**self.env, **(changes or {})},
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
        mac_confirmation = """  jobs_prompt_output printf '直接回车复核授权并执行；其它输入取消：' >&2
  IFS= read -r lc_authorization || return 130
  [ -z "$lc_authorization" ] || return 130"""
        other_confirmation = """  jobs_prompt_output printf '按一次空格后回车复核授权；其它输入取消：' >&2
  IFS= read -r lc_space || return 130
  [ "$lc_space" = ' ' ] || return 130"""
        self.assertEqual(expected.count(mac_confirmation), 1)
        self.assertFalse((self.deploy / "公共组件/部署生命周期.sh").exists())
        for platform in PLATFORMS:
            for undeploy in (False, True):
                with self.subTest(platform=platform, undeploy=undeploy):
                    entry = platform_entry(self.deploy, platform, undeploy=undeploy)
                    block = embedded_lifecycle(entry)
                    if platform != 'MacOS':
                        self.assertEqual(block.count(other_confirmation), 1)
                        block = block.replace(other_confirmation, mac_confirmation)
                    self.assertEqual(block, expected)
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

    def test_14_mac_clear_requires_explicit_choice_and_enter_before_any_source_write(self):
        self.baseline()
        self.create_deployment()
        before = self.inventory()
        shells = ['sh'] + (['zsh'] if shutil.which('zsh') else [])
        for shell in shells:
            for answers in ('\n \n', '\nCLEAR\n', '\n\x04'):
                with self.subTest(shell=shell, answers=repr(answers)):
                    (self.tools / 'counter').unlink(missing_ok=True)
                    code, output = self.run_terminal('lc_undeploy_main', answers=answers,
                                                    changes=self.selector(['clear', 'apply']), shell=shell)
                    self.assertEqual(code, 130, output)
                    self.assertIn('直接回车复核授权并执行；其它输入取消', output)
                    self.assertEqual(self.inventory(), before)
                    self.assertFalse(self.backups.exists())
        (self.tools / 'counter').unlink(missing_ok=True)
        code, output = self.run_terminal('lc_undeploy_main',
                                        changes=self.selector(['clear', 'apply']), shell=shells[-1])
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
            'LIFECYCLE_HELPER': str(mode_helper), 'HOME': mode.env['HOME'], 'XDG_CACHE_HOME': mode.env['XDG_CACHE_HOME']})
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

    def test_25_finalize_scans_only_owned_runtime_paths_and_keeps_external_changes(self):
        for shell in ('sh', 'bash', 'zsh'):
            if not shutil.which(shell):
                continue
            with self.subTest(shell=shell):
                server = self.work / ('selective-' + shell)
                server.mkdir()
                initial = self.work / ('initial-' + shell + '.tsv')
                changes = {'SERVER_ROOT': str(server),
                           'LOG_FILE': str(server / '.runtime/logs/current.log'),
                           'FIXTURE_INITIAL': str(initial)}
                self.run_shell('''mkdir -p "$SERVER_ROOT/.runtime/logs" "$SERVER_ROOT/.tools/shared"
printf 'original-sdk\\n' > "$SERVER_ROOT/.tools/shared/sdk"
printf 'original-config\\n' > "$SERVER_ROOT/.runtime/config.env"
lc_begin
printf 'before-run\\n' > "$LOG_FILE"
lc_checkpoint
cp "$LC_STATE/after.tsv" "$FIXTURE_INITIAL"
printf 'external-sdk\\n' > "$SERVER_ROOT/.tools/shared/sdk"
printf 'external-config\\n' > "$SERVER_ROOT/.runtime/config.env"
printf 'unowned-new-file\\n' > "$SERVER_ROOT/.runtime/unowned"
printf 'after-run\\n' >> "$LOG_FILE"
printf 'server-output\\n' > "$LOG_FILE.server.log"
printf 'tunnel-output\\n' > "$LOG_FILE.tunnel.log"
quick_config="$SERVER_ROOT/.runtime/logs/quick-config.fixture"
printf '{}\\n' > "$quick_config"
QR_OUTPUT="$SERVER_ROOT/.runtime/access-qr.fixture"
mkdir -p "$QR_OUTPUT/nested"
printf 'qr-output\\n' > "$QR_OUTPUT/nested/code.svg"
find() {
  case "$1" in
    "$LOG_FILE"|"$LOG_FILE.server.log"|"$LOG_FILE.tunnel.log"|"$quick_config"|"$QR_OUTPUT") command find "$@";;
    *) printf 'unexpected-unowned-scan:%s\\n' "$1" >&2; return 71;;
  esac
}
lc_hash() {
  case "$1" in
    "$LOG_FILE"|"$LOG_FILE.server.log"|"$LOG_FILE.tunnel.log"|"$quick_config"|"$QR_OUTPUT"/*)
      if command -v sha256sum >/dev/null 2>&1; then command sha256sum "$1" | awk '{print $1}'
      else command shasum -a 256 "$1" | awk '{print $1}'; fi;;
    *) printf 'unexpected-unowned-hash:%s\\n' "$1" >&2; return 72;;
  esac
}
lc_finalize''', shell=shell, changes=changes, check=True)
                state = server / '.deployment-state/posix'
                before = {row.split('\t', 3)[3]: row for row in initial.read_text().splitlines()}
                after = {row.split('\t', 3)[3]: row for row in (state / 'after.tsv').read_text().splitlines()}
                selected = {row.split('\t', 3)[3] for row in (state / 'finalize.tsv').read_text().splitlines()}
                self.assertEqual(selected, {
                    '.runtime/logs/current.log', '.runtime/logs/current.log.server.log',
                    '.runtime/logs/current.log.tunnel.log', '.runtime/logs/quick-config.fixture',
                    '.runtime/access-qr.fixture', '.runtime/access-qr.fixture/nested',
                    '.runtime/access-qr.fixture/nested/code.svg'})
                for path, row in before.items():
                    if path not in selected:
                        self.assertEqual(after[path], row, path)
                self.assertNotIn('.runtime/unowned', after)
                self.assertNotEqual(after['.runtime/logs/current.log'], before['.runtime/logs/current.log'])
                self.assertFalse((server / '.deployment-state/operation-lock').exists())
                result = self.run_shell('lc_validate_owner\nlc_restore_resources',
                                        shell=shell, changes=changes)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual((server / '.tools/shared/sdk').read_text(), 'external-sdk\n')
                self.assertEqual((server / '.runtime/config.env').read_text(), 'external-config\n')
                self.assertEqual((server / '.runtime/unowned').read_text(), 'unowned-new-file\n')

    def test_26_finalize_rejects_unsafe_paths_and_symlink_ancestors_without_resealing(self):
        self.baseline()
        self.create_deployment()
        after = self.server / '.deployment-state/posix/after.tsv'
        before = after.read_bytes()
        outside = self.work / 'outside-runtime'
        outside.mkdir()
        marker = outside / 'owned.log'
        marker.write_text('outside-unchanged\n')
        (self.server / '.runtime/linked').symlink_to(outside, target_is_directory=True)
        cases = (
            {'LOG_FILE': str(marker)},
            {'quick_config': str(self.server / '.tools/shared/other-project')},
            {'QR_OUTPUT': str(self.server / '.runtime/../data')},
            {'LOG_FILE': str(self.server / '.runtime/linked/owned.log')},
            {'quick_config': str(self.server / '.runtime/linked/owned.log')},
            {'QR_OUTPUT': str(self.server / '.runtime/linked/missing-directory')},
        )
        for changes in cases:
            with self.subTest(changes=changes):
                result = self.run_shell('lc_context\nlc_finalize_resources', changes=changes)
                self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertEqual(after.read_bytes(), before)
                self.assertEqual(marker.read_text(), 'outside-unchanged\n')

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

    def test_27_redeploy_ignores_finder_metadata_without_resealing_old_manifests(self):
        """Finder新增、改写及移除元数据不应阻止重新部署或覆盖恢复依据。"""
        self.baseline()
        changed = self.server / '.tools/.DS_Store'
        removed = self.server / '.runtime/.DS_Store'
        changed.write_bytes(b'previous-finder-layout')
        removed.write_bytes(b'previous-runtime-layout')
        self.create_deployment()
        state = self.server / '.deployment-state/posix'
        manifests = {name: (state / name).read_bytes() for name in ('before.tsv', 'after.tsv')}
        changed.write_bytes(b'new-finder-layout')
        removed.unlink()
        for name in ('.tools/shared/.DS_Store', '.runtime/logs/.DS_Store'):
            (self.server / name).write_bytes(b'finder-created-after-deployment')
        contents = {str(path.relative_to(self.server)): path.read_bytes()
                    for name in ('.runtime', '.tools', 'data')
                    for path in (self.server / name).rglob('*') if path.is_file()}
        for shell in ('sh', 'bash', 'zsh'):
            if not shutil.which(shell):
                continue
            with self.subTest(shell=shell):
                self.run_shell('trap \'lc_release_lock\' EXIT\nlc_begin\nlc_release_lock',
                               shell=shell, check=True)
                self.assertEqual({name: (state / name).read_bytes() for name in manifests}, manifests)
                self.assertEqual({str(path.relative_to(self.server)): path.read_bytes()
                                  for name in ('.runtime', '.tools', 'data')
                                  for path in (self.server / name).rglob('*') if path.is_file()}, contents)
                self.assertFalse((state.parent / 'operation-lock').exists())

    def test_28_redeploy_still_rejects_real_changes_and_unsafe_metadata_names(self):
        """配置、SDK、未知程序和伪元数据仍拒绝，不把外部资源重新认领。"""
        self.baseline()
        self.create_deployment()
        state = self.server / '.deployment-state/posix'
        manifests = {name: (state / name).read_bytes() for name in ('before.tsv', 'after.tsv')}
        outside = self.work / 'outside-finder-target'
        outside.write_bytes(b'outside-original')
        cases = (
            ('sdk', '.tools/shared/other-project', 'file'),
            ('config', '.runtime/config.env', 'file'),
            ('program', '.runtime/bin/unknown-program', 'file'),
            ('unknown', '.runtime/unowned', 'file'),
            ('similar-name', '.tools/shared/.DS_Store.backup', 'file'),
            ('directory', '.tools/shared/.DS_Store', 'directory'),
            ('symlink', '.tools/shared/.DS_Store', 'symlink'),
        )
        for shell in ('sh', 'bash', 'zsh'):
            if not shutil.which(shell):
                continue
            for case, name, kind in cases:
                with self.subTest(shell=shell, case=case):
                    target = self.server / name
                    original = target.read_bytes() if target.is_file() else None
                    if kind == 'directory':
                        target.mkdir()
                    elif kind == 'symlink':
                        target.symlink_to(outside)
                    else:
                        target.write_bytes(b'new-or-externally-modified-content')
                    try:
                        result = self.run_shell('''if lc_begin; then
  lc_release_lock
else
  fixture_code=$?
  lc_release_lock
  exit "$fixture_code"
fi''', shell=shell)
                        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                        if kind != 'symlink':
                            self.assertIn('部署前检查未通过', result.stdout + result.stderr)
                            self.assertNotIn('反部署未完成', result.stdout + result.stderr)
                        self.assertEqual({name: (state / name).read_bytes() for name in manifests}, manifests)
                        if kind == 'directory':
                            self.assertTrue(target.is_dir())
                        elif kind == 'symlink':
                            self.assertTrue(target.is_symlink())
                            self.assertEqual(target.readlink(), outside)
                        else:
                            self.assertEqual(target.read_bytes(), b'new-or-externally-modified-content')
                        self.assertEqual(outside.read_bytes(), b'outside-original')
                        self.assertFalse((state.parent / 'operation-lock').exists())
                    finally:
                        if original is not None:
                            target.write_bytes(original)
                        elif kind == 'directory':
                            target.rmdir()
                        else:
                            target.unlink()

    def test_29_redeploy_comparison_handles_empty_and_metadata_only_manifests(self):
        """空清单不吞掉下一份清单，非普通文件及非四列记录不能按元数据跳过。"""
        expected = self.work / 'expected.tsv'
        actual = self.work / 'actual.tsv'
        metadata = 'F\t' + 'a' * 64 + '\t644\t.tools/.DS_Store\n'
        program = 'F\t' + 'b' * 64 + '\t600\t.runtime/bin/server\n'
        directory = 'D\t-\t755\t.tools/.DS_Store\n'
        cases = (
            ('', '', True),
            ('', metadata, True),
            (metadata, '', True),
            (metadata, metadata.replace('a' * 64, 'c' * 64), True),
            ('', program, False),
            (program, '', False),
            (metadata, program, False),
            (program, metadata, False),
            ('', directory, False),
            ('', metadata.rstrip('\n') + '\textra\n', False),
        )
        for shell in ('sh', 'bash', 'zsh'):
            if not shutil.which(shell):
                continue
            for index, (before, after, matches) in enumerate(cases):
                with self.subTest(shell=shell, case=index):
                    expected.write_text(before, encoding='utf-8')
                    actual.write_text(after, encoding='utf-8')
                    result = self.run_shell('lc_redeploy_matches "$FIXTURE_EXPECTED" "$FIXTURE_ACTUAL"',
                                            shell=shell, changes={'FIXTURE_EXPECTED': str(expected),
                                                                  'FIXTURE_ACTUAL': str(actual)})
                    self.assertEqual(result.returncode == 0, matches, result.stdout + result.stderr)
                    self.assertEqual(expected.read_text(encoding='utf-8'), before)
                    self.assertEqual(actual.read_text(encoding='utf-8'), after)

    def test_30_redeploy_preserves_regenerated_programs_and_go_cache_before_accepting(self):
        """已知生成物变动先留校验副本，原点与上一轮封口都不能被改写。"""
        self.baseline()
        cache = self.server / '.tools/gobuildcache'
        (cache / 'ab').mkdir(parents=True)
        changed = cache / 'ab' / ('ab' + '1' * 62 + '-a')
        removed = cache / 'ab' / ('ab' + '2' * 62 + '-d')
        changed.write_bytes(b'old-cache-index')
        removed.write_bytes(b'old-cache-data')
        (cache / 'README').write_bytes(b'old-cache-description')
        (cache / 'trim.txt').write_bytes(b'old-trim-time')
        (self.server / '.runtime/bin/deployqr').write_bytes(b'previous-registered-qr')
        self.create_deployment()
        state = self.server / '.deployment-state/posix'
        manifests = {name: ((state / name).read_bytes(), (state / name).stat().st_mtime_ns)
                     for name in ('before.tsv', 'after.tsv')}
        originals = {str(path.relative_to(state / 'originals')): path.read_bytes()
                     for path in (state / 'originals').rglob('*') if path.is_file()}
        changed.write_bytes(b'new-cache-index')
        changed.chmod(0o600)
        removed.unlink()
        (cache / 'README').write_bytes(b'current-cache-description')
        (cache / 'trim.txt').write_bytes(b'current-trim-time')
        (cache / 'cd').mkdir()
        (cache / 'cd' / ('cd' + '3' * 62 + '-d')).write_bytes(b'new-cache-data')
        (self.server / '.runtime/bin/server').write_bytes(b'rebuilt-server')
        (self.server / '.runtime/bin/deployqr').write_bytes(b'rebuilt-qr')
        (cache / '.DS_Store').write_bytes(b'finder-layout')
        contents = {str(path.relative_to(self.server)): path.read_bytes()
                    for name in ('.runtime', '.tools', 'data')
                    for path in (self.server / name).rglob('*') if path.is_file()}
        for shell in ('sh', 'bash', 'zsh'):
            if not shutil.which(shell):
                continue
            with self.subTest(shell=shell):
                previous = set((state / 'redeploy-backups').glob('redeploy.*'))
                self.run_shell("trap 'lc_release_lock' EXIT\nlc_begin\nlc_release_lock",
                               shell=shell, check=True)
                created = set((state / 'redeploy-backups').glob('redeploy.*')) - previous
                self.assertEqual(len(created), 1)
                backup = created.pop()
                self.assertEqual(backup.stat().st_mode & 0o777, 0o700)
                self.assertTrue((backup / 'verified').is_file())
                self.assertEqual((backup / 'previous-after.tsv').read_bytes(), manifests['after.tsv'][0])
                current = {row.split('\t', 3)[3]: row.split('\t', 3)
                           for row in (backup / 'current.tsv').read_text().splitlines()}
                changes = {row.split('\t', 3)[3]: row.split('\t', 3)
                           for row in (backup / 'changes.tsv').read_text().splitlines()}
                missing = {row.split('\t', 3)[3]
                           for row in (backup / 'missing.tsv').read_text().splitlines()}
                self.assertIn(str(removed.relative_to(self.server)), missing)
                self.assertIn('.runtime/bin/server', changes)
                self.assertIn('.runtime/bin/deployqr', changes)
                self.assertIn('.tools/gobuildcache/cd', changes)
                for name, row in changes.items():
                    self.assertEqual(row, current[name])
                    if row[0] == 'F':
                        snapshot = backup / 'files' / name
                        self.assertTrue(snapshot.is_file(), name)
                        self.assertEqual(snapshot.read_bytes(), contents[name], name)
                        self.assertEqual(hashlib.sha256(snapshot.read_bytes()).hexdigest(), row[1], name)
                        self.assertEqual(format(snapshot.stat().st_mode & 0o7777, 'o'), row[2], name)
                self.assertEqual({name: ((state / name).read_bytes(), (state / name).stat().st_mtime_ns)
                                  for name in manifests}, manifests)
                self.assertEqual({str(path.relative_to(state / 'originals')): path.read_bytes()
                                  for path in (state / 'originals').rglob('*') if path.is_file()}, originals)
                self.assertEqual({str(path.relative_to(self.server)): path.read_bytes()
                                  for name in ('.runtime', '.tools', 'data')
                                  for path in (self.server / name).rglob('*') if path.is_file()}, contents)
                self.assertFalse((state.parent / 'operation-lock').exists())

    def test_31_redeploy_rejects_fake_cache_paths_and_generated_file_types(self):
        """缓存名单只接受指定结构和类型，不能凭目录前缀绕过资源保护。"""
        self.baseline()
        cache = self.server / '.tools/gobuildcache'
        (cache / 'ab').mkdir(parents=True)
        self.create_deployment()
        state = self.server / '.deployment-state/posix'
        manifests = {name: (state / name).read_bytes() for name in ('before.tsv', 'after.tsv')}
        (self.server / '.runtime/bin/server').write_bytes(b'valid-regenerated-output')
        outside = self.work / 'outside-generated-target'
        outside.write_bytes(b'outside-original')
        cases = (
            ('.runtime/bin/deployqr', 'file'),
            ('.tools/gobuildcache/unknown', 'file'),
            ('.tools/gobuildcache/ab/not-a-go-key-a', 'file'),
            ('.tools/gobuildcache/ab/' + 'cd' + '0' * 62 + '-a', 'file'),
            ('.tools/gobuildcache/ab/' + 'ab' + '0' * 62 + '-x', 'file'),
            ('.tools/gobuildcache/zz', 'directory'),
            ('.tools/gobuildcache/ab/nested', 'directory'),
            ('.tools/gobuildcache/ab/' + 'ab' + '4' * 62 + '-d', 'directory'),
            ('.tools/gobuildcache/ab/' + 'ab' + '5' * 62 + '-a', 'symlink'),
            ('.runtime/bin/server', 'directory'),
            ('.runtime/bin/server', 'symlink'),
        )
        for shell in ('sh', 'bash', 'zsh'):
            if not shutil.which(shell):
                continue
            for name, kind in cases:
                with self.subTest(shell=shell, name=name, kind=kind):
                    target = self.server / name
                    original = target.read_bytes() if target.is_file() else None
                    original_mode = target.stat().st_mode & 0o7777 if original is not None else None
                    if original is not None:
                        target.unlink()
                    if kind == 'directory':
                        target.mkdir()
                    elif kind == 'symlink':
                        target.symlink_to(outside)
                    else:
                        target.write_bytes(b'not-trusted-generated-content')
                    try:
                        result = self.run_shell('''if lc_begin; then
  lc_release_lock
else
  fixture_code=$?
  lc_release_lock
  exit "$fixture_code"
fi''', shell=shell)
                        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                        self.assertFalse(list((state / 'redeploy-backups').glob('redeploy.*')))
                        self.assertEqual({name: (state / name).read_bytes() for name in manifests}, manifests)
                        self.assertEqual(outside.read_bytes(), b'outside-original')
                        if kind == 'directory':
                            self.assertTrue(target.is_dir())
                        elif kind == 'symlink':
                            self.assertTrue(target.is_symlink())
                        else:
                            self.assertEqual(target.read_bytes(), b'not-trusted-generated-content')
                        self.assertFalse((state.parent / 'operation-lock').exists())
                    finally:
                        if kind == 'directory':
                            target.rmdir()
                        else:
                            target.unlink()
                        if original is not None:
                            target.write_bytes(original)
                            target.chmod(original_mode)

    def test_32_redeploy_backup_failure_keeps_source_and_old_manifests(self):
        """副本写入失败或副本摘要不符时，生成物也不能未经保留就继续部署。"""
        self.baseline()
        self.create_deployment()
        state = self.server / '.deployment-state/posix'
        manifests = {name: (state / name).read_bytes() for name in ('before.tsv', 'after.tsv')}
        server = self.server / '.runtime/bin/server'
        server.write_bytes(b'rebuilt-but-not-yet-preserved')
        bodies = (
            '''cp() {
  case "$*" in *redeploy-backups*) return 74;; esac
  command cp "$@"
}''',
            '''cp() {
  command cp "$@" || return
  case "$*" in
    *redeploy-backups*/files/*)
      for fixture_destination do :; done
      printf 'corrupt-copy\\n' > "$fixture_destination";;
  esac
}''',
        )
        for shell in ('sh', 'bash', 'zsh'):
            if not shutil.which(shell):
                continue
            for index, body in enumerate(bodies):
                with self.subTest(shell=shell, failure=index):
                    result = self.run_shell(body + '''
if lc_begin; then
  lc_release_lock
else
  fixture_code=$?
  lc_release_lock
  exit "$fixture_code"
fi''', shell=shell)
                    self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                    self.assertEqual(server.read_bytes(), b'rebuilt-but-not-yet-preserved')
                    self.assertEqual({name: (state / name).read_bytes() for name in manifests}, manifests)
                    self.assertFalse(list((state / 'redeploy-backups').glob('redeploy.*/verified')))
                    self.assertFalse((state.parent / 'operation-lock').exists())

    def test_35_redeploy_keeps_cache_directory_modes_strict(self):
        """合法缓存目录的权限后改仍是外部变化，不随缓存文件一起放行。"""
        self.baseline()
        cache = self.server / '.tools/gobuildcache'
        bucket = cache / 'ab'
        bucket.mkdir(parents=True)
        self.create_deployment()
        state = self.server / '.deployment-state/posix'
        after = (state / 'after.tsv').read_bytes()
        (self.server / '.runtime/bin/server').write_bytes(b'known-generated-difference')
        for target in (cache, bucket):
            mode = target.stat().st_mode & 0o7777
            target.chmod(0o700 if mode != 0o700 else 0o750)
            try:
                result = self.run_shell("trap 'lc_release_lock' EXIT\nlc_begin")
                self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertEqual((state / 'after.tsv').read_bytes(), after)
                self.assertFalse(list((state / 'redeploy-backups').glob('redeploy.*')))
                self.assertFalse((state.parent / 'operation-lock').exists())
            finally:
                target.chmod(mode)

    def test_36_checkpoint_does_not_adopt_unknown_cache_objects(self):
        """运行中混入未知缓存文件时不能在新封口中把它认作本次生成物。"""
        self.baseline()
        (self.server / '.tools/gobuildcache/ab').mkdir(parents=True)
        self.create_deployment()
        state = self.server / '.deployment-state/posix'
        after = (state / 'after.tsv').read_bytes()
        unknown = self.server / '.tools/gobuildcache/ab/not-a-generated-object'
        unknown.write_bytes(b'external-content')
        result = self.run_shell("lc_context\nlc_acquire_lock\ntrap 'lc_release_lock' EXIT\nlc_checkpoint")
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual((state / 'after.tsv').read_bytes(), after)
        self.assertEqual(unknown.read_bytes(), b'external-content')
        self.assertFalse((state.parent / 'operation-lock').exists())

    def test_37_first_deployment_rejects_unknown_cache_before_claiming_ownership(self):
        """初次原点也排除非标准缓存，拒绝后修正夹具仍可正常登记与封口。"""
        for shell in ('sh', 'bash', 'zsh'):
            if not shutil.which(shell):
                continue
            with self.subTest(shell=shell):
                server = self.work / ('new-cache-' + shell)
                for directory in ('.runtime/bin', '.tools/gobuildcache/ab', 'data'):
                    (server / directory).mkdir(parents=True)
                for name, content in {
                    '.runtime/bin/server': b'original-program',
                    '.runtime/config.env': b'original-config',
                    '.tools/gobuildcache/ab/' + 'ab' + '7' * 62 + '-a': b'known-cache-index',
                    '.tools/gobuildcache/custom-note': b'unrelated-user-note',
                    'data/state.json': b'{"fixture":"preserve-initial-data"}',
                }.items():
                    (server / name).write_bytes(content)
                changes = {'SERVER_ROOT': str(server),
                           'LOG_FILE': str(server / '.runtime/logs/new.log')}
                original = {str(path.relative_to(server)): (path.read_bytes(), path.stat().st_mode & 0o7777)
                            for name in ('.runtime', '.tools', 'data')
                            for path in (server / name).rglob('*') if path.is_file()}
                result = self.run_shell('''if lc_begin; then
  lc_release_lock
  exit 90
else
  fixture_code=$?
  lc_finalize
  exit "$fixture_code"
fi''', shell=shell, changes=changes)
                self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertNotEqual(result.returncode, 90, result.stdout + result.stderr)
                state = server / '.deployment-state/posix'
                for path in (state.parent / 'owner', state / 'before.tsv', state / 'after.tsv'):
                    self.assertFalse(path.exists(), path)
                self.assertFalse((state.parent / 'operation-lock').exists())
                self.assertEqual({str(path.relative_to(server)): (path.read_bytes(), path.stat().st_mode & 0o7777)
                                  for name in ('.runtime', '.tools', 'data')
                                  for path in (server / name).rglob('*') if path.is_file()}, original)
                (server / '.tools/gobuildcache/custom-note').unlink()
                self.run_shell('lc_begin\nlc_checkpoint\nlc_finalize',
                               shell=shell, changes=changes, check=True)
                self.assertTrue((state.parent / 'owner').is_file())
                self.assertTrue((state / 'before.tsv').is_file())
                self.assertTrue((state / 'after.tsv').is_file())
                self.assertEqual((server / 'data/state.json').read_bytes(), original['data/state.json'][0])
                self.assertFalse((state.parent / 'operation-lock').exists())

    def test_33_finalize_empty_after_manifest_records_current_log(self):
        """空后态仍能封存第一条运行日志，第二输入不能被当成第一输入跳过。"""
        for shell in ('sh', 'bash', 'zsh'):
            if not shutil.which(shell):
                continue
            with self.subTest(shell=shell):
                server = self.work / ('empty-after-' + shell)
                server.mkdir()
                changes = {'SERVER_ROOT': str(server),
                           'LOG_FILE': str(server / '.runtime/logs/new.log')}
                self.run_shell('''lc_begin
lc_checkpoint
mkdir -p "$SERVER_ROOT/.runtime/logs"
printf 'first-log\\n' > "$LOG_FILE"
lc_finalize''', shell=shell, changes=changes, check=True)
                after = server / '.deployment-state/posix/after.tsv'
                rows = [row.split('\t', 3) for row in after.read_text().splitlines()]
                row = next(item for item in rows if item[3] == '.runtime/logs/new.log')
                self.assertEqual(row[0], 'F')
                self.assertEqual(row[1], hashlib.sha256(b'first-log\n').hexdigest())
                self.assertFalse((server / '.deployment-state/operation-lock').exists())

    def test_34_mac_rejected_preflight_does_not_reseal_previous_manifest(self):
        """实际Mac退出钩子只解锁被拒绝的部署，不重写旧后态或收录本轮日志。"""
        if sys.platform != 'darwin' or not shutil.which('zsh'):
            self.skipTest('MacOS failure integration requires MacOS and zsh')
        self.baseline()
        self.create_deployment()
        state = self.server / '.deployment-state/posix'
        manifests = {name: ((state / name).read_bytes(), (state / name).stat().st_mtime_ns)
                     for name in ('before.tsv', 'after.tsv')}
        (self.server / '.runtime/config.env').write_bytes(b'external-config-change')
        rejected_log = self.server / '.runtime/logs/rejected.log'
        rejected_log.write_bytes(b'preexisting-unowned-log')
        prefix = platform_entry(self.deploy, 'MacOS').read_text().rsplit('main "$@"', 1)[0]
        script = self.work / 'rejected-preflight.zsh'
        script.write_text(prefix + '''
SERVER_ROOT="$FIXTURE_SERVER"
DEPLOY_ROOT="$FIXTURE_DEPLOY"
LOG_FILE="$FIXTURE_LOG"
simulate_main() {
  initialize_deployment_lifecycle
  printf 'unexpected-success\\n'
}
simulate_main
''', encoding='utf-8')
        outside = self.work / 'outside-rejected-target'
        outside.write_bytes(b'outside-preserved')
        link = self.server / '.runtime/linked-unowned'
        for failure in ('manifest-difference', 'manifest-symlink'):
            with self.subTest(failure=failure):
                if failure == 'manifest-symlink':
                    link.symlink_to(outside)
                try:
                    result = subprocess.run(['zsh', str(script)], cwd='/', env={**self.env,
                        'FIXTURE_SERVER': str(self.server), 'FIXTURE_DEPLOY': str(self.deploy),
                        'FIXTURE_LOG': str(rejected_log)}, text=True, capture_output=True, timeout=20)
                    self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                    self.assertNotIn('unexpected-success', result.stdout + result.stderr)
                    self.assertEqual({name: ((state / name).read_bytes(), (state / name).stat().st_mtime_ns)
                                      for name in manifests}, manifests)
                    self.assertEqual(rejected_log.read_bytes(), b'preexisting-unowned-log')
                    self.assertEqual((self.server / '.runtime/config.env').read_bytes(), b'external-config-change')
                    self.assertEqual(outside.read_bytes(), b'outside-preserved')
                    self.assertFalse((state.parent / 'operation-lock').exists())
                    self.assertFalse((state.parent / 'restart-lock').exists())
                finally:
                    if link.is_symlink():
                        link.unlink()

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
