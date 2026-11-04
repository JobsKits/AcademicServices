"""Jobs：在本机隔离复制并验证冻结APP；不替代另一台电脑或Windows验收。"""
import argparse
from datetime import datetime
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT = next(parent for parent in Path(__file__).resolve().parents if (parent / '代码').is_dir() and (parent / '测试').is_dir())
PROJECT = ROOT / "代码/前端/PC端/Python/Zhixu"


def verify(app, artifacts):
    if sys.platform != "darwin":
        raise RuntimeError("冻结APP验证需要MacOS")
    app = app.resolve(strict=True)
    entry = app / "Contents/MacOS/Zhixu"
    if not entry.is_file() or app.suffix != ".app":
        raise RuntimeError("请选择已生成的知序APP")
    artifacts.mkdir(parents=True, exist_ok=True)
    checked, unexpected = 0, []
    for file in (app / "Contents").rglob("*"):
        if not file.is_file() or file.is_symlink():
            continue
        # Mach-O魔数覆盖本机/通用二进制，不把资源、PYC或许可证当作库。
        with file.open("rb") as stream:
            magic = stream.read(4)
        if magic not in (b"\xfe\xed\xfa\xce", b"\xce\xfa\xed\xfe", b"\xfe\xed\xfa\xcf", b"\xcf\xfa\xed\xfe", b"\xca\xfe\xba\xbe", b"\xbe\xba\xfe\xca", b"\xca\xfe\xba\xbf", b"\xbf\xba\xfe\xca"):
            continue
        result = subprocess.run(["/usr/bin/otool", "-L", str(file)], capture_output=True, text=True, check=True)
        checked += 1
        for line in result.stdout.splitlines()[1:]:
            dependency = line.strip().split(" (", 1)[0]
            if dependency.startswith("/") and not dependency.startswith(("/System/", "/usr/lib/")):
                unexpected.append({"file": str(file.relative_to(app)), "dependency": dependency})
    if unexpected:
        raise RuntimeError("包存在外部绝对库依赖：" + json.dumps(unexpected, ensure_ascii=False))
    with tempfile.TemporaryDirectory(prefix="知序 迁移验证 ") as temporary:
        temporary = Path(temporary)
        moved = temporary / "复制改名后的知序.app"
        shutil.copytree(app, moved, symlinks=True)
        environment = {k: v for k, v in os.environ.items() if k not in ("PYTHONPATH", "PYTHONHOME", "VIRTUAL_ENV", "QT_PLUGIN_PATH", "QT_QPA_PLATFORM_PLUGIN_PATH", "QT_QPA_PLATFORM")}
        environment.update(PATH="/usr/bin:/bin:/usr/sbin:/sbin", ZHIXU_DATA_DIR=str(temporary / "isolated-user"))
        image = temporary / "native.png"
        result = subprocess.run([str(moved / "Contents/MacOS/Zhixu"), "--screenshot", str(image)], cwd="/", env=environment, capture_output=True, text=True, timeout=25)
        (artifacts / "native-relocation.log").write_text(result.stdout + result.stderr, encoding="utf-8")
        if result.returncode or not image.is_file() or not image.stat().st_size:
            raise RuntimeError("复制后的APP未成功取得首屏，请查看native-relocation.log")
        shutil.copy2(image, artifacts / "frozen-relocated-native.png")
    dmg = app.parent / "Zhixu.dmg"
    if not dmg.is_file():
        raise RuntimeError("与APP同批的DMG不存在")
    manifest = {
        "checked_at": datetime.now().astimezone().isoformat(),
        "bundle": str(app.relative_to(PROJECT.parent)),
        "dmg": str(dmg.relative_to(PROJECT.parent)),
        "dmg_sha256": hashlib.sha256(dmg.read_bytes()).hexdigest(),
        "native_macho_files_checked": checked,
        "external_non_system_dependencies": unexpected,
        "relocated_native_launch": True,
        "scope": "MacOS Apple Silicon local build + independent renamed copied bundle, not another computer or actual AirDrop AppTranslocation",
        "source_sha256": {str(file.relative_to(PROJECT)): hashlib.sha256(file.read_bytes()).hexdigest() for base in ("src", "Scripts") for file in (PROJECT / base).rglob("*") if file.is_file() and file.suffix in (".py", ".ps1", ".svg", ".txt")},
    }
    (artifacts / "package-validation.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return {k: v for k, v in manifest.items() if k != "source_sha256"}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, default=PROJECT.parent / "知序.app")
    parser.add_argument("--artifacts", type=Path, default=ROOT / "测试/前端/PC端/Python/证据/本轮" / ("桌面成品核验-" + datetime.now().strftime("%Y.%m.%d %H-%M-%S")))
    options = parser.parse_args()
    print(json.dumps(verify(options.app, options.artifacts), ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
