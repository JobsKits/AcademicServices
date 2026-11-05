"""Jobs 桌面商城：浏览、下单、模拟支付、确认交付与评价。"""
import base64
import json
from pathlib import Path
from urllib.parse import urljoin, urlsplit

from PySide6.QtCore import QTimer, Qt, QUrl
from PySide6.QtGui import QColor, QIcon, QPalette, QPixmap
from PySide6.QtNetwork import QNetworkAccessManager, QNetworkRequest
from PySide6.QtWidgets import (
    QApplication, QComboBox, QDialog, QDialogButtonBox, QFormLayout,
    QFrame, QHBoxLayout, QLabel, QLineEdit, QMessageBox, QPushButton,
    QSpinBox, QTextEdit, QVBoxLayout, QWidget, QMainWindow,
)
from .app import Task, heading, paragraph, button, clear, scroll_page, money
from .repository import HttpClient, api_url
from .settings import Settings
from .shop_repository import ShopRepository

ASSETS = Path(__file__).parent / "Assets"
STRINGS = json.loads((ASSETS / "shop_strings.json").read_text(encoding="utf-8"))
LANGUAGES = {"zh": "简体中文", "zh-Hant": "繁體中文", "bo": "བོད་ཡིག", "en": "English", "ja": "日本語", "fr": "Français", "es": "Español", "de": "Deutsch", "ru": "Русский", "ko": "한국어"}


class ShopWindow(QMainWindow):
    def __init__(self, settings=None, repository=None):
        super().__init__()
        from PySide6.QtCore import QThreadPool
        self.settings = settings or Settings()
        self.repo = repository or ShopRepository(self.settings)
        self.locale = self.settings.values.get("language", "zh")
        if self.locale not in STRINGS:
            self.locale = "zh"
        self.state = self.repo.snapshot()
        self.category = "all"
        self.status_filter = "all"
        self.page = "products"
        self.product = None
        self.busy = False
        self.generation = 0
        self.tasks = set()
        self.pool = QThreadPool(self)
        self.pool.setMaxThreadCount(1)
        self.network = QNetworkAccessManager(self)
        self.resize(1180, 830)
        self.setMinimumSize(760, 560)
        self.setWindowIcon(QIcon(str(ASSETS / "brand.svg")))
        self.build()
        self.apply_theme()
        QApplication.styleHints().colorSchemeChanged.connect(self.apply_theme)
        self.timer = QTimer(self)
        self.timer.timeout.connect(self.refresh)
        self.timer.start(30_000)
        QTimer.singleShot(100, self.refresh)

    def t(self, key):
        return STRINGS[self.locale].get(key, key)

    def build(self):
        self.setWindowTitle("知序 · " + self.t("shop"))
        root = QWidget()
        layout = QVBoxLayout(root)
        layout.setContentsMargins(26, 22, 26, 16)
        row = QHBoxLayout()
        row.addWidget(heading("知序 · " + self.t("shop"), 25))
        row.addStretch()
        self.language = QComboBox()
        for code, name in LANGUAGES.items():
            self.language.addItem(name, code)
        self.language.setCurrentIndex(self.language.findData(self.locale))
        self.language.setAccessibleName(self.t("language"))
        self.language.currentIndexChanged.connect(self.change_language)
        row.addWidget(self.language)
        self.theme = QComboBox()
        for code in ("system", "light", "dark"):
            self.theme.addItem(self.t(code), code)
        self.theme.setCurrentIndex(max(0, self.theme.findData(self.settings.values["theme"])))
        self.theme.setAccessibleName(self.t("theme"))
        self.theme.currentIndexChanged.connect(self.change_theme)
        row.addWidget(self.theme)
        self.account_button = button(self.t("logout" if self.state["user"] else "login"), self.account)
        row.addWidget(self.account_button)
        layout.addLayout(row)
        nav = QHBoxLayout()
        for key in ("products", "orders", "settings"):
            nav.addWidget(button(self.t(key), lambda checked=False, k=key: self.show_page(k)))
        nav.addStretch()
        self.reload_button = button(self.t("reload"), self.refresh)
        nav.addWidget(self.reload_button)
        layout.addLayout(nav)
        self.notice = paragraph("")
        layout.addWidget(self.notice)
        self.area, self.content = scroll_page()
        layout.addWidget(self.area, 1)
        self.setCentralWidget(root)
        self.render()

    def change_language(self):
        self.locale = self.language.currentData()
        self.settings.save(language=self.locale)
        self.build()

    def change_theme(self):
        self.settings.save(theme=self.theme.currentData())
        self.apply_theme()

    def apply_theme(self, *_):
        theme = self.settings.values["theme"]
        dark = theme == "dark" or (theme == "system" and QApplication.styleHints().colorScheme() == Qt.ColorScheme.Dark)
        self.colors = ({"bg": "#211c18", "card": "#2f2720", "text": "#f5e9dc", "sub": "#d3beaa", "line": "#806c59", "brand": "#e4b187", "on": "#2d1c0e"} if dark else {"bg": "#fbf5eb", "card": "#fffdf8", "text": "#392b22", "sub": "#715d4b", "line": "#c4ae96", "brand": "#805334", "on": "#ffffff"})
        c = self.colors
        palette = QPalette()
        for role, key in ((QPalette.ColorRole.Window, "bg"), (QPalette.ColorRole.WindowText, "text"), (QPalette.ColorRole.Base, "card"), (QPalette.ColorRole.Text, "text"), (QPalette.ColorRole.Button, "card"), (QPalette.ColorRole.ButtonText, "text"), (QPalette.ColorRole.ToolTipBase, "card"), (QPalette.ColorRole.ToolTipText, "text"), (QPalette.ColorRole.Highlight, "brand"), (QPalette.ColorRole.HighlightedText, "on"), (QPalette.ColorRole.PlaceholderText, "sub")):
            palette.setColor(role, QColor(c[key]))
        QApplication.instance().setPalette(palette)
        QApplication.instance().setStyleSheet(f"""
            QWidget {{color:{c['text']};font-size:14px;}}
            QMainWindow,QScrollArea,QScrollArea>QWidget>QWidget {{background:{c['bg']};}}
            QFrame[card="true"] {{background:{c['card']};border:1px solid {c['line']};border-radius:16px;}}
            QPushButton {{background:{c['card']};border:1px solid {c['line']};border-radius:9px;padding:9px 15px;}}
            QPushButton[primary="true"] {{background:{c['brand']};color:{c['on']};}}
            QPushButton:disabled {{color:{c['sub']};}}
            QLineEdit,QTextEdit,QSpinBox,QComboBox {{background:{c['card']};border:1px solid {c['line']};padding:7px;border-radius:6px;}}
            QComboBox QAbstractItemView {{background:{c['card']};color:{c['text']};selection-background-color:{c['brand']};selection-color:{c['on']};}}
            QDialog,QMessageBox {{background:{c['bg']};}}
        """)

    def show_page(self, page):
        self.page = page
        self.product = None
        self.render()
        if page in ("products", "orders"):
            self.refresh()

    def render(self):
        clear(self.content)
        self.notice.setText(self.t("online" if self.state["source"] == "live" else "offline"))
        self.account_button.setText(self.t("logout" if self.state["user"] else "login"))
        if self.repo.pending_request:
            pending = self.card()
            pending.addWidget(paragraph(self.t("pendingWrite")))
            pending.addWidget(button(self.t("reconcile"), lambda: self.run(self.repo.reconcile)))
            pending.addWidget(button(self.t("retry"), lambda: self.run(self.repo.retry)))
        if self.page == "settings":
            self.render_settings()
        elif self.page == "orders":
            self.render_orders()
        elif self.product:
            self.render_detail(self.product)
        else:
            self.render_products()
        self.content.addStretch()

    def card(self):
        frame = QFrame()
        frame.setProperty("card", True)
        box = QVBoxLayout(frame)
        box.setContentsMargins(22, 18, 22, 18)
        self.content.addWidget(frame)
        return box

    def empty(self, key):
        box = self.card()
        box.addWidget(heading(self.t(key)))
        box.addWidget(paragraph(self.t("emptyHint")))
        box.addWidget(button(self.t("reload"), self.refresh))

    def render_products(self):
        self.content.addWidget(heading(self.t("hero"), 34))
        self.content.addWidget(paragraph(self.t("intro")))
        row = QHBoxLayout()
        for code in ("all", "graduation", "journal", "editing"):
            item = button(self.t(code), lambda checked=False, k=code: self.select_category(k))
            item.setCheckable(True)
            item.setChecked(code == self.category)
            row.addWidget(item)
        self.content.addLayout(row)
        products = [p for p in self.state["products"] if p["active"] and (self.category == "all" or p["category_id"] == self.category)]
        if not products:
            self.empty("emptyProducts")
        for product in products:
            box = self.card()
            line = QHBoxLayout()
            line.addWidget(self.picture(product), 0)
            text = QVBoxLayout()
            text.addWidget(heading(product["name"], 22))
            text.addWidget(paragraph(product.get("summary", "")))
            text.addWidget(paragraph(self.t(product.get("kind", "service")) + " · " + money(product["price_minor"])))
            if product.get("is_demo"):
                text.addWidget(paragraph(self.t("demoGoods")))
            line.addLayout(text, 1)
            box.addLayout(line)
            if not product["in_stock"]:
                box.addWidget(paragraph(self.t("outOfStock")))
            box.addWidget(button(self.t("details"), lambda checked=False, p=product: self.detail(p)))

    def select_category(self, category):
        self.category = category
        self.render()

    def picture(self, product):
        label = QLabel()
        label.setFixedSize(96, 96)
        label.setPixmap(QIcon(str(ASSETS / "brand.svg")).pixmap(90, 90))
        value = product.get("image", "")
        if value.startswith("data:image/"):
            try:
                pixmap = QPixmap()
                pixmap.loadFromData(base64.b64decode(value.split(",", 1)[1], validate=True))
                if not pixmap.isNull():
                    label.setPixmap(pixmap.scaled(96, 96, Qt.AspectRatioMode.KeepAspectRatio, Qt.TransformationMode.SmoothTransformation))
            except (ValueError, IndexError):
                pass
        elif value:
            address = urljoin(self.repo.client.base + "/", value)
            parsed = urlsplit(address)
            if parsed.scheme == "https" or (parsed.scheme == "http" and parsed.hostname in ("localhost", "127.0.0.1", "::1")):
                request = QNetworkRequest(QUrl(address))
                request.setTransferTimeout(2500)
                reply = self.network.get(request)
                def finish():
                    try:
                        if reply.bytesAvailable() <= 3 * 1024 * 1024:
                            pixmap = QPixmap()
                            pixmap.loadFromData(reply.readAll())
                            if not pixmap.isNull():
                                label.setPixmap(pixmap.scaled(96, 96, Qt.AspectRatioMode.KeepAspectRatio, Qt.TransformationMode.SmoothTransformation))
                    except RuntimeError:
                        pass
                    reply.deleteLater()
                reply.finished.connect(finish)
        return label

    def detail(self, product):
        self.product = product
        self.render()

    def render_detail(self, product):
        self.content.addWidget(button(self.t("back"), lambda: self.show_page("products")))
        box = self.card()
        box.addWidget(self.picture(product))
        box.addWidget(heading(product["name"], 30))
        box.addWidget(heading(money(product["price_minor"]), 24))
        if product.get("is_demo"):
            box.addWidget(paragraph(self.t("demoGoods")))
        box.addWidget(paragraph(product.get("description", "")))
        for section in product.get("sections") or []:
            box.addWidget(heading(section.get("title", "")))
            box.addWidget(paragraph(section.get("body", "")))
        buy = button(self.t("buy" if product["active"] and product["in_stock"] else "outOfStock"), lambda: self.buy(product), True)
        buy.setEnabled(product["active"] and product["in_stock"])
        box.addWidget(buy)

    def buy(self, product):
        if not self.state["user"]:
            self.account()
            return
        def action():
            self.repo.buy(product)
            return self.repo.snapshot()
        self.page = "orders"
        self.product = None
        self.run(action)

    def render_orders(self):
        self.content.addWidget(heading(self.t("orders"), 30))
        self.filter = QComboBox()
        for code in ("all", "pending_payment", "pending_completion", "pending_review", "completed", "cancelled"):
            self.filter.addItem(self.t(code), code)
        self.filter.setCurrentIndex(self.filter.findData(self.status_filter))
        self.filter.currentIndexChanged.connect(self.change_filter)
        self.content.addWidget(self.filter)
        orders = [o for o in self.state["orders"] if self.status_filter == "all" or o["status"] == self.status_filter]
        if not orders:
            self.empty("emptyOrders")
        for order in orders:
            box = self.card()
            box.addWidget(heading(order["product_snapshot"]["name"], 23))
            box.addWidget(paragraph(order["id"] + " · " + money(order["amount_minor"]) + " · " + self.t(order["status"])))
            if order.get("payment"):
                pay = order["payment"]
                box.addWidget(paragraph(self.t("mockRecord") + " · " + self.t(pay.get("channel", "wechat"))))
            if order["status"] == "pending_payment":
                box.addWidget(button(self.t("checkout"), lambda checked=False, o=order: self.checkout(o), True))
                box.addWidget(button(self.t("cancel"), lambda checked=False, o=order: self.order_action(o, "cancel")))
            elif order["status"] == "pending_completion":
                box.addWidget(paragraph(self.t(order["fulfillment_status"])))
                if order.get("delivery_text"):
                    box.addWidget(paragraph(order["delivery_text"]))
                if order["fulfillment_status"] == "delivered":
                    box.addWidget(button(self.t("accept"), lambda checked=False, o=order: self.order_action(o, "accept"), True))
            elif order["status"] == "pending_review":
                box.addWidget(button(self.t("review"), lambda checked=False, o=order: self.review(o), True))
            if order.get("review"):
                box.addWidget(paragraph(str(order["review"].get("rating", "")) + " / 5 · " + order["review"].get("text", "")))

    def change_filter(self):
        self.status_filter = self.filter.currentData()
        self.render()

    def checkout(self, order):
        dialog = QDialog(self)
        dialog.setWindowTitle(self.t("checkout"))
        box = QVBoxLayout(dialog)
        box.addWidget(heading(money(order["amount_minor"]), 28))
        box.addWidget(paragraph(self.t("mockHint")))
        channels = QComboBox()
        for code in ("alipay", "wechat"):
            channels.addItem(self.t(code), code)
        box.addWidget(channels)
        box.addWidget(button(self.t("confirmPay"), dialog.accept, True))
        box.addWidget(button(self.t("cancel"), dialog.reject))
        if dialog.exec() == QDialog.DialogCode.Accepted:
            self.order_action(order, "pay", channel=channels.currentData())

    def review(self, order):
        dialog = QDialog(self)
        dialog.setWindowTitle(self.t("review"))
        form = QFormLayout(dialog)
        rating = QSpinBox()
        rating.setRange(1, 5)
        rating.setValue(5)
        text = QTextEdit()
        form.addRow(self.t("rating"), rating)
        form.addRow(self.t("text"), text)
        form.addRow(button(self.t("save"), dialog.accept))
        form.addRow(button(self.t("cancel"), dialog.reject))
        if dialog.exec() == QDialog.DialogCode.Accepted and text.toPlainText().strip():
            self.order_action(order, "review", rating=rating.value(), text=text.toPlainText().strip())

    def order_action(self, order, action, **fields):
        def work():
            self.repo.action(order, action, **fields)
            return self.repo.snapshot()
        self.run(work)

    def account(self):
        if self.busy:
            return
        if self.state["user"]:
            self.repo.logout()
            self.state = self.repo.snapshot()
            self.render()
            return
        dialog = QDialog(self)
        dialog.setWindowTitle(self.t("login"))
        form = QFormLayout(dialog)
        account = QLineEdit("customer")
        password = QLineEdit()
        password.setEchoMode(QLineEdit.EchoMode.Password)
        form.addRow(self.t("account"), account)
        form.addRow(self.t("password"), password)
        form.addRow(paragraph(self.t("loginHint")))
        form.addRow(button(self.t("login"), dialog.accept, True))
        form.addRow(button(self.t("cancel"), dialog.reject))
        if dialog.exec() == QDialog.DialogCode.Accepted:
            self.run(lambda: self.repo.login(account.text(), password.text()))

    def render_settings(self):
        box = self.card()
        form = QFormLayout()
        address = QLineEdit(self.settings.values["api"])
        timeout = QSpinBox()
        timeout.setRange(500, 10000)
        timeout.setValue(int(self.settings.values["timeout"] * 1000))
        form.addRow(self.t("api"), address)
        form.addRow(self.t("timeout"), timeout)
        box.addLayout(form)
        def save():
            if self.busy:
                return
            try:
                endpoint = api_url(address.text())
            except Exception as error:
                QMessageBox.information(self, self.t("settings"), str(error))
                return
            self.generation += 1
            self.repo.logout()
            self.settings.save(api=endpoint, timeout=timeout.value() / 1000)
            self.repo = ShopRepository(self.settings)
            self.state = self.repo.snapshot()
            self.render()
            self.refresh()
        box.addWidget(button(self.t("save"), save, True))

    def refresh(self):
        self.run(self.repo.refresh)

    def run(self, function):
        if self.busy:
            return
        self.busy = True
        self.area.setEnabled(False)
        self.account_button.setEnabled(False)
        self.reload_button.setEnabled(False)
        task = Task(function, self.generation)
        self.tasks.add(task)
        def finish(value, error, generation):
            self.tasks.discard(task)
            self.busy = False
            self.area.setEnabled(True)
            self.account_button.setEnabled(True)
            self.reload_button.setEnabled(True)
            if generation != self.generation:
                return
            self.state = self.repo.snapshot() if error else value
            if self.product:
                self.product = next((p for p in self.state["products"] if p["id"] == self.product["id"] and p["active"]), None)
            self.render()
            if error:
                QMessageBox.information(self, self.t("shop"), str(error))
        task.signals.finished.connect(finish)
        self.pool.start(task)

    def closeEvent(self, event):
        self.generation += 1
        self.timer.stop()
        self.pool.waitForDone(12_000)
        event.accept()
