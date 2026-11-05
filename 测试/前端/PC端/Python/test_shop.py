"""覆盖商城恢复、模拟交易、主题语言与商品详情。"""
import copy
import os
from pathlib import Path
import tempfile
import unittest

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
from PySide6.QtWidgets import QApplication, QLabel, QPushButton
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

    def tearDown(self):
        self.temp.cleanup()

    def test_local_sample_payment_idempotent_then_service_and_review(self):
        self.repo.login("customer", "")
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
        self.repo.login("customer", "")
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

    def test_warm_themes_detail_and_empty_reload(self):
        window = ShopWindow(self.settings, self.repo)
        window.timer.stop()
        window.theme.setCurrentIndex(window.theme.findData("light"))
        self.assertEqual(window.colors["bg"], "#fbf5eb")
        window.theme.setCurrentIndex(window.theme.findData("dark"))
        self.assertEqual(window.colors["bg"], "#211c18")
        window.theme.setCurrentIndex(window.theme.findData("system"))
        window.detail(self.repo.products[0])
        self.assertTrue(any(x.text() == "论文提纲" for x in window.area.findChildren(QLabel)))
        self.assertTrue(any(x.text() == window.t("buy") for x in window.area.findChildren(QPushButton)))
        window.page = "orders"
        window.product = None
        window.render()
        self.assertTrue(any(x.text() == window.t("reload") for x in window.area.findChildren(QPushButton)))
        window.close()
        window.deleteLater()
        self.app.processEvents()


if __name__ == "__main__":
    unittest.main()
