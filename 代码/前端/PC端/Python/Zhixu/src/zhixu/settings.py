"""用户配置只保存地址、主题与待核对写操作，绝不保存口令或会话。"""
import json
import os
import sys
import tempfile
from pathlib import Path


def data_root():
    if os.getenv("ZHIXU_DATA_DIR"):
        return Path(os.environ["ZHIXU_DATA_DIR"]).expanduser()
    if sys.platform == "win32":
        return Path(os.getenv("LOCALAPPDATA", Path.home() / "AppData/Local")) / "Zhixu"
    if sys.platform == "darwin":
        return Path.home() / "Library/Application Support/Zhixu"
    return Path(os.getenv("XDG_DATA_HOME", Path.home() / ".local/share")) / "zhixu"


class Settings:
    def __init__(self, root=None):
        self.root = Path(root) if root else data_root()
        self.path = self.root / "settings.json"
        self.values = {"theme": "system", "language": "zh", "api": "http://127.0.0.1:8080/api/v1", "timeout": 2.5}
        if self.path.exists():
            try:
                loaded = json.loads(self.path.read_text(encoding="utf-8"))
                if isinstance(loaded, dict):
                    self.values.update({k: v for k, v in loaded.items() if k in self.values})
            except (ValueError, OSError):
                pass

    def save(self, **values):
        self.values.update(values)
        self.write_json(self.path, self.values)

    def write_json(self, path, value):
        self.root.mkdir(parents=True, exist_ok=True, mode=0o700)
        fd, temporary = tempfile.mkstemp(dir=self.root, prefix=".pending-")
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as stream:
                json.dump(value, stream, ensure_ascii=False)
                stream.flush()
                os.fsync(stream.fileno())
            os.replace(temporary, path)
            path.chmod(0o600)
        finally:
            Path(temporary).unlink(missing_ok=True)
