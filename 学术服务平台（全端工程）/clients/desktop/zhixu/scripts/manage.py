"""Jobs 桌面客户端环境准备、打包与启动；以本文件位置寻址。"""
import argparse
import datetime
import importlib.util
import json
import os
import shutil
import subprocess
import sys
import venv
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[1]
DELIVERY = PROJECT.parent
ENV = PROJECT / ".build-venv"
DIST = DELIVERY / "dist"
WORK = PROJECT / ".build"


def confirm(message):
    try:
        if input(message) != "":
            raise RuntimeError("已取消，未继续当前流程")
    except EOFError as error:
        raise RuntimeError("没有交互输入，流程停止；请双击平台入口") from error


def intro(mode, confirmed=False):
    print("知序桌面端 · " + ("生成安装包" if mode == "build" else "源码运行"))
    print("影响范围：本工程内 .build-venv / .build；仅缺少依赖时联网安装，不升级系统环境。")
    print("来源：https://pypi.org/；固定 PySide6 6.12.0、PyInstaller 6.22.3。")
    if mode == "build":
        print("会删除本应用固定 dist 内的旧产物；成功后定位产物并启动本次软件。")
        print("输出：dist/YYYY.MM.DD HH-mm-ss/；macOS生成APP+DMG，Windows生成EXE目录+ZIP。")
    print("日志：本工程 .build/session.log；按Ctrl+C或输入任意字符取消。")
    if not confirmed:
        confirm("已了解用途与范围，直接回车继续：")


def execute(args, **kwargs):
    print("执行：", " ".join(str(a) for a in args), flush=True)
    with subprocess.Popen([str(a) for a in args], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, errors="replace", **kwargs) as process:
        for line in process.stdout:
            print(line, end="", flush=True)
        code = process.wait()
    if code:
        raise RuntimeError("命令失败，退出码 " + str(code))


def python_path():
    return ENV / ("Scripts/python.exe" if os.name == "nt" else "bin/python")


def ensure_environment(mode):
    if not (3, 10) <= sys.version_info[:2] < (3, 16):
        raise RuntimeError("需要Python3.10—3.15；建议当前最新3.15.2")
    current = python_path()
    if not current.exists():
        venv.EnvBuilder(with_pip=True, system_site_packages=True).create(ENV)
    requested = {"PySide6": "6.12.0"}
    if mode == "build":
        requested["PyInstaller"] = "6.22.3"
    for name, version in requested.items():
        probe = subprocess.run([str(current), "-c", f"import {name}; assert {name}.__version__ == {version!r}"], capture_output=True)
        if probe.returncode:
            confirm(f"缺少 {name}=={version}。来源https://pypi.org/，目标工程内虚拟环境；直接回车安装，任意字符取消：")
            execute([current, "-m", "pip", "install", "--disable-pip-version-check", name + "==" + version])
            execute([current, "-c", f"import {name}; assert {name}.__version__ == {version!r}"])
    return current


def checked_dist():
    if DIST.is_symlink() or DIST.name != "dist" or DIST.parent != DELIVERY or DIST.resolve() == PROJECT:
        raise RuntimeError("拒绝清理异常 dist 路径")
    if not DIST.exists():
        return
    for shortcut in (DELIVERY / "知序.app", DELIVERY / "知序.dmg"):
        if shortcut.is_symlink():
            try:
                shortcut.resolve().relative_to(DIST.resolve())
            except ValueError as error:
                raise RuntimeError("快捷入口指向其它应用，拒绝改动") from error
            shortcut.unlink()
        elif shortcut.exists():
            raise RuntimeError("快捷入口同名真实文件存在，拒绝覆盖")
    for name in ("知序.exe.lnk", "知序.zip.lnk"):
        shortcut = DELIVERY / name
        if shortcut.exists():
            # 本构建器只管理随自身清单登记且哈希一致的快捷方式。
            import hashlib
            manifest = WORK / "shortcuts.json"
            known = json.loads(manifest.read_text()) if manifest.exists() else {}
            if hashlib.sha256(shortcut.read_bytes()).hexdigest() != known.get(name):
                raise RuntimeError("现有快捷方式未获本应用清单确认，拒绝覆盖")
            shortcut.unlink()
    shutil.rmtree(DIST)
    if DIST.exists():
        raise RuntimeError("旧产物未成功清除")


def shortcut_windows(executable, package, stamp):
    import hashlib
    script = WORK / "shortcut.ps1"
    script.write_text('param($Link,$Target,$Directory)\n$w=New-Object -ComObject WScript.Shell\n$s=$w.CreateShortcut($Link)\n$s.TargetPath=$Target\n$s.WorkingDirectory=$Directory\n$s.Save()\n', encoding="utf-8-sig")
    manifest = {}
    for name, target in (("知序.exe.lnk", executable), ("知序.zip.lnk", package)):
        link = DELIVERY / name
        if link.exists():
            raise RuntimeError("快捷入口同名真实文件存在")
        execute(["powershell.exe", "-NoProfile", "-File", script, link, target, stamp])
        manifest[name] = hashlib.sha256(link.read_bytes()).hexdigest()
    (WORK / "shortcuts.json").write_text(json.dumps(manifest), encoding="utf-8")


def build(current):
    if sys.platform not in ("darwin", "win32"):
        raise RuntimeError("安装包须在macOS或Windows目标平台本机生成")
    if sys.platform == "darwin" and not shutil.which("hdiutil"):
        raise RuntimeError("缺少macOS系统hdiutil，停止构建")
    checked_dist()
    stamp = DIST / datetime.datetime.now().strftime("%Y.%m.%d %H-%M-%S")
    stamp.mkdir(parents=True)
    args = [current, "-m", "PyInstaller", "--noconfirm", "--windowed", "--noupx", "--name", "Zhixu", "--paths", PROJECT / "src", "--add-data", str(PROJECT / "src/zhixu/assets") + os.pathsep + "zhixu/assets", "--distpath", stamp, "--workpath", WORK / "work", "--specpath", WORK / "spec"]
    # Homebrew等非wheel布局不能依赖上游Hook隐式发现平台插件；按Qt真实插件根显式打包。
    plugin_root = Path(subprocess.check_output([str(current), "-c", "from PySide6.QtCore import QLibraryInfo; print(QLibraryInfo.path(QLibraryInfo.PluginsPath))"], text=True).strip())
    plugin_destination = "PySide6/plugins" if os.name == "nt" else "PySide6/Qt/plugins"
    platform_file = "qwindows.dll" if os.name == "nt" else "libqcocoa.dylib"
    if not (plugin_root / "platforms" / platform_file).is_file():
        raise RuntimeError("缺少本机Qt平台插件：" + str(plugin_root / "platforms" / platform_file))
    for group in ("platforms", "imageformats", "iconengines"):
        for plugin in sorted((plugin_root / group).glob("*")):
            if plugin.is_file() and plugin.suffix.lower() in (".dll", ".dylib", ".so"):
                if group != "platforms" and "svg" not in plugin.name.lower():
                    continue
                args += ["--add-binary", str(plugin) + os.pathsep + plugin_destination + "/" + group]
    if sys.platform == "darwin":
        args += ["--osx-bundle-identifier", "asia.zhixu.desktop"]
    args += [PROJECT / "src/entry.py"]
    execute(args, cwd=PROJECT)
    freeze = subprocess.check_output([str(current), "-m", "pip", "freeze"], text=True)
    (stamp / "构建依赖快照.txt").write_text(freeze, encoding="utf-8")
    if sys.platform == "darwin":
        app = stamp / "Zhixu.app"
        if not (app / "Contents/MacOS/Zhixu").is_file() or not (app / "Contents/Frameworks/zhixu/assets/brand.svg").is_file():
            raise RuntimeError("APP入口或包内品牌资源缺失")
        smoke_image = WORK / "frozen-smoke.png"
        smoke_image.unlink(missing_ok=True)
        smoke_env = dict(os.environ, ZHIXU_DATA_DIR=str(WORK / "smoke-data"))
        smoke_env.pop("PYTHONPATH", None)
        smoke_env.pop("VIRTUAL_ENV", None)
        execute([app / "Contents/MacOS/Zhixu", "--screenshot", smoke_image], env=smoke_env, cwd=WORK)
        if not smoke_image.exists() or not smoke_image.stat().st_size:
            raise RuntimeError("安装包首次界面验证失败，不发布快捷入口")
        dmg = stamp / "Zhixu.dmg"
        execute(["hdiutil", "create", "-volname", "Zhixu", "-srcfolder", app, "-ov", "-format", "UDZO", dmg])
        if not dmg.exists() or not dmg.stat().st_size:
            raise RuntimeError("DMG未生成")
        for name, target in (("知序.app", app), ("知序.dmg", dmg)):
            (DELIVERY / name).symlink_to(target.relative_to(DELIVERY))
        execute(["open", "-R", dmg])
        execute(["open", "-n", app])
    else:
        executable = stamp / "Zhixu/Zhixu.exe"
        if not executable.exists():
            raise RuntimeError("EXE未生成")
        package = Path(shutil.make_archive(str(stamp / "Zhixu"), "zip", root_dir=stamp, base_dir="Zhixu"))
        shortcut_windows(executable, package, stamp)
        subprocess.Popen(["explorer.exe", str(stamp)])
        subprocess.Popen([str(executable)], cwd=executable.parent)
    print("成功：本次产物位于 " + str(stamp))


def main():
    parser = argparse.ArgumentParser(description="知序桌面端开发与打包工具")
    parser.add_argument("mode", choices=["run", "build", "check"])
    parser.add_argument("--entry-confirmed", action="store_true", help="外层入口已展示自述并取得本次回车确认")
    options = parser.parse_args()
    if options.mode == "check":
        print(json.dumps({"project": str(PROJECT), "python": sys.version, "pyside": importlib.util.find_spec("PySide6") is not None, "dist_symlink": DIST.is_symlink()}, ensure_ascii=False, indent=2))
        return 0
    intro(options.mode, options.entry_confirmed)
    WORK.mkdir(exist_ok=True)
    # 内层直调同样保留日志；外层设置标记时由平台入口统一落盘。
    if not os.getenv("ZHIXU_ENTRY_LOGGING"):
        class Tee:
            def __init__(self, terminal, log):
                self.terminal, self.log = terminal, log
            def write(self, content):
                self.terminal.write(content)
                self.log.write(content)
            def flush(self):
                self.terminal.flush()
                self.log.flush()
        logfile = (WORK / "session.log").open("w", encoding="utf-8")
        sys.stdout = Tee(sys.stdout, logfile)
        sys.stderr = Tee(sys.stderr, logfile)
    current = ensure_environment(options.mode)
    if options.mode == "build":
        build(current)
    else:
        environment = dict(os.environ, PYTHONPATH=str(PROJECT / "src"))
        execute([current, "-m", "zhixu.app"], env=environment, cwd=PROJECT)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (RuntimeError, OSError, KeyboardInterrupt) as error:
        print("失败：" + str(error), file=sys.stderr)
        raise SystemExit(1)
