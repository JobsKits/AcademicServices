"""首页轮播和带横向手势的分类页，网络失败始终保留打包图片。"""
import base64
from pathlib import Path
from urllib.parse import urljoin, urlsplit

from PySide6.QtCore import QEasingCurve, QEvent, QPoint, QPropertyAnimation, QSize, QTimer, Qt, QUrl
from PySide6.QtGui import QDesktopServices, QIcon, QPainter, QPalette, QPixmap
from PySide6.QtNetwork import QNetworkAccessManager, QNetworkRequest
from PySide6.QtWidgets import QApplication, QDialog, QLabel, QSizePolicy, QTabWidget, QVBoxLayout, QHBoxLayout, QPushButton, QWidget


class SettingsButton(QPushButton):
    def __init__(self, label, callback):
        super().__init__()
        self.setProperty("settingsEntry", True)
        self.setAccessibleName(label)
        self.setToolTip(label)
        self.setFixedSize(44, 44)
        self.setIconSize(QSize(26, 26))
        self.clicked.connect(callback)
        self.update_icon()

    def update_icon(self):
        # Some system themes omit this icon; the bundled font provides a gear fallback.
        pixmap = QPixmap(32, 32)
        pixmap.fill(Qt.GlobalColor.transparent)
        painter = QPainter(pixmap)
        painter.setRenderHint(QPainter.RenderHint.Antialiasing)
        font = QApplication.font()
        font.setPixelSize(28)
        painter.setFont(font)
        painter.setPen(self.palette().color(QPalette.ColorRole.ButtonText))
        painter.drawText(pixmap.rect(), Qt.AlignmentFlag.AlignCenter, "⚙")
        painter.end()
        self.setIcon(QIcon.fromTheme("preferences-system", QIcon(pixmap)))

    def changeEvent(self, event):
        super().changeEvent(event)
        if event.type() in (QEvent.Type.PaletteChange, QEvent.Type.ApplicationPaletteChange):
            self.update_icon()


class SubmitDialog(QDialog):
    """提交完成前保留表单；关闭不能让正在进行的写操作失去反馈。"""
    submitting = False

    def reject(self):
        if not self.submitting:
            super().reject()


def valid_web_link(value):
    try:
        parsed = urlsplit(value)
        return parsed.scheme in ("https", "http") and bool(parsed.hostname) and not parsed.username and not parsed.password
    except (TypeError, ValueError):
        return False


class BannerCarousel(QWidget):
    def __init__(self, banners, assets, base, parent=None, t=lambda key: key, interval_ms=4500):
        super().__init__(parent)
        self.assets = Path(assets)
        self.base = base
        self.banners = banners or [dict(id=k, title="", image="", target_url="") for k in ("graduation", "journal", "editing")]
        self.index = 0
        self.t = t
        self.paused = False
        self.hovered = False
        self.drag_start = None
        self.source = QPixmap()
        self.network = QNetworkAccessManager(self)
        layout = QVBoxLayout(self)
        layout.setContentsMargins(0, 0, 0, 0)
        self.picture = QLabel()
        self.picture.setMinimumHeight(180)
        self.picture.setMaximumHeight(290)
        self.picture.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self.picture.setSizePolicy(QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Fixed)
        self.picture.installEventFilter(self)
        self.picture.setMouseTracking(True)
        layout.addWidget(self.picture)
        self.title = QLabel()
        self.title.setWordWrap(True)
        self.title.setAlignment(Qt.AlignmentFlag.AlignCenter)
        layout.addWidget(self.title)
        self.controls = QWidget(self.picture)
        self.controls.setObjectName("bannerIndicators")
        self.controls.setStyleSheet("QWidget#bannerIndicators {background:rgba(255,253,248,220);border-radius:14px;}")
        controls = QHBoxLayout(self.controls)
        controls.setContentsMargins(0, 0, 0, 0)
        controls.setSpacing(2)
        self.indicators = []
        for index in range(len(self.banners)):
            item = QPushButton()
            item.setCheckable(True)
            item.setFocusPolicy(Qt.FocusPolicy.TabFocus)
            item.setFixedSize(36, 36)
            item.setAccessibleName(f"{t('banners')} {index + 1}")
            item.setStyleSheet("QPushButton {color:#392b22;border:0;background:transparent;padding:0;font-size:14px;} QPushButton:focus {border:1px solid #805334;}")
            item.clicked.connect(lambda checked=False, target=index: self.select_page(target))
            self.indicators.append(item)
            controls.addWidget(item)
        self.controls.setVisible(len(self.banners) > 1)
        self.setFocusPolicy(Qt.FocusPolicy.TabFocus)
        self.timer = QTimer(self)
        self.timer.timeout.connect(self.advance)
        self.timer.setInterval(max(1500, int(interval_ms)))
        QApplication.instance().applicationStateChanged.connect(self.schedule)
        QApplication.instance().focusChanged.connect(self.focus_changed)
        self.load()

    def focus_changed(self, previous, current):
        self.schedule()

    def schedule(self, *_):
        if self.isVisible() and len(self.banners) > 1 and not self.paused and self.drag_start is None and QApplication.applicationState() == Qt.ApplicationState.ApplicationActive:
            self.timer.start()
        else:
            self.timer.stop()

    def eventFilter(self, obj, event):
        if obj is self.picture:
            if event.type() == QEvent.Type.MouseButtonPress and event.button() == Qt.MouseButton.LeftButton:
                self.drag_start = event.position()
                self.timer.stop()
                self.picture.grabMouse()
                return True
            if event.type() == QEvent.Type.MouseMove and self.drag_start is not None:
                return True
            if event.type() == QEvent.Type.MouseButtonRelease and self.drag_start is not None:
                delta = event.position() - self.drag_start
                self.drag_start = None
                self.picture.releaseMouse()
                if abs(delta.x()) >= 50 and abs(delta.x()) > abs(delta.y()) * 1.3:
                    self.manual_step(1 if delta.x() < 0 else -1)
                elif abs(delta.x()) < 10 and abs(delta.y()) < 10:
                    self.open_banner(event)
                self.schedule()
                return True
        return super().eventFilter(obj, event)

    def toggle_pause(self):
        self.paused = not self.paused
        self.schedule()

    def manual_step(self, amount):
        self.select_page((self.index + amount) % len(self.banners))

    def select_page(self, index):
        self.index = index
        self.load()
        self.schedule()

    def showEvent(self, event):
        super().showEvent(event)
        self.schedule()

    def hideEvent(self, event):
        self.timer.stop()
        super().hideEvent(event)

    def enterEvent(self, event):
        self.hovered = True
        self.schedule()
        super().enterEvent(event)

    def leaveEvent(self, event):
        self.hovered = False
        self.schedule()
        super().leaveEvent(event)

    def focusInEvent(self, event):
        self.schedule()
        super().focusInEvent(event)

    def keyPressEvent(self, event):
        if event.key() in (Qt.Key.Key_Left, Qt.Key.Key_Right):
            self.manual_step(-1 if event.key() == Qt.Key.Key_Left else 1)
        elif event.key() == Qt.Key.Key_Space:
            self.toggle_pause()
        else:
            super().keyPressEvent(event)

    def advance(self):
        self.index = (self.index + 1) % len(self.banners)
        self.load()

    def load(self):
        current = self.banners[self.index]
        self.source = QPixmap(str(self.assets / "Banners" / (("graduation", "journal", "editing")[self.index % 3] + ".png")))
        self.paint_image()
        self.title.setText(str(current.get("title", "")))
        self.title.setVisible(bool(self.title.text()))
        for index, item in enumerate(self.indicators):
            selected = index == self.index
            item.setChecked(selected)
            item.setText("●" if selected else "○")
        self.picture.setCursor(Qt.CursorShape.PointingHandCursor if valid_web_link(current.get("target_url", "")) else Qt.CursorShape.ArrowCursor)
        image = current.get("image", "")
        if image.startswith("data:image/"):
            try:
                pixmap = QPixmap()
                pixmap.loadFromData(base64.b64decode(image.split(",", 1)[1], validate=True))
                if not pixmap.isNull():
                    self.source = pixmap
                    self.paint_image()
            except (ValueError, IndexError):
                pass
        elif image:
            address = urljoin(self.base + "/", image)
            if not valid_web_link(address):
                return
            request = QNetworkRequest(QUrl(address))
            request.setTransferTimeout(2500)
            reply = self.network.get(request)
            expected = self.index
            def finished():
                if expected == self.index and reply.bytesAvailable() <= 3 * 1024 * 1024:
                    pixmap = QPixmap()
                    pixmap.loadFromData(reply.readAll())
                    if not pixmap.isNull():
                        self.source = pixmap
                        self.paint_image()
                reply.deleteLater()
            reply.finished.connect(finished)

    def paint_image(self):
        if not self.source.isNull():
            self.picture.setPixmap(self.source.scaled(max(200, self.picture.width()), max(180, self.picture.height()), Qt.AspectRatioMode.KeepAspectRatio, Qt.TransformationMode.SmoothTransformation))
            self.controls.adjustSize()
            pixmap = self.picture.pixmap()
            image_width = pixmap.width() / pixmap.devicePixelRatio()
            image_height = pixmap.height() / pixmap.devicePixelRatio()
            right = (self.picture.width() + image_width) / 2
            bottom = (self.picture.height() + image_height) / 2
            self.controls.move(max(0, int(right - self.controls.width() - 12)), max(0, int(bottom - self.controls.height() - 12)))
            self.controls.raise_()

    def resizeEvent(self, event):
        super().resizeEvent(event)
        self.paint_image()

    def open_banner(self, event):
        self.schedule()
        target = self.banners[self.index].get("target_url", "")
        if valid_web_link(target):
            QDesktopServices.openUrl(QUrl(target))


class CategoryPager(QTabWidget):
    def __init__(self, parent=None):
        super().__init__(parent)
        self.setDocumentMode(True)
        self.setUsesScrollButtons(True)
        self.start_point = None
        self.animation = None
        self.currentChanged.connect(self.animate_page)
        QApplication.instance().installEventFilter(self)

    def eventFilter(self, obj, event):
        if isinstance(obj, QWidget) and (obj is self or self.isAncestorOf(obj)):
            if event.type() == QEvent.Type.MouseButtonPress:
                self.start_point = event.globalPosition()
            elif event.type() == QEvent.Type.MouseButtonRelease and self.start_point is not None:
                delta = event.globalPosition() - self.start_point
                self.start_point = None
                if abs(delta.x()) > 75 and abs(delta.x()) > abs(delta.y()) * 1.4:
                    next_index = self.currentIndex() + (-1 if delta.x() > 0 else 1)
                    self.setCurrentIndex(max(0, min(self.count() - 1, next_index)))
                    return True
        return super().eventFilter(obj, event)

    def animate_page(self, index):
        page = self.widget(index)
        if page is None:
            return
        self.update_page_height()
        self.animation = QPropertyAnimation(page, b"pos", self)
        self.animation.setDuration(230)
        self.animation.setStartValue(page.pos() + QPoint(min(60, max(20, self.width() // 5)), 0))
        self.animation.setEndValue(page.pos())
        self.animation.setEasingCurve(QEasingCurve.Type.OutCubic)
        self.animation.start()

    def update_page_height(self):
        page = self.currentWidget()
        if page is not None:
            self.setMinimumHeight(page.sizeHint().height() + self.tabBar().sizeHint().height() + 12)
