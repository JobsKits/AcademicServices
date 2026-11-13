"""覆盖商城恢复、模拟交易、主题语言与商品详情。"""
import copy
import os
from pathlib import Path
import tempfile
import unittest
import time
from unittest.mock import patch

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
from PySide6.QtWidgets import QApplication, QLabel, QPushButton, QTextEdit, QTabWidget
from PySide6.QtCore import QTimer, Qt, QPoint
from PySide6.QtTest import QTest
from zhixu.repository import ApiError, OfflineError, UnknownWrite
from zhixu.settings import Settings
from zhixu.shop_repository import ShopRepository, demo_products
from zhixu.shop import ShopWindow, STRINGS, LANGUAGES


class Client:
    def __init__(self):
        self.offline = True
        self.token = ""
        self.base = "http://127.0.0.1:8080/api/v1"
        self.calls = []

    def request(self, method, path, body=None, key=None):
        self.calls.append((method, path, copy.deepcopy(body), key))
        if self.offline:
            raise OfflineError("offline")
        if path == "/shop-config":
            return {"demo_mode": False, "payment_mode": "mock"}
        if path == "/banners":
            return {"banners": []}
        if path == "/products":
            return {"products": demo_products()}
        if path == "/shop-orders" and method == "GET":
            return {"orders": []}
        if path == "/auth/login":
            return {"user": {"id": "customer", "role": "customer"}, "token": "sample"}
        raise ApiError("Forbidden", 403)


class ShopTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.app = QApplication.instance() or QApplication([])

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.settings = Settings(self.temp.name)
        self.client = Client()
        self.repo = ShopRepository(self.settings, self.client)
        self.repo.demo_mode = True

    def tearDown(self):
        self.temp.cleanup()

    def test_email_registration_profile_and_password_reset(self):
        email = "reader@example.test"
        code = self.repo.request_email_code(email, "register")["demo_code"]
        with self.assertRaises(ApiError):
            self.repo.request_email_code(email, "register")
        self.repo.register(email, code, "Reader", "sample-pass", "sample-pass")
        self.assertEqual(self.repo.user["username"], "Reader")
        self.assertNotIn("hash", self.repo.user)
        self.assertNotIn((email, "register"), self.repo.demo_codes)
        self.repo.update_profile("ReaderNew")
        self.repo.logout()
        self.repo.login("readernew", "sample-pass")
        reset = self.repo.request_email_code(email, "reset_password")["demo_code"]
        self.repo.reset_password(email, reset, "changed-pass", "changed-pass")
        self.assertIsNone(self.repo.user)
        with self.assertRaises(ApiError):
            self.repo.login(email, "sample-pass")
        self.repo.login(email, "changed-pass")
        self.assertEqual(self.repo.user["username"], "ReaderNew")

    def test_formal_outage_does_not_create_local_auth(self):
        self.repo.demo_mode = False
        for operation in (lambda: self.repo.login("customer", "demo-customer"), lambda: self.repo.request_email_code("a@example.test", "register")):
            with self.assertRaises(ApiError):
                operation()
        self.assertIsNone(self.repo.user)
        self.assertEqual(self.repo.demo_accounts, {})

    def test_guest_header_auth_door_and_formal_settings(self):
        self.repo.demo_mode = False
        window = ShopWindow(self.settings, self.repo)
        window.timer.stop()
        window.initial_refresh.stop()
        self.assertIn(window.t("register"), window.account_button.text())
        self.assertFalse(window.reload_button.isVisibleTo(window.centralWidget()))
        self.assertFalse(window.orders_tab.isVisibleTo(window.centralWidget()))
        errors = []
        def inspect():
            dialog = self.app.activeModalWidget()
            try:
                tabs = dialog.findChildren(QTabWidget)[0]
                self.assertEqual([tabs.tabText(i) for i in range(tabs.count())], [window.t(k) for k in ("login", "register", "forgotPassword")])
            except Exception as error:
                errors.append(error)
            dialog.reject()
        QTimer.singleShot(0, inspect)
        window.account()
        self.assertEqual(errors, [])
        window.page = "settings"
        window.render()
        self.assertFalse(hasattr(window, "address_input"))
        window.close()
        window.deleteLater()

    def test_local_sample_payment_idempotent_then_service_and_review(self):
        self.repo.login("customer", "demo-customer")
        product = self.repo.products[0]
        order = self.repo.buy(product)
        duplicate = self.repo.buy(product)
        self.assertEqual(order["id"], duplicate["id"])
        paid = self.repo.action(order, "pay", channel="alipay")
        self.assertEqual(paid["status"], "pending_completion")
        self.assertEqual(paid["payment"]["mode"], "mock")
        with self.assertRaises(ApiError):
            self.repo.action(paid, "accept")
        self.repo.demo_orders[0]["fulfillment_status"] = "delivered"
        accepted = self.repo.action(paid, "accept")
        self.assertEqual(accepted["status"], "pending_review")
        reviewed = self.repo.action(accepted, "review", rating=5, text="Helpful")
        self.assertEqual(reviewed["status"], "completed")

    def test_offline_samples_are_replaced_on_successful_refresh(self):
        self.repo.login("customer", "demo-customer")
        self.repo.buy(self.repo.products[0])
        self.assertTrue(self.repo.orders)
        self.client.offline = False
        self.repo.refresh()
        self.assertEqual(self.repo.source, "live")
        self.assertEqual(self.repo.orders, [])
        self.assertTrue(any(call[1] == "/products" for call in self.client.calls))

    def test_real_order_timeout_never_becomes_fake_success(self):
        self.repo.user = {"id": "customer", "role": "customer"}
        real = {"id": "real-order", "version": 1}
        with self.assertRaises(ApiError):
            self.repo.action(real, "pay", channel="wechat")
        self.assertEqual(self.repo.demo_orders, [])
        self.assertEqual(len(self.repo.pending), 1)

    def test_live_create_timeout_blocks_other_writes_and_preserves_original_key(self):
        self.client.offline = False
        self.repo.login("customer", "password")
        self.client.offline = True
        with self.assertRaises(UnknownWrite):
            self.repo.buy(self.repo.products[0])
        pending = copy.deepcopy(self.repo.pending_request)
        self.assertEqual(self.repo.demo_orders, [])
        with self.assertRaises(UnknownWrite):
            self.repo.buy(self.repo.products[1])
        with self.assertRaises(UnknownWrite):
            self.repo.retry()
        self.assertEqual(self.repo.pending_request["key"], pending["key"])
        self.assertEqual(self.repo.pending_request["body"], pending["body"])

    def test_rejected_write_does_not_fall_back(self):
        self.client.offline = False
        self.repo.login("customer", "password")
        with self.assertRaises(ApiError):
            self.repo.buy(self.repo.products[0])
        self.assertEqual(self.repo.demo_orders, [])

    def test_ten_languages_complete_and_persisted(self):
        self.assertEqual(set(LANGUAGES), set(STRINGS))
        keys = set(STRINGS["zh"])
        for locale, translations in STRINGS.items():
            self.assertEqual(set(translations), keys, locale)
            self.assertTrue(all(isinstance(x, str) and x for x in translations.values()))
        self.settings.save(language="bo")
        self.assertEqual(Settings(self.temp.name).values["language"], "bo")

    def test_customer_requirements_edit_preserves_price_and_locks_after_acceptance(self):
        self.repo.login("customer", "demo-customer")
        order = self.repo.buy(self.repo.products[0], requirements="Initial")
        updated = self.repo.action(order, "edit", requirements="Revised", contact="Customer", delivery_requirements="PDF")
        self.assertEqual(updated["requirements"], "Revised")
        self.assertEqual(updated["amount_minor"], order["amount_minor"])
        self.repo.demo_orders[0]["accepted_at"] = "2026-11-05T00:00:00Z"
        self.repo.demo_orders[0]["fulfillment_status"] = "in_progress"
        with self.assertRaises(ApiError):
            self.repo.action(updated, "edit", requirements="Locked")

    def test_current_profile_has_four_order_shortcuts_and_settings_theme(self):
        self.repo.login("customer", "demo-customer")
        window = ShopWindow(self.settings, self.repo)
        window.timer.stop()
        window.page = "profile"
        window.render()
        buttons = [b.text() for b in window.area.findChildren(QPushButton)]
        for status in ("pending_payment", "pending_completion", "completed", "pending_review"):
            self.assertTrue(any(window.t(status) in value for value in buttons))
        window.page = "settings"
        window.render()
        self.assertTrue(window.theme.isVisibleTo(window.centralWidget()))
        self.assertTrue(window.language.isVisibleTo(window.centralWidget()))
        window.page = "products"
        window.render()
        self.assertEqual(window.category_pager.count(), 3)
        self.assertFalse(window.theme.isVisibleTo(window.centralWidget()))
        window.close()
        window.deleteLater()
        self.app.processEvents()

    def test_carousel_local_fallback_is_not_empty_and_links_are_web_only(self):
        from zhixu.shop_widgets import BannerCarousel, valid_web_link
        from zhixu.shop import ASSETS
        banner = BannerCarousel([], ASSETS, self.client.base)
        self.assertEqual(len(banner.banners), 3)
        self.assertFalse(banner.source.isNull())
        self.assertTrue(valid_web_link("https://example.com/course"))
        self.assertFalse(valid_web_link("javascript:alert(1)"))
        self.assertFalse(valid_web_link("https://user:pass@example.com"))
        banner.advance()
        self.assertEqual(banner.index, 1)
        banner.close()
        banner.deleteLater()

    def test_demo_configuration_exposes_only_explicit_current_credentials(self):
        self.client.offline = False
        original = self.client.request
        def request(method, path, body=None, key=None):
            if path == "/shop-config":
                return {"demo_mode": True, "demo_credentials": [{"role": "customer", "account": "customer", "password": "test-only"}, {"role": "admin", "account": "admin", "password": "other-test"}]}
            return original(method, path, body, key)
        self.client.request = request
        self.repo.refresh()
        self.assertEqual(len(self.repo.demo_credentials), 2)
        self.client.request = original
        self.repo.refresh()
        self.assertEqual(self.repo.demo_credentials, [])
        self.assertFalse(self.repo.demo_mode)

    def test_cancelled_sample_locks_editing(self):
        self.repo.login("customer", "demo-customer")
        order = self.repo.buy(self.repo.products[0])
        cancelled = self.repo.action(order, "cancel")
        self.assertFalse(cancelled["editable"])

    def test_closed_window_stops_initial_refresh_and_preserves_settings_draft(self):
        window = ShopWindow(self.settings, self.repo)
        window.timer.stop()
        window.page = "settings"
        window.render()
        window.address_input.setText("https://example.com/api/v1")
        window.timeout_input.setValue(4500)
        window.render()
        self.assertEqual(window.address_input.text(), "https://example.com/api/v1")
        self.assertEqual(window.timeout_input.value(), 4500)
        window.close()
        self.assertFalse(window.initial_refresh.isActive())
        self.assertTrue(window.closed)
        window.refresh()
        self.assertFalse(window.busy)
        window.deleteLater()
        self.app.processEvents()

    def test_single_banner_static_and_manual_pagination_has_no_playback_controls(self):
        from zhixu.shop_widgets import BannerCarousel
        from zhixu.shop import ASSETS
        banner = BannerCarousel([{"id": "one", "title": "One", "image": "", "target_url": ""}], ASSETS, self.client.base)
        self.assertFalse(banner.timer.isActive())
        self.assertFalse(banner.controls.isVisibleTo(banner))
        multiple = BannerCarousel([], ASSETS, self.client.base)
        multiple.manual_step(1)
        self.assertFalse(multiple.paused)
        self.assertEqual([item.text() for item in multiple.indicators], ["○", "●", "○"])
        self.assertEqual([item.isChecked() for item in multiple.indicators], [False, True, False])
        self.assertFalse(hasattr(multiple, "pause_button"))
        self.assertNotIn("/", multiple.title.text())
        multiple.indicators[2].click()
        self.assertEqual(multiple.index, 2)
        multiple.toggle_pause()
        self.assertTrue(multiple.paused)
        multiple.toggle_pause()
        multiple.focus_changed(None, multiple)
        multiple.focus_changed(multiple, None)
        self.assertFalse(multiple.paused)
        multiple.hide()
        self.assertFalse(multiple.timer.isActive())
        banner.deleteLater()
        multiple.deleteLater()

    def test_guest_private_navigation_opens_auth_and_cancel_stays_home(self):
        window = ShopWindow(self.settings, self.repo)
        window.timer.stop()
        window.initial_refresh.stop()
        for destination in ("profile", "orders"):
            observed = []
            def cancel():
                dialog = self.app.activeModalWidget()
                observed.append(dialog is not None)
                if dialog:
                    dialog.reject()
            QTimer.singleShot(0, cancel)
            window.show_page(destination)
            self.assertEqual(observed, [True])
            self.assertEqual(window.page, "products")
        window.page = "settings"
        window.render()
        self.assertFalse(any(b.text() in (window.t("login"), window.t("switchAccount")) for b in window.area.findChildren(QPushButton)))
        window.close()
        window.deleteLater()

    def test_background_read_does_not_disable_guest_content_or_primary_text(self):
        window = ShopWindow(self.settings, self.repo)
        window.timer.stop()
        window.initial_refresh.stop()
        def slow_read():
            time.sleep(.12)
            return self.repo.snapshot()
        window.run(slow_read, background=True)
        self.assertFalse(window.busy)
        self.assertTrue(window.reading)
        self.assertTrue(window.area.isEnabled())
        self.assertTrue(window.account_button.isEnabled())
        for theme in ("light", "dark"):
            self.settings.save(theme=theme)
            window.apply_theme()
            for enabled in (True, False):
                window.account_button.setEnabled(enabled)
                window.account_button.ensurePolished()
                self.assertEqual(window.account_button.palette().buttonText().color().name(), window.colors["on"])
        QTest.qWait(180)
        window.close()
        window.deleteLater()

    def test_carousel_elapsed_timer_and_mouse_drag_change_slide(self):
        from zhixu.shop_widgets import BannerCarousel
        from zhixu.shop import ASSETS
        with patch.object(QApplication, "applicationState", return_value=Qt.ApplicationState.ApplicationActive):
            banner = BannerCarousel([], ASSETS, self.client.base, interval_ms=1500)
            banner.resize(800, 300)
            banner.show()
            QTest.qWait(60)
            self.assertTrue(banner.timer.isActive())
            start = banner.index
            QTest.qWait(1580)
            self.assertNotEqual(banner.index, start)
            before = banner.index
            QTest.mousePress(banner.picture, Qt.MouseButton.LeftButton, pos=QPoint(500, 100))
            QTest.mouseMove(banner.picture, QPoint(400, 101), 20)
            QTest.mouseMove(banner.picture, QPoint(300, 101), 20)
            QTest.mouseRelease(banner.picture, Qt.MouseButton.LeftButton, pos=QPoint(250, 101))
            self.assertEqual(banner.index, (before + 1) % 3)
            self.assertTrue(banner.timer.isActive())
            banner.close()
            banner.deleteLater()

    def test_settings_entries_use_icons_with_localized_names(self):
        window = ShopWindow(self.settings, self.repo)
        window.timer.stop()
        window.initial_refresh.stop()
        window.page = "profile"
        window.render()
        entries = [item for item in window.findChildren(QPushButton) if item.property("settingsEntry")]
        self.assertEqual(len(entries), 1)
        for item in entries:
            self.assertFalse(item.text())
            self.assertFalse(item.icon().isNull())
            self.assertEqual(item.accessibleName(), window.t("settings"))
        entries[0].click()
        self.assertEqual(window.page, "settings")
        window.close()
        window.deleteLater()
        self.app.processEvents()

    def test_live_refresh_outage_retains_private_records_then_recovers(self):
        self.repo.login("customer", "demo-customer")
        order = self.repo.buy(self.repo.products[0])
        self.repo.live_session = True
        self.repo.source = "live"
        retained = self.repo.refresh()
        self.assertTrue(retained["stale"])
        self.assertEqual(retained["source"], "live")
        self.assertEqual(retained["orders"][0]["id"], order["id"])
        self.client.offline = False
        recovered = self.repo.refresh()
        self.assertFalse(recovered["stale"])
        self.assertEqual(recovered["orders"], [])

    def test_resource_rejection_is_not_an_outage_or_a_forced_logout(self):
        self.repo.login("customer", "demo-customer")
        user = copy.deepcopy(self.repo.user)
        for status in (403, 404):
            def denied(*args, **kwargs):
                raise ApiError("Resource unavailable", status)
            self.client.request = denied
            with self.assertRaises(ApiError) as context:
                self.repo._request("POST", "/shop-orders/missing/actions", {"action": "edit"})
            self.assertNotIsInstance(context.exception, OfflineError)
            self.assertEqual(self.repo.user, user)

    def test_explicit_banner_closure_survives_outage(self):
        from zhixu.shop_widgets import BannerCarousel
        self.client.offline = False
        self.repo.refresh()
        self.assertTrue(self.repo.banners_loaded)
        self.assertEqual(self.repo.banners, [])
        self.client.offline = True
        self.repo.refresh()
        self.assertTrue(self.repo.banners_loaded)
        window = ShopWindow(self.settings, self.repo)
        window.initial_refresh.stop()
        window.timer.stop()
        self.assertEqual(window.area.findChildren(BannerCarousel), [])
        window.close()
        window.deleteLater()
        self.app.processEvents()

    def test_rejected_purchase_preserves_form_and_allows_explicit_retry(self):
        self.repo.login("customer", "demo-customer")
        window = ShopWindow(self.settings, self.repo)
        window.initial_refresh.stop()
        window.timer.stop()
        original_buy = self.repo.buy
        attempts = []
        errors = []
        def buy(product, **details):
            attempts.append(copy.deepcopy(details))
            if len(attempts) == 1:
                raise ApiError("Please correct the request", 409)
            return original_buy(product, **details)
        self.repo.buy = buy
        def operate():
            dialog = self.app.activeModalWidget()
            try:
                fields = dialog.findChildren(QTextEdit)
                fields[0].setPlainText("Keep this requirement")
                submit = next(b for b in dialog.findChildren(QPushButton) if b.text() == window.t("buy"))
                submit.click()
                deadline = time.monotonic() + 3
                while window.busy and time.monotonic() < deadline:
                    QTest.qWait(10)
                self.assertFalse(window.busy)
                self.assertTrue(dialog.isVisible())
                self.assertEqual(fields[0].toPlainText(), "Keep this requirement")
                label = next(l for l in dialog.findChildren(QLabel) if l.accessibleName() == "form-error")
                self.assertIn("correct", label.text())
                self.assertTrue(label.isVisible())
                submit.click()
            except Exception as error:
                errors.append(error)
                dialog.submitting = False
                dialog.reject()
        QTimer.singleShot(0, operate)
        window.buy(self.repo.products[0])
        self.assertEqual(errors, [])
        self.assertEqual(len(attempts), 2)
        self.assertEqual(attempts[0], attempts[1])
        self.assertEqual(self.repo.orders[0]["requirements"], "Keep this requirement")
        self.assertEqual(window.page, "orders")
        window.close()
        window.deleteLater()
        self.app.processEvents()

    def test_detail_return_restores_catalogue_scroll(self):
        window = ShopWindow(self.settings, self.repo)
        window.initial_refresh.stop()
        window.timer.stop()
        window.show()
        QTest.qWait(80)
        scrollbar = window.area.verticalScrollBar()
        self.assertGreater(scrollbar.maximum(), 80)
        scrollbar.setValue(80)
        window.detail(self.repo.products[0])
        QTest.qWait(40)
        window.show_page("products")
        QTest.qWait(120)
        self.assertEqual(window.area.verticalScrollBar().value(), 80)
        window.close()
        window.deleteLater()
        self.app.processEvents()

    def test_packaged_fonts_cover_tibetan_cjk_and_korean_without_network(self):
        from PySide6.QtGui import QFont, QRawFont
        from zhixu.shop import load_shop_fonts
        load_shop_fonts()
        for family, character in (("Noto Serif Tibetan", "བ"), ("Noto Sans CJK SC", "学"), ("Noto Sans CJK SC", "한")):
            font = QRawFont.fromFont(QFont(family))
            self.assertTrue(font.isValid(), family)
            self.assertTrue(font.supportsCharacter(ord(character)), family)

    def test_warm_themes_detail_and_empty_reload(self):
        window = ShopWindow(self.settings, self.repo)
        window.timer.stop()
        window.theme.setCurrentIndex(window.theme.findData("light"))
        self.assertEqual(window.colors["bg"], "#fbf7f0")
        window.theme.setCurrentIndex(window.theme.findData("dark"))
        self.assertEqual(window.colors["bg"], "#191612")
        window.theme.setCurrentIndex(window.theme.findData("system"))
        window.detail(self.repo.products[0])
        self.assertTrue(any(x.text() == "论文提纲" for x in window.area.findChildren(QLabel)))
        self.assertTrue(any(x.text() == window.t("buy") for x in window.area.findChildren(QPushButton)))
        self.repo.login("customer", "demo-customer")
        window.state = self.repo.snapshot()
        window.page = "orders"
        window.product = None
        window.render()
        self.assertTrue(any(x.text() == window.t("reload") for x in window.area.findChildren(QPushButton)))
        window.close()
        window.deleteLater()
        self.app.processEvents()


if __name__ == "__main__":
    unittest.main()
