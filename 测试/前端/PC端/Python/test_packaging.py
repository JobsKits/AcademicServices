import importlib.util
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = next(parent for parent in Path(__file__).resolve().parents if (parent / '代码').is_dir() and (parent / '测试').is_dir())
SCRIPT = ROOT / "代码/前端/PC端/Python/Zhixu/Scripts/manage.py"
SPEC = importlib.util.spec_from_file_location("zhixu_manage", SCRIPT)
manage = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(manage)


class BuildSafetyTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="知序 打包夹具-")
        self.root = Path(self.temp.name) / "独立工程（迁移）"
        self.root.mkdir()
        self.source = self.root / "Zhixu"
        self.source.mkdir()
        self.dist = self.root / "Dist"
        self.dist.mkdir()
        self.work = self.source / ".build"
        self.work.mkdir()
        self.patch = patch.multiple(manage, DELIVERY=self.root, PROJECT=self.source, DIST=self.dist, WORK=self.work)
        self.patch.start()

    def tearDown(self):
        self.patch.stop()
        self.temp.cleanup()

    def test_owned_dist_cleanup_does_not_touch_source(self):
        (self.dist / "old.txt").write_text("old")
        (self.source / "keep.txt").write_text("source")
        manage.checked_dist()
        self.assertFalse(self.dist.exists())
        self.assertTrue((self.source / "keep.txt").exists())

    def test_symlink_dist_refused_before_deleting_anything(self):
        self.dist.rmdir()
        outside = self.root / "external"
        outside.mkdir()
        (outside / "keep").write_text("safe")
        self.dist.symlink_to(outside, target_is_directory=True)
        with self.assertRaises(RuntimeError):
            manage.checked_dist()
        self.assertTrue((outside / "keep").exists())

    def test_real_same_name_shortcut_refused(self):
        (self.root / "知序.app").write_text("user file")
        with self.assertRaises(RuntimeError):
            manage.checked_dist()
        self.assertTrue(self.dist.exists())

    def test_foreign_shortcut_refused(self):
        (self.root / "知序.app").symlink_to("external.app")
        with self.assertRaises(RuntimeError):
            manage.checked_dist()
        self.assertTrue((self.root / "知序.app").is_symlink())

    def test_owned_relative_shortcuts_removed(self):
        (self.root / "知序.app").symlink_to("Dist/old/Zhixu.app")
        manage.checked_dist()
        self.assertFalse((self.root / "知序.app").is_symlink())

    def test_eof_and_any_nonempty_input_cancel(self):
        for value in (" ", "YES", "cancel"):
            with self.subTest(value=value), patch("builtins.input", return_value=value), self.assertRaises(RuntimeError):
                manage.confirm("Confirm")
        with patch("builtins.input", side_effect=EOFError()), self.assertRaises(RuntimeError):
            manage.confirm("Confirm")

    def test_wrong_platform_cannot_start_cleaning(self):
        with patch.object(manage.sys, "platform", "linux"), self.assertRaises(RuntimeError):
            manage.build("python")
        self.assertTrue(self.dist.exists())


if __name__ == "__main__":
    unittest.main()
