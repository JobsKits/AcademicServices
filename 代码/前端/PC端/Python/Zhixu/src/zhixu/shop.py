"""Jobs 桌面商城：浏览、下单、模拟支付、确认交付与评价。"""
import base64
import json
from pathlib import Path
from urllib.parse import urljoin, urlsplit

from PySide6.QtCore import QTimer, Qt, QUrl, QSize
from PySide6.QtGui import QColor, QIcon, QPalette, QPixmap, QFontDatabase
from PySide6.QtNetwork import QNetworkAccessManager, QNetworkRequest
from PySide6.QtWidgets import (
    QApplication, QComboBox, QDialog, QDialogButtonBox, QFormLayout,
    QFrame, QHBoxLayout, QLabel, QLineEdit, QMessageBox, QPushButton,
    QSpinBox, QTextEdit, QVBoxLayout, QWidget, QMainWindow, QStyle, QToolTip, QGridLayout, QTabWidget, QFileDialog, QBoxLayout, QSizePolicy,
)
from .app import Task, heading, paragraph, button, clear, scroll_page, money
from .repository import HttpClient, api_url
from .settings import Settings
from .shop_repository import ShopRepository
from .shop_widgets import BannerCarousel, CategoryPager, SettingsButton, SubmitDialog

ASSETS = Path(__file__).parent / "Assets"
STRINGS = json.loads((ASSETS / "shop_strings.json").read_text(encoding="utf-8"))
LANGUAGES = {"zh": "简体中文", "zh-Hant": "繁體中文", "bo": "བོད་ཡིག", "en": "English", "ja": "日本語", "fr": "Français", "es": "Español", "de": "Deutsch", "ru": "Русский", "ko": "한국어"}
_fonts_loaded = False


def load_shop_fonts():
    global _fonts_loaded
    if _fonts_loaded:
        return
    families = []
    for name in ("NotoSansCJKsc-Regular.otf", "NotoSerifTibetan.ttf"):
        font_id = QFontDatabase.addApplicationFont(str(ASSETS / "Fonts" / name))
        if font_id >= 0:
            families.extend(QFontDatabase.applicationFontFamilies(font_id))
    font = QApplication.font()
    font.setFamilies(list(dict.fromkeys(families + font.families())))
    QApplication.setFont(font)
    _fonts_loaded = True


class ShopWindow(QMainWindow):
    def __init__(self, settings=None, repository=None):
        super().__init__()
        load_shop_fonts()
        from PySide6.QtCore import QThreadPool
        self.settings = settings or Settings()
        self.repo = repository or ShopRepository(self.settings)
        self.locale = self.settings.values.get("language", "zh")
        if self.locale not in STRINGS:
            self.locale = "zh"
        self.state = self.repo.snapshot()
        self.category = "graduation"
        self.status_filter = "all"
        self.page = "products"
        self.product = None
        self.busy = False
        self.reading = False
        self.closed = False
        self.error_message = ""
        self.scroll_positions = {}
        self.current_context = None
        self.render_revision = 0
        self.scroll_restore_pending = False
        self.connection_draft = {"api": self.settings.values["api"], "timeout": self.settings.values["timeout"]}
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
        self.initial_refresh = QTimer(self)
        self.initial_refresh.setSingleShot(True)
        self.initial_refresh.timeout.connect(self.refresh)
        self.initial_refresh.start(100)

    def t(self, key):
        return STRINGS[self.locale].get(key, key)

    def build(self):
        self.setWindowTitle("知序 · " + self.t("shop"))
        root = QWidget()
        layout = QVBoxLayout(root)
        layout.setContentsMargins(28, 24, 28, 24)
        layout.setSpacing(16)
        row = QHBoxLayout()
        row.setSpacing(12)
        brand = QLabel()
        brand.setPixmap(QIcon(str(ASSETS / "brand.svg")).pixmap(36, 36))
        row.addWidget(brand)
        row.addWidget(heading("知序 · " + self.t("shop"), 24))
        row.addStretch()
        self.language = QComboBox()
        for code, name in LANGUAGES.items():
            self.language.addItem(name, code)
        self.language.setCurrentIndex(self.language.findData(self.locale))
        self.language.setAccessibleName(self.t("language"))
        self.language.currentIndexChanged.connect(self.change_language)
        self.theme = QComboBox()
        for code in ("system", "light", "dark"):
            self.theme.addItem(self.t(code), code)
        self.theme.setCurrentIndex(max(0, self.theme.findData(self.settings.values["theme"])))
        self.theme.setAccessibleName(self.t("theme"))
        self.theme.currentIndexChanged.connect(self.change_theme)
        self.account_button = button(self.t("logout" if self.state["user"] else "login"), self.account)
        self.account_button.setProperty("primary", True)
        row.addWidget(self.account_button)
        self.header_settings = self.settings_button()
        row.addWidget(self.header_settings)
        layout.addLayout(row)
        nav = QHBoxLayout()
        nav.setSpacing(8)
        self.nav_buttons = {}
        self.reload_button = button(self.t("reload"), self.refresh)
        self.reload_button.hide()
        for key, label, icon in (("products", "home", QStyle.StandardPixmap.SP_DirHomeIcon), ("orders", "myOrders", QStyle.StandardPixmap.SP_FileDialogDetailedView), ("profile", "mine", QStyle.StandardPixmap.SP_FileDialogInfoView)):
            item = button(self.t(label), lambda checked=False, k=key: self.show_page(k))
            item.setIcon(self.style().standardIcon(icon))
            item.setIconSize(QSize(22, 22))
            item.setProperty("navigation", True)
            item.setCheckable(True)
            self.nav_buttons[key] = item
            if key == "profile":
                self.profile_tab = item
            if key == "orders":
                self.orders_tab = item
            nav.addWidget(item)
        nav.addStretch()
        self.notice = paragraph("")
        self.notice.setProperty("muted", True)
        nav.addWidget(self.notice)
        layout.addLayout(nav)
        self.error_notice = paragraph("")
        self.error_notice.setAccessibleName("operation-error")
        self.error_notice.hide()
        layout.addWidget(self.error_notice)
        self.area, self.content = scroll_page()
        self.area.widget().setMaximumWidth(1120)
        self.area.setAlignment(Qt.AlignmentFlag.AlignHCenter | Qt.AlignmentFlag.AlignTop)
        self.content.setContentsMargins(4, 12, 4, 24)
        self.content.setSpacing(24)
        layout.addWidget(self.area, 1)
        self.setCentralWidget(root)
        self.render()

    def change_language(self):
        self.locale = self.language.currentData()
        self.settings.save(language=self.locale)
        self.build()

    def settings_button(self):
        return SettingsButton(self.t("settings"), lambda: self.show_page("settings"))

    def change_theme(self):
        self.settings.save(theme=self.theme.currentData())
        self.apply_theme()

    def apply_theme(self, *_):
        theme = self.settings.values["theme"]
        dark = theme == "dark" or (theme == "system" and QApplication.styleHints().colorScheme() == Qt.ColorScheme.Dark)
        self.colors = ({"bg": "#191612", "card": "#24201b", "text": "#f4ede4", "sub": "#c5b7a7", "line": "#574a3d", "brand": "#e3b88f", "on": "#2c1c10", "soft": "#382c22", "hover": "#302922"} if dark else {"bg": "#fbf7f0", "card": "#fffcf7", "text": "#352a24", "sub": "#6f5b4e", "line": "#d9cdbd", "brand": "#865338", "on": "#ffffff", "soft": "#f0e4d7", "hover": "#f5ece0"})
        c = self.colors
        palette = QPalette()
        for role, key in ((QPalette.ColorRole.Window, "bg"), (QPalette.ColorRole.WindowText, "text"), (QPalette.ColorRole.Base, "card"), (QPalette.ColorRole.Text, "text"), (QPalette.ColorRole.Button, "card"), (QPalette.ColorRole.ButtonText, "text"), (QPalette.ColorRole.ToolTipBase, "card"), (QPalette.ColorRole.ToolTipText, "text"), (QPalette.ColorRole.Highlight, "brand"), (QPalette.ColorRole.HighlightedText, "on"), (QPalette.ColorRole.PlaceholderText, "sub")):
            palette.setColor(role, QColor(c[key]))
        QApplication.instance().setPalette(palette)
        QApplication.instance().setStyleSheet(f"""
            QWidget {{color:{c['text']};font-size:15px;selection-background-color:{c['brand']};selection-color:{c['on']};}}
            QMainWindow,QScrollArea,QScrollArea>QWidget>QWidget {{background:{c['bg']};}}
            QFrame[card="true"] {{background:{c['card']};border:1px solid {c['line']};border-radius:16px;}}
            QLabel[muted="true"] {{color:{c['sub']};font-size:14px;}}
            QLabel#productPrice {{color:{c['brand']};font-size:20px;font-weight:650;}}
            QPushButton {{background:{c['card']};border:1px solid {c['line']};border-radius:10px;padding:10px 16px;min-height:22px;}}
            QPushButton:hover {{background:{c['hover']};border-color:{c['brand']};}}
            QPushButton:focus {{border:2px solid {c['brand']};}}
            QPushButton:pressed {{background:{c['soft']};}}
            QPushButton[navigation="true"] {{background:transparent;border-color:transparent;padding:10px 18px;}}
            QPushButton[navigation="true"]:checked {{background:{c['soft']};color:{c['brand']};font-weight:650;}}
            QPushButton[navigation="true"]:focus {{border-color:{c['brand']};}}
            QPushButton[primary="true"] {{background:{c['brand']};color:{c['on']};border-color:{c['brand']};}}
            QPushButton:disabled {{color:{c['sub']};}}
            QPushButton[primary="true"]:disabled {{background:{c['brand']};color:{c['on']};}}
            QLineEdit,QTextEdit,QSpinBox,QComboBox {{background:{c['card']};border:1px solid {c['line']};padding:10px 12px;border-radius:9px;}}
            QLineEdit:focus,QTextEdit:focus,QSpinBox:focus,QComboBox:focus {{border:2px solid {c['brand']};}}
            QComboBox QAbstractItemView {{background:{c['card']};color:{c['text']};selection-background-color:{c['brand']};selection-color:{c['on']};}}
            QTabWidget::pane {{border:0;background:transparent;}}
            QTabBar::tab {{background:transparent;color:{c['sub']};border:0;border-bottom:2px solid transparent;padding:12px 22px;margin-right:6px;}}
            QTabBar::tab:selected {{color:{c['brand']};border-bottom-color:{c['brand']};font-weight:650;}}
            QTabBar::tab:hover {{background:{c['soft']};}}
            QScrollBar:vertical {{background:transparent;width:8px;margin:0;}}
            QScrollBar::handle:vertical {{background:{c['line']};border-radius:4px;min-height:32px;}}
            QScrollBar::add-line:vertical,QScrollBar::sub-line:vertical {{height:0;}}
            QScrollBar::add-page:vertical,QScrollBar::sub-page:vertical {{background:transparent;}}
            QDialog,QMessageBox {{background:{c['bg']};}}
        """)

    def show_page(self, page):
        if page in ("orders", "profile") and not self.state["user"]:
            if self.account() != QDialog.DialogCode.Accepted or not self.state["user"]:
                self.page = "products"
                self.product = None
                self.render()
                return
        self.page = page
        self.product = None
        self.render()
        if page in ("products", "orders"):
            self.refresh()

    def render(self):
        if self.page in ("orders", "profile") and not self.state["user"]:
            self.page = "products"
            self.product = None
        if self.current_context is not None and not self.scroll_restore_pending:
            self.scroll_positions[self.current_context] = self.area.verticalScrollBar().value()
        self.current_context = (self.page, self.product["id"] if self.product else self.status_filter if self.page == "orders" else "")
        self.render_revision += 1
        self.scroll_restore_pending = True
        revision = self.render_revision
        self.language.setParent(self.centralWidget())
        self.language.hide()
        self.theme.setParent(self.centralWidget())
        self.theme.hide()
        clear(self.content)
        self.notice.setText(("Demo · " if self.state.get("demo_mode") else "") + self.t("online" if self.state["source"] == "live" else "offline"))
        self.error_notice.setText(self.error_message or (self.t("updateFailed") if self.state.get("stale") else ""))
        self.error_notice.setVisible(bool(self.error_notice.text()))
        self.account_button.setText(self.t("logout" if self.state["user"] else "login"))
        user = self.state["user"]
        name = user.get("username") or user.get("name") or user.get("account") if user else ""
        self.account_button.setText(name or self.t("login") + " / " + self.t("register"))
        self.account_button.clicked.disconnect()
        self.account_button.clicked.connect(lambda: self.show_page("profile") if self.state["user"] else self.account())
        self.header_settings.setVisible(not bool(user))
        self.orders_tab.setVisible(bool(user))
        for key, item in self.nav_buttons.items():
            item.setChecked(self.page == key or (key == "products" and bool(self.product)))
        self.profile_tab.setText(name or self.t("mine"))
        self.account_button.setIcon(self.avatar_icon(user) if user else QIcon())
        self.profile_tab.setIcon(self.avatar_icon(user) if user else QIcon(str(ASSETS / "brand.svg")))
        if self.repo.pending_request:
            pending = self.card()
            pending.addWidget(paragraph(self.t("pendingWrite")))
            pending.addWidget(button(self.t("reconcile"), lambda: self.run(self.repo.reconcile)))
            pending.addWidget(button(self.t("retry"), lambda: self.run(self.repo.retry)))
        if self.page == "settings":
            self.render_settings()
        elif self.page == "orders":
            self.render_orders()
        elif self.page == "profile":
            self.render_profile()
        elif self.product:
            self.render_detail(self.product)
        else:
            self.render_products()
        self.content.addStretch()
        position = self.scroll_positions.get(self.current_context, 0)
        def restore_position(attempt=0):
            if not self.closed and revision == self.render_revision:
                self.content.activate()
                self.area.widget().adjustSize()
                if position > self.area.verticalScrollBar().maximum() and attempt < 3:
                    QTimer.singleShot(0, lambda: restore_position(attempt + 1))
                    return
                self.area.verticalScrollBar().setValue(position)
                self.scroll_restore_pending = False
        QTimer.singleShot(0, restore_position)

    def card(self):
        frame = QFrame()
        frame.setProperty("card", True)
        box = QVBoxLayout(frame)
        box.setContentsMargins(24, 24, 24, 24)
        box.setSpacing(14)
        self.content.addWidget(frame)
        return box

    def empty(self, key):
        box = self.card()
        icon = QLabel()
        icon.setPixmap(self.style().standardIcon(QStyle.StandardPixmap.SP_FileDialogContentsView).pixmap(48, 48))
        box.addWidget(icon)
        box.addWidget(heading(self.t(key)))
        box.addWidget(paragraph(self.t("emptyHint")))
        box.addWidget(button(self.t("reload"), self.refresh))

    def render_products(self):
        self.product_grids = []
        hero = QWidget()
        self.hero_layout = QBoxLayout(QBoxLayout.Direction.LeftToRight, hero)
        self.hero_layout.setContentsMargins(0, 0, 0, 0)
        self.hero_layout.setSpacing(28)
        introduction = QWidget()
        introduction_layout = QVBoxLayout(introduction)
        self.hero_introduction_layout = introduction_layout
        introduction_layout.setContentsMargins(0, 24, 0, 24)
        introduction_layout.setSpacing(16)
        introduction_layout.addStretch()
        introduction_layout.addWidget(heading(self.t("hero"), 32))
        intro = paragraph(self.t("intro"))
        intro.setProperty("muted", True)
        introduction_layout.addWidget(intro)
        introduction_layout.addStretch()
        self.hero_layout.addWidget(introduction, 2)
        self.hero_banner = None
        if self.state.get("banners") or not self.state.get("banners_loaded"):
            self.hero_banner = BannerCarousel(self.state.get("banners", []), ASSETS, self.repo.client.base, self, t=self.t)
            self.hero_layout.addWidget(self.hero_banner, 5)
        self.content.addWidget(hero)
        pager = CategoryPager(self)
        self.category_pager = pager
        categories = ("graduation", "journal", "editing")
        for category in categories:
            page = QWidget()
            box = QVBoxLayout(page)
            box.setContentsMargins(0, 16, 0, 0)
            box.setSpacing(16)
            products = [p for p in self.state["products"] if p["active"] and p["category_id"] == category]
            if not products:
                box.addWidget(heading(self.t("emptyProducts")))
                box.addWidget(paragraph(self.t("emptyHint")))
                box.addWidget(button(self.t("reload"), self.refresh))
            grid = QGridLayout()
            grid.setHorizontalSpacing(16)
            grid.setVerticalSpacing(16)
            frames = []
            for product in products:
                frame = QFrame()
                frame.setProperty("card", True)
                frame.setSizePolicy(QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Maximum)
                card = QVBoxLayout(frame)
                card.setContentsMargins(20, 20, 20, 20)
                card.setSpacing(16)
                line = QHBoxLayout()
                line.setSpacing(18)
                line.addWidget(self.picture(product))
                text = QVBoxLayout()
                text.setSpacing(8)
                text.addWidget(heading(product["name"], 22))
                summary = product.get("summary", "")
                if summary and summary.strip() != product["name"].strip():
                    text.addWidget(paragraph(summary))
                kind = paragraph(self.t(product.get("kind", "service")))
                kind.setProperty("muted", True)
                text.addWidget(kind)
                price = paragraph(money(product["price_minor"]))
                price.setObjectName("productPrice")
                text.addWidget(price)
                if product.get("is_demo"):
                    demo = paragraph(self.t("demoGoods"))
                    demo.setProperty("muted", True)
                    text.addWidget(demo)
                line.addLayout(text, 1)
                card.addLayout(line)
                if not product["in_stock"]:
                    card.addWidget(paragraph(self.t("outOfStock")))
                actions = QHBoxLayout()
                actions.addStretch()
                actions.addWidget(button(self.t("details"), lambda checked=False, p=product: self.detail(p)))
                card.addLayout(actions)
                frames.append(frame)
            self.product_grids.append((grid, frames))
            box.addLayout(grid)
            box.addStretch()
            pager.addTab(page, self.t(category))
        pager.setCurrentIndex(categories.index(self.category) if self.category in categories else 0)
        pager.currentChanged.connect(lambda index: setattr(self, "category", categories[index]))
        pager.animate_page(pager.currentIndex())
        self.content.addWidget(pager)
        self.reflow_products()

    def reflow_products(self):
        if self.page != "products" or self.product:
            return
        wide = self.area.viewport().width() >= 980
        if hasattr(self, "hero_layout"):
            self.hero_layout.setDirection(QBoxLayout.Direction.LeftToRight if wide else QBoxLayout.Direction.TopToBottom)
            self.hero_layout.setStretch(0, 2 if wide else 0)
            self.hero_introduction_layout.setContentsMargins(0, 24 if wide else 8, 0, 24 if wide else 8)
            if self.hero_banner is not None:
                self.hero_layout.setStretch(1, 5 if wide else 0)
                self.hero_banner.picture.setFixedHeight(250 if wide else 190)
                self.hero_banner.paint_image()
        for grid, frames in getattr(self, "product_grids", []):
            columns = 2 if wide and len(frames) > 1 else 1
            for index, frame in enumerate(frames):
                grid.addWidget(frame, index // columns, index % columns)
            grid.setColumnStretch(0, 1)
            grid.setColumnStretch(1, 1 if columns == 2 else 0)
            grid.invalidate()
        if hasattr(self, "category_pager"):
            self.category_pager.update_page_height()

    def resizeEvent(self, event):
        super().resizeEvent(event)
        if hasattr(self, "area"):
            # Reflow existing widgets so resizing never discards a form or carousel state.
            QTimer.singleShot(0, self.reflow_products)

    def render_profile(self):
        user = self.state["user"]
        box = self.card()
        avatar = QLabel()
        avatar.setPixmap(self.avatar_icon(user).pixmap(96, 96))
        box.addWidget(avatar)
        box.addWidget(heading((user.get("username") or user.get("name") or user.get("account")) if user else self.t("mine"), 30))
        box.addWidget(paragraph(self.t("profileHint")))
        if not user:
            box.addWidget(button(self.t("login"), self.account, True))
        row = QGridLayout()
        for index, status in enumerate(("pending_payment", "pending_completion", "completed", "pending_review")):
            count = sum(o["status"] == status for o in self.state["orders"])
            row.addWidget(button(self.t(status) + f" ({count})", lambda checked=False, key=status: self.open_orders(key)), index // 2, index % 2)
        box.addLayout(row)
        box.addWidget(button(self.t("myOrders"), lambda: self.open_orders("all")))
        if user:
            box.addWidget(self.settings_button(), 0, Qt.AlignmentFlag.AlignRight)

    def avatar_icon(self, user):
        if user and user.get("avatar_url", "").startswith("data:image/"):
            pixmap = QPixmap()
            try:
                pixmap.loadFromData(base64.b64decode(user["avatar_url"].split(",", 1)[1], validate=True))
                if not pixmap.isNull():
                    return QIcon(pixmap)
            except (ValueError, IndexError):
                pass
        from PySide6.QtGui import QPainter
        pixmap = QPixmap(48, 48)
        pixmap.fill(Qt.GlobalColor.transparent)
        painter = QPainter(pixmap)
        painter.setRenderHint(QPainter.RenderHint.Antialiasing)
        painter.setBrush(QColor.fromHsv((user or {}).get("avatar_color", 137) % 360, 110, 160))
        painter.setPen(Qt.PenStyle.NoPen)
        painter.drawEllipse(1, 1, 46, 46)
        painter.setPen(Qt.GlobalColor.white)
        painter.drawText(pixmap.rect(), Qt.AlignmentFlag.AlignCenter, str((user or {}).get("username") or (user or {}).get("name") or "?")[:1].upper())
        painter.end()
        return QIcon(pixmap)

    def open_orders(self, status):
        self.status_filter = status
        self.show_page("orders")

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

    def submit_form(self, dialog, layout, work, submit_key="save", success=None, validate=None):
        error_label = paragraph("")
        error_label.setAccessibleName("form-error")
        error_label.hide()
        layout.addRow(error_label)
        submit = button(self.t(submit_key), lambda: send(), True)
        cancel = button(self.t("cancel"), dialog.reject)
        layout.addRow(submit)
        layout.addRow(cancel)

        def send():
            if self.busy or dialog.submitting:
                return
            error = validate() if validate else ""
            if error:
                error_label.setText(error)
                error_label.show()
                return
            error_label.hide()
            dialog.submitting = True
            submit.setEnabled(False)
            submit.setText("…")
            cancel.setEnabled(False)

            def saved(_):
                dialog.submitting = False
                dialog.accept()
                if success:
                    success()

            def failed(error):
                dialog.submitting = False
                submit.setText(self.t(submit_key))
                submit.setEnabled(not bool(self.repo.pending_request))
                cancel.setEnabled(True)
                error_label.setText(str(error))
                error_label.show()

            self.run(work(), on_success=saved, on_error=failed)

        return dialog.exec()

    def buy(self, product):
        if not self.state["user"]:
            if self.account() == QDialog.DialogCode.Accepted and self.state["user"]:
                self.buy(product)
            return
        dialog = SubmitDialog(self)
        dialog.setWindowTitle(self.t("buy"))
        form = QFormLayout(dialog)
        form.addRow(heading(product["name"], 22))
        form.addRow(heading(money(product["price_minor"]), 24))
        fields = {}
        for key in ("requirements", "contact", "delivery_requirements"):
            item = QLineEdit() if key == "contact" else QTextEdit()
            fields[key] = item
            form.addRow(self.t("deliveryRequirements" if key == "delivery_requirements" else key), item)
        def action():
            details = {key: (item.text() if key == "contact" else item.toPlainText()) for key, item in fields.items()}
            def work():
                self.repo.buy(product, **details)
                return self.repo.snapshot()
            return work
        def purchased():
            self.page = "orders"
            self.status_filter = "pending_payment"
            self.product = None
            self.render()
        self.submit_form(dialog, form, action, "buy", purchased)

    def render_orders(self):
        self.content.addWidget(heading(self.t("orders"), 30))
        if not self.state["user"]:
            box = self.card()
            box.addWidget(paragraph(self.t("signInFirst")))
            box.addWidget(button(self.t("login"), self.account, True))
            box.addWidget(button(self.t("reload"), self.refresh))
            return
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
            for key in ("requirements", "contact", "delivery_requirements"):
                if order.get(key):
                    box.addWidget(paragraph(self.t("deliveryRequirements" if key == "delivery_requirements" else key) + ": " + order[key]))
            editable = order.get("editable", not order.get("accepted_at") and order["status"] in ("pending_payment", "pending_completion") and order["fulfillment_status"] == "pending")
            if editable:
                box.addWidget(paragraph(self.t("beforeAccepted")))
                box.addWidget(button(self.t("editRequirements"), lambda checked=False, o=order: self.edit_requirements(o)))
            elif order["status"] != "cancelled":
                box.addWidget(paragraph(self.t("orderLocked")))
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

    def edit_requirements(self, order):
        dialog = SubmitDialog(self)
        dialog.setWindowTitle(self.t("editRequirements"))
        form = QFormLayout(dialog)
        fields = {}
        for key in ("requirements", "contact", "delivery_requirements"):
            field = QLineEdit(order.get(key, "")) if key == "contact" else QTextEdit(order.get(key, ""))
            fields[key] = field
            form.addRow(self.t("deliveryRequirements" if key == "delivery_requirements" else key), field)
        def action():
            details = {key: (field.text() if key == "contact" else field.toPlainText()) for key, field in fields.items()}
            def work():
                self.repo.action(order, "edit", **details)
                return self.repo.snapshot()
            return work
        self.submit_form(dialog, form, action)

    def change_filter(self):
        self.status_filter = self.filter.currentData()
        self.render()

    def checkout(self, order):
        dialog = SubmitDialog(self)
        dialog.setWindowTitle(self.t("checkout"))
        box = QFormLayout(dialog)
        box.addRow(heading(order["product_snapshot"]["name"], 22))
        box.addRow(heading(money(order["amount_minor"]), 28))
        box.addRow(paragraph(self.t("mockHint")))
        channels = QComboBox()
        for code in ("alipay", "wechat"):
            channels.addItem(self.t(code), code)
        box.addRow(channels)
        def action():
            channel = channels.currentData()
            def work():
                self.repo.action(order, "pay", channel=channel)
                return self.repo.snapshot()
            return work
        self.submit_form(dialog, box, action, "confirmPay")

    def review(self, order):
        dialog = SubmitDialog(self)
        dialog.setWindowTitle(self.t("review"))
        form = QFormLayout(dialog)
        rating = QSpinBox()
        rating.setRange(1, 5)
        rating.setValue(5)
        text = QTextEdit()
        form.addRow(self.t("rating"), rating)
        form.addRow(self.t("text"), text)
        def action():
            score, value = rating.value(), text.toPlainText().strip()
            def work():
                self.repo.action(order, "review", rating=score, text=value)
                return self.repo.snapshot()
            return work
        self.submit_form(dialog, form, action, validate=lambda: "" if text.toPlainText().strip() else self.t("requiredReview"))

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
            self.scroll_positions.clear()
            self.render()
            return
        dialog = SubmitDialog(self)
        dialog.setWindowTitle(self.t("login"))
        form = QFormLayout(dialog)
        tabs = QTabWidget()
        fields = {}
        for mode in ("login", "register", "forgotPassword"):
            page = QWidget()
            page_form = QFormLayout(page)
            values = {}
            for key in (("account", "password") if mode == "login" else ("email", "code", "username", "password", "confirmPassword") if mode == "register" else ("email", "code", "password", "confirmPassword")):
                field = QLineEdit()
                field.setAccessibleName(self.t(key))
                if key in ("password", "confirmPassword"):
                    field.setEchoMode(QLineEdit.EchoMode.Password)
                values[key] = field
                page_form.addRow(self.t(key), field)
            if mode != "login":
                code_notice = paragraph("")
                def send_code(checked=False, values=values, mode=mode, code_notice=code_notice):
                    captured = values["email"].text()
                    delivery = {}
                    def work():
                        delivery.update(self.repo.request_email_code(captured, "register" if mode == "register" else "reset_password"))
                        return self.repo.snapshot()
                    def sent(_):
                        code_notice.setText(self.t("demoCode") + ": " + delivery["demo_code"] if delivery.get("delivery") == "demo" else self.t("codeSent"))
                    self.run(work, on_success=sent, on_error=lambda error: code_notice.setText(str(error)))
                page_form.addRow(button(self.t("sendCode"), send_code))
                page_form.addRow(code_notice)
            fields[mode] = values
            tabs.addTab(page, self.t(mode))
        form.addRow(tabs)
        if self.state.get("demo_mode") and self.state.get("demo_credentials"):
            form.addRow(paragraph(self.t("demoConfiguredHint")))
            for credential in self.state.get("demo_credentials", []):
                role = self.t("merchant" if credential["role"] == "admin" else "demoCustomer")
                form.addRow(heading(role, 16))
                for field in ("account", "password"):
                    value = credential[field]
                    row = QHBoxLayout()
                    row.addWidget(paragraph(value), 1)
                    copy_button = button(self.t("copy"), lambda checked=False, v=value: self.copy_value(v))
                    row.addWidget(copy_button)
                    form.addRow(self.t(field), row)
        def login_action():
            mode = ("login", "register", "forgotPassword")[tabs.currentIndex()]
            values = {key: value.text() for key, value in fields[mode].items()}
            if mode == "login":
                return lambda: self.repo.login(values["account"], values["password"])
            if mode == "register":
                return lambda: self.repo.register(values["email"], values["code"], values["username"], values["password"], values["confirmPassword"])
            return lambda: self.repo.reset_password(values["email"], values["code"], values["password"], values["confirmPassword"])
        return self.submit_form(dialog, form, login_action, "continueAuth")

    def copy_value(self, value):
        QApplication.clipboard().setText(value)
        QToolTip.showText(self.mapToGlobal(self.rect().center()), self.t("copied"), self, self.rect(), 1500)

    def switch_account(self):
        if self.busy:
            return
        self.repo.logout()
        self.state = self.repo.snapshot()
        self.scroll_positions.clear()
        self.render()
        self.account()

    def render_settings(self):
        box = self.card()
        form = QFormLayout()
        form.addRow(self.t("language"), self.language)
        form.addRow(self.t("theme"), self.theme)
        self.language.show()
        self.theme.show()
        if self.state["user"]:
            box.addWidget(button(self.t("switchAccount"), self.switch_account))
        if self.state["user"]:
            name = QLineEdit(self.state["user"].get("username") or self.state["user"].get("name", ""))
            form.addRow(self.t("username"), name)
            selected = {"avatar": None}
            avatar_notice = paragraph("")
            def choose_avatar():
                path, _ = QFileDialog.getOpenFileName(self, self.t("uploadAvatar"), "", "Images (*.png *.jpg *.jpeg *.webp)")
                if not path:
                    return
                data = Path(path).read_bytes()
                pixmap = QPixmap()
                if len(data) > 2 * 1024 * 1024 or not pixmap.loadFromData(data):
                    avatar_notice.setText(self.t("invalidAvatar"))
                    return
                from PySide6.QtCore import QByteArray, QBuffer, QIODevice
                encoded = QByteArray()
                buffer = QBuffer(encoded)
                buffer.open(QIODevice.OpenModeFlag.WriteOnly)
                pixmap.scaled(256, 256, Qt.AspectRatioMode.KeepAspectRatio, Qt.TransformationMode.SmoothTransformation).save(buffer, "PNG")
                selected["avatar"] = "data:image/png;base64," + base64.b64encode(bytes(encoded)).decode()
                avatar_notice.setText(Path(path).name)
            form.addRow(button(self.t("uploadAvatar"), choose_avatar))
            form.addRow(avatar_notice)
            def save_profile():
                captured_name, captured_avatar = name.text(), selected["avatar"]
                self.run(lambda: self.repo.update_profile(captured_name, captured_avatar))
            form.addRow(button(self.t("saveProfile"), save_profile, True))
        box.addLayout(form)
        if not self.state.get("demo_mode"):
            return
        form = QFormLayout()
        address = QLineEdit(self.connection_draft["api"])
        self.address_input = address
        address.textChanged.connect(lambda value: self.connection_draft.update(api=value))
        timeout = QSpinBox()
        self.timeout_input = timeout
        timeout.setRange(500, 10000)
        timeout.setValue(int(self.connection_draft["timeout"] * 1000))
        timeout.valueChanged.connect(lambda value: self.connection_draft.update(timeout=value / 1000))
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
        if self.closed or self.page == "settings":
            return
        self.run(self.repo.refresh, background=True)

    def run(self, function, on_success=None, on_error=None, background=False):
        if self.busy or self.closed or background and self.reading:
            return
        if background:
            self.reading = True
        else:
            self.busy = True
            self.area.setEnabled(False)
            self.account_button.setEnabled(False)
            self.reload_button.setEnabled(False)
        task = Task(function, self.generation)
        self.tasks.add(task)
        def finish(value, error, generation):
            self.tasks.discard(task)
            if background:
                self.reading = False
            else:
                self.busy = False
                self.area.setEnabled(True)
                self.account_button.setEnabled(True)
                self.reload_button.setEnabled(True)
            if generation != self.generation or self.closed or background and self.busy:
                return
            self.error_message = str(error) if error else ""
            self.state = self.repo.snapshot() if error else value
            if self.product:
                self.product = next((p for p in self.state["products"] if p["id"] == self.product["id"] and p["active"]), None)
            self.render()
            if error and on_error:
                on_error(error)
            elif not error and on_success:
                on_success(value)
        task.signals.finished.connect(finish)
        self.pool.start(task)

    def closeEvent(self, event):
        self.closed = True
        self.generation += 1
        self.timer.stop()
        self.initial_refresh.stop()
        self.pool.waitForDone(12_000)
        event.accept()
