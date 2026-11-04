import copy
import os
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
from PySide6.QtCore import Qt
from PySide6.QtWidgets import QApplication, QPushButton, QLabel
from zhixu.app import MainWindow
from zhixu.repository import Repository, SERVICES
from zhixu.settings import Settings


class RenderRepository:
    def __init__(self):
        self.state = {"user": {"id": "customer", "name": "客户", "role": "customer"}, "source": "real", "notice": "真实服务器", "services": copy.deepcopy(SERVICES), "cases": [], "pending": None, "real_session": True}
    def snapshot(self):
        return copy.deepcopy(self.state)
    def refresh(self):
        return self.snapshot()


class GuiTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.app = QApplication.instance() or QApplication([])
        cls.app.setStyle("Fusion")

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.settings = Settings(self.temp.name)
        self.repo = RenderRepository()
        self.window = MainWindow(self.settings, self.repo)
        self.window.refresh_timer.stop()

    def tearDown(self):
        self.window.close()
        self.window.deleteLater()
        self.app.processEvents()
        self.temp.cleanup()

    def test_home_has_exactly_three_services(self):
        labels = [label.text() for label in self.window.home.findChildren(QLabel)]
        self.assertTrue(any("毕业论文" in x for x in labels))
        self.assertTrue(any("普刊" in x for x in labels))
        self.assertTrue(any("编译" in x for x in labels))
        self.assertEqual(sum(b.text() == "提交需求" for b in self.window.home.findChildren(QPushButton)), 3)

    def test_real_empty_workspace_has_reload_and_new_request(self):
        labels = [label.text() for label in self.window.workspace.findChildren(QLabel)]
        self.assertIn("还没有需求", labels)
        names = [b.text() for b in self.window.workspace.findChildren(QPushButton)]
        self.assertIn("重新加载我的需求", names)
        self.assertIn("去选择服务", names)

    def test_theme_three_modes_and_restart_persistence(self):
        self.window.theme.setCurrentIndex(2)
        self.assertEqual(self.window.colors["bg"], "#101b20")
        self.assertEqual(Settings(self.temp.name).values["theme"], "dark")
        self.window.theme.setCurrentIndex(1)
        self.assertEqual(self.window.colors["bg"], "#f4f7f7")
        self.window.theme.setCurrentIndex(0)
        self.assertEqual(Settings(self.temp.name).values["theme"], "system")

    def test_system_theme_changes_are_live_manual_is_stable(self):
        hints = self.app.styleHints()
        # offscreen平台不提供系统外观变更，用Qt实际信号覆盖订阅与手动优先级。
        with patch("zhixu.app.QApplication.styleHints", return_value=SimpleNamespace(colorScheme=lambda: Qt.ColorScheme.Dark)):
            hints.colorSchemeChanged.emit(Qt.ColorScheme.Dark)
            self.assertEqual(self.window.colors["bg"], "#101b20")
            self.window.theme.setCurrentIndex(1)
            hints.colorSchemeChanged.emit(Qt.ColorScheme.Dark)
            self.assertEqual(self.window.colors["bg"], "#f4f7f7")

    def test_quote_offer_has_customer_accept_action(self):
        self.window.state["cases"] = [{"id": "one", "owner_id": "customer", "service_id": "editing", "title": "稿件润色", "description": "本人稿件", "status": "awaiting_quote_accept", "version": 1, "quote": {"id": "q1", "status": "offered", "scope": "本版服务条款", "amount_minor": 10000, "prepay_minor": 0, "revision_limit": 2}, "order": None}]
        self.window.render_workspace()
        names = [b.text() for b in self.window.workspace.findChildren(QPushButton)]
        self.assertIn("确认本版报价并生成订单", names)
        self.assertIn("撤回未成交需求", names)

    def test_cancellation_and_change_use_offered_contract(self):
        self.window.state["cases"] = [{"id": "one", "title": "稿件", "status": "in_service", "version": 3, "order": {"status": "in_service", "cancellation": {"status": "offered", "settlement_minor": 10000}, "changes": [{"id": "change", "status": "offered", "amount_minor": 20000, "scope": "新条款"}]}}]
        self.window.render_workspace()
        names = [b.text() for b in self.window.workspace.findChildren(QPushButton)]
        for name in ("确认取消与最终结算", "拒绝取消方案", "确认服务变更", "拒绝服务变更"):
            self.assertIn(name, names)
        labels = [label.text() for label in self.window.workspace.findChildren(QLabel)]
        self.assertTrue(any("最终应付 ¥100.00" in label for label in labels))
        self.assertFalse(any("settlement_minor" in label for label in labels))

    def test_service_form_only_shows_relevant_required_fields(self):
        captured = []
        def inspect_and_cancel(dialog):
            captured.append([x.text() for x in dialog.findChildren(QLabel)])
            return 0
        with patch("zhixu.app.QDialog.exec", inspect_and_cancel):
            for service in SERVICES:
                self.window.create_case(service)
        graduation, journal, editing = captured
        self.assertIn("专业 / 研究方向 *", graduation)
        self.assertIn("学历 / 稿件阶段 *", graduation)
        self.assertIn("专业 / 研究方向 *", journal)
        self.assertNotIn("学历 / 稿件阶段 *", journal)
        self.assertIn("原文 → 目标语言 *", editing)
        self.assertNotIn("专业 / 研究方向 *", editing)
        self.assertNotIn("学历 / 稿件阶段 *", editing)

    def test_light_dark_text_contrast(self):
        def brightness(color):
            channels = [int(color[i:i+2], 16) / 255 for i in (1,3,5)]
            channels = [x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in channels]
            return sum(x * w for x,w in zip(channels,(.2126,.7152,.0722)))
        for mode in (1,2):
            self.window.theme.setCurrentIndex(mode)
            c = self.window.colors
            for fg,bg in (("text","bg"),("sub","bg"),("text","card"),("sub","card"),("onbrand","brand"),("disabled","bg")):
                x,y=sorted((brightness(c[fg]),brightness(c[bg])))
                self.assertGreaterEqual((y+.05)/(x+.05),4.5, (mode,fg,bg))

    def test_window_layout_and_theme_render(self):
        artifacts = Path(os.environ.get("ACADEMIC_TEST_ARTIFACTS", Path(__file__).parent / "证据/本次截图"))
        artifacts.mkdir(parents=True, exist_ok=True)
        for mode,size,name in ((1,(1180,800),"home-light"),(2,(760,600),"home-dark-narrow")):
            self.window.theme.setCurrentIndex(mode)
            self.window.resize(*size)
            self.window.show()
            self.app.processEvents()
            pixmap = self.window.grab()
            self.assertFalse(pixmap.isNull())
            self.assertTrue(pixmap.save(str(artifacts / (name+".png"))))


if __name__ == "__main__":
    unittest.main()
