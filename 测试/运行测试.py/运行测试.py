#!/usr/bin/env python3
"""运行选定的隔离回归；测试源码和证据始终留在仓库外层的测试目录。"""

from __future__ import annotations

import argparse
from datetime import datetime
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import time


ROOT = Path(__file__).resolve().parents[2]
TEST_ROOT = ROOT / "测试"
SERVER = ROOT / "代码/后端/后端代码"
DESKTOP = ROOT / "代码/前端/PC端/Python/Zhixu"
FLUTTER = ROOT / "代码/前端/移动端/Flutter"
GROUPS = {
    "go": "后端同包单元／并发回归及 vet；缺专用 PG 库会明确跳过数据库用例",
    "desktop": "桌面数据、离屏界面、打包与引导保护；不生成 APP／DMG／EXE",
    "http": "编译并启动临时 Go 服务，执行真实回环 HTTP 与重启闭环",
    "qr": "独立部署二维码工具单元回归；Go overlay 注入外置测试，不启动服务",
    "deploy": "部署语法、假工具、临时回环与 PTY 保护；不安装或发布公网",
    "mini": "微信客户端仓库逻辑；不启动微信开发者工具或真机",
    "flutter": "Flutter 仓库与 Widget 回归；不安装依赖或打移动端包",
    "harmony": "鸿蒙 HTTPS 宿主与生成器合同；不调用 DevEco 或生成 HAP",
}


def parser() -> argparse.ArgumentParser:
    value = argparse.ArgumentParser(description=__doc__)
    value.add_argument("groups", nargs="*", choices=tuple(GROUPS), metavar="分组")
    value.add_argument("--group", action="append", choices=(*GROUPS, "all"), default=[], help="选择分组，可重复；all 表示全部")
    value.add_argument("--all", action="store_true", help="显式运行全部分组；需要完整本地工具链")
    value.add_argument("--list", action="store_true", help="只显示分组，不创建日志或运行测试")
    value.add_argument("--go", dest="go_bin", help="使用现有 Go 可执行文件，也可设置 GO_BIN")
    value.add_argument("--python", dest="python_bin", help="桌面测试解释器，需要已安装 PySide6")
    value.add_argument("--flutter", dest="flutter_bin", help="使用现有 Flutter 可执行文件")
    value.add_argument("--timeout", type=int, default=900, help="每条命令最长秒数，默认 900")
    return value


def executable(explicit: str | None, candidates: list[Path], name: str) -> str:
    if explicit:
        path = shutil.which(explicit) or str(Path(explicit).expanduser().resolve())
        if Path(path).is_file() and os.access(path, os.X_OK):
            return str(Path(path).resolve())
        raise RuntimeError(f"指定的 {name} 不是可执行文件：{explicit}")
    for path in candidates:
        if path.is_file() and os.access(path, os.X_OK):
            return str(path)
    path = shutil.which(name)
    if path:
        return path
    raise RuntimeError(f"没有可用的 {name}；准备现有工具后显式传入路径，本入口不会下载依赖。")


def go_executable(options: argparse.Namespace) -> str:
    binary = "go.exe" if os.name == "nt" else "go"
    return executable(
        options.go_bin or os.environ.get("GO_BIN"),
        [SERVER / ".tools/go/bin" / binary],
        "go",
    )


def desktop_python(options: argparse.Namespace) -> str:
    binary = ".build-venv/Scripts/python.exe" if os.name == "nt" else ".build-venv/bin/python"
    return executable(options.python_bin, [DESKTOP / binary, Path(sys.executable)], "python3")


def command_plan(group: str, options: argparse.Namespace, overlay: Path, evidence: Path):
    env = os.environ.copy()
    env.update({"PYTHONDONTWRITEBYTECODE": "1", "PYTHONUNBUFFERED": "1"})
    if group in {"go", "http", "qr"}:
        go = go_executable(options)
        env.update({"GO_BIN": go, "GOTOOLCHAIN": "local", "GOPROXY": "off", "GOTELEMETRY": "off"})
        if group == "qr":
            return [([go, "test", "-mod=readonly", "-overlay", str(overlay), "-count=1", "-v", "./..."], ROOT / "部署/公共组件/地址二维码", env)]
        if group == "go":
            return [
                ([go, "test", "-overlay", str(overlay), "-race", "-count=1", "-v", "./..."], SERVER, env),
                ([go, "vet", "-overlay", str(overlay), "./..."], SERVER, env),
            ]
        return [([sys.executable, str(TEST_ROOT / "后端/接口/test_http.py")], ROOT, env)]
    if group == "desktop":
        source = str(DESKTOP / "src")
        env["PYTHONPATH"] = source + (os.pathsep + env["PYTHONPATH"] if env.get("PYTHONPATH") else "")
        env["QT_QPA_PLATFORM"] = "offscreen"
        env["ACADEMIC_TEST_ARTIFACTS"] = str(evidence / "桌面截图")
        return [([desktop_python(options), "-m", "unittest", "discover", "-s", str(TEST_ROOT / "前端/PC端/Python"), "-v"], ROOT, env)]
    if group == "deploy":
        return [
            ([sys.executable, str(TEST_ROOT / "部署/test_deploy.py")], ROOT, env),
            ([sys.executable, str(TEST_ROOT / "部署/【测试】部署双模式.py/【测试】部署双模式.py")], ROOT, env),
            ([sys.executable, str(TEST_ROOT / "部署/【测试】反部署.py/【测试】反部署.py")], ROOT, env),
        ]
    if group == "mini":
        return [([executable(None, [], "node"), "--test", str(TEST_ROOT / "前端/微信小程序/test_mini.cjs"), str(TEST_ROOT / "前端/微信小程序/test_shop.cjs")], ROOT, env)]
    if group == "flutter":
        flutter = executable(options.flutter_bin, [], "flutter")
        env["CI"] = "true"
        return [([flutter, "test", "--no-pub", str(TEST_ROOT / "前端/移动端/Flutter/repository_test.dart"), str(TEST_ROOT / "前端/移动端/Flutter/widget_test.dart"), str(TEST_ROOT / "前端/后台管理端/Flutter/admin_widget_test.dart"), str(TEST_ROOT / "前端/移动端/Flutter/shop_test.dart")], FLUTTER, env)]
    return [([sys.executable, str(TEST_ROOT / "前端/移动端/鸿蒙/test_prepare_harmony.py")], ROOT, env)]


def group_evidence(group: str, stamp: str) -> Path:
    """按被测职责保存新证据，跨组根目录仅存摘要索引。"""
    parents = {
        "go": "后端/证据/本轮",
        "http": "后端/证据/本轮",
        "deploy": "部署/证据/本轮",
        "qr": "部署/证据/本轮",
        "desktop": "前端/PC端/Python/证据/本轮",
        "mini": "前端/微信小程序/证据/本轮",
        "harmony": "前端/移动端/鸿蒙/证据/本轮",
        "flutter": "前端/报告与证据/本轮",
    }
    return TEST_ROOT / parents[group] / stamp


def execute(command: list[str], cwd: Path, env: dict[str, str], logfile: Path, timeout: int):
    started = time.monotonic()
    print(f"运行：{subprocess.list2cmdline(command)}", flush=True)
    print(f"工作目录：{cwd}\n日志：{logfile}", flush=True)
    with logfile.open("w", encoding="utf-8") as stream:
        try:
            process = subprocess.Popen(
                command, cwd=cwd, env=env, stdout=stream, stderr=subprocess.STDOUT,
                start_new_session=os.name != "nt",
                creationflags=subprocess.CREATE_NEW_PROCESS_GROUP if os.name == "nt" else 0,
            )
            try:
                code = process.wait(timeout=timeout)
            except (subprocess.TimeoutExpired, KeyboardInterrupt) as error:
                if os.name == "nt":
                    subprocess.run(["taskkill", "/PID", str(process.pid), "/T", "/F"], stdout=stream, stderr=subprocess.STDOUT, check=False)
                else:
                    os.killpg(process.pid, signal.SIGTERM)
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    if os.name == "nt":
                        process.kill()
                    else:
                        os.killpg(process.pid, signal.SIGKILL)
                    process.wait()
                if isinstance(error, KeyboardInterrupt):
                    raise
                stream.write(f"\n超过 {timeout} 秒，当前命令及其子进程已停止。\n")
                code = 124
        except OSError:
            raise
    output = logfile.read_text(encoding="utf-8", errors="replace")
    print(output, end="" if output.endswith("\n") else "\n", flush=True)
    return {"exit_code": code, "seconds": round(time.monotonic() - started, 3), "log": str(logfile.relative_to(TEST_ROOT))}


def main() -> int:
    options = parser().parse_args()
    groups = list(GROUPS) if options.all or "all" in options.group else list(dict.fromkeys([*options.groups, *options.group]))
    if options.list or not groups:
        for name, description in GROUPS.items():
            print(f"{name}: {description}")
        return 0
    if options.timeout <= 0:
        parser().error("--timeout 必须大于 0")
    print("所选测试只使用临时业务数据；不会安装依赖、注册服务或发布公网。")
    print("HTTP 分组会编译临时后端并监听动态回环端口；Go 会使用现有依赖缓存。")
    print("Go overlay 只在临时 JSON 中映射外部测试文件，代码目录不会创建测试副本或链接。")
    print("分组：" + "、".join(groups), flush=True)
    stamp = datetime.now().strftime("%Y.%m.%d %H-%M-%S-%f")
    evidence = TEST_ROOT / "报告与证据/本轮" / stamp
    evidence.mkdir(parents=True)
    summary = {"started_at": datetime.now().astimezone().isoformat(), "groups": {}}
    failed = False
    with tempfile.TemporaryDirectory(prefix="academic-go-overlay-") as temp:
        overlay = Path(temp) / "overlay.json"
        if "go" in groups:
            for name in ("engine_test.go", "http_test.go"):
                if not (TEST_ROOT / "后端" / name).is_file():
                    raise RuntimeError(f"缺少外部后端测试文件：{name}")
        replacements = {
            str(SERVER / "internal/platform" / file.name): str(file)
            for file in sorted((TEST_ROOT / "后端").glob("*_test.go"))
        }
        if "qr" in groups:
            replacements[str(ROOT / "部署/公共组件/地址二维码/main_test.go")] = str(TEST_ROOT / "部署/地址二维码/main_test.go")
        overlay.write_text(json.dumps({"Replace": replacements}, ensure_ascii=False, indent=2), encoding="utf-8")
        for group in groups:
            records = []
            try:
                group_output = group_evidence(group, stamp)
                group_output.mkdir(parents=True, exist_ok=True)
                for index, (command, cwd, env) in enumerate(command_plan(group, options, overlay, group_output), 1):
                    result = execute(command, cwd, env, group_output / f"{group}-{index}.log", options.timeout)
                    records.append(result)
                    if result["exit_code"] != 0:
                        failed = True
                        break
                summary["groups"][group] = {"status": "失败" if any(r["exit_code"] for r in records) else "命令成功，跳过项以日志为准", "commands": records}
            except (OSError, RuntimeError) as error:
                failed = True
                print(f"{group} 未执行／阻塞：{error}", file=sys.stderr, flush=True)
                summary["groups"][group] = {"status": "阻塞", "reason": str(error), "commands": records}
    summary["finished_at"] = datetime.now().astimezone().isoformat()
    (evidence / "执行摘要.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"执行摘要：{evidence / '执行摘要.json'}")
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
