"""Jobs 知序桌面端：业务请求在工作线程中执行，迟到回包按会话代次丢弃。"""
import argparse
import sys
from pathlib import Path

from PySide6.QtCore import QObject, QRunnable, Qt, QThreadPool, QTimer, Signal
from PySide6.QtGui import QColor, QIcon, QPalette
from PySide6.QtWidgets import (
    QApplication, QCheckBox, QComboBox, QDialog, QDialogButtonBox, QFileDialog,
    QFormLayout, QFrame, QHBoxLayout, QLabel, QLineEdit, QListWidget,
    QListWidgetItem, QMainWindow, QMessageBox, QPushButton, QScrollArea,
    QSpinBox, QStackedWidget, QTextEdit, QVBoxLayout, QWidget,
)
from .repository import ApiError, Repository, SERVICES, STATUS, UnknownWrite, api_url
from .settings import Settings


class Result(QObject):
    finished = Signal(object, object, int)


class Task(QRunnable):
    def __init__(self, function, generation):
        super().__init__()
        self.function, self.generation = function, generation
        self.signals = Result()

    def run(self):
        try:
            self.signals.finished.emit(self.function(), None, self.generation)
        except Exception as error:
            self.signals.finished.emit(None, error, self.generation)


def heading(text, size=20):
    label = QLabel(text)
    label.setWordWrap(True)
    font = label.font()
    font.setPointSize(size)
    font.setBold(True)
    label.setFont(font)
    label.setStyleSheet(f"font-size:{size}px;font-weight:650;")
    return label


def paragraph(text):
    label = QLabel(text)
    label.setWordWrap(True)
    label.setTextInteractionFlags(Qt.TextInteractionFlag.TextSelectableByMouse)
    return label


def button(text, callback, primary=False):
    item = QPushButton(text)
    item.clicked.connect(callback)
    item.setMinimumHeight(38)
    if primary:
        item.setProperty("primary", True)
    return item


def clear(layout):
    while layout.count():
        child = layout.takeAt(0)
        if child.widget():
            child.widget().deleteLater()
        elif child.layout():
            clear(child.layout())


def scroll_page():
    area = QScrollArea()
    area.setWidgetResizable(True)
    area.setFrameShape(QFrame.Shape.NoFrame)
    body = QWidget()
    layout = QVBoxLayout(body)
    layout.setContentsMargins(28, 24, 28, 24)
    layout.setSpacing(18)
    area.setWidget(body)
    return area, layout


def money(value):
    return f"¥{int(value or 0) / 100:,.2f}"


def status_text(value):
    return STATUS.get(value, {"offered": "待确认", "accepted": "已确认", "superseded": "已有新版", "expired": "已过期", "declined": "已拒绝", "requested": "待审核", "approved": "已批准待执行", "processing": "处理中", "unknown": "结果待核对", "succeeded": "已核实成功", "failed": "已核实失败", "rejected": "已拒绝", "open": "处理中"}.get(value, "待核对"))


class MainWindow(QMainWindow):
    def __init__(self, settings=None, repository=None):
        super().__init__()
        self.settings = settings or Settings()
        self.repo = repository or Repository(self.settings)
        self.state = self.repo.snapshot()
        self.generation = 0
        self.busy = False
        self.selected_id = None
        self.tasks = set()
        self.pool = QThreadPool(self)
        self.pool.setMaxThreadCount(1)
        self.setWindowTitle("知序 · 学术服务")
        self.setWindowIcon(QIcon(str(Path(__file__).parent / "Assets/brand.svg")))
        self.resize(1180, 800)
        self.setMinimumSize(760, 560)
        self.build()
        self.apply_theme()
        QApplication.styleHints().colorSchemeChanged.connect(self.apply_theme)
        self.render_home()
        self.render_workspace()
        self.refresh_timer = QTimer(self)
        self.refresh_timer.timeout.connect(self.refresh)
        self.refresh_timer.start(30_000)
        QTimer.singleShot(100, self.refresh)

    def build(self):
        container = QWidget()
        shell = QVBoxLayout(container)
        shell.setContentsMargins(0, 0, 0, 0)
        shell.setSpacing(0)
        header = QWidget()
        header.setObjectName("header")
        row = QHBoxLayout(header)
        row.setContentsMargins(26, 16, 26, 16)
        row.addWidget(heading("知序", 23))
        row.addWidget(paragraph("让每一步，都清楚"))
        row.addStretch()
        self.theme = QComboBox()
        self.theme.setAccessibleName("外观主题")
        self.theme.addItem("跟随系统", "system")
        self.theme.addItem("白天", "light")
        self.theme.addItem("黑夜", "dark")
        self.theme.setCurrentIndex(max(0, self.theme.findData(self.settings.values["theme"])))
        self.theme.currentIndexChanged.connect(self.change_theme)
        row.addWidget(self.theme)
        self.account_button = button("登录", self.account)
        row.addWidget(self.account_button)
        shell.addWidget(header)
        self.notice = paragraph(self.state["notice"])
        self.notice.setObjectName("notice")
        self.notice.setContentsMargins(26, 12, 26, 12)
        shell.addWidget(self.notice)
        nav = QHBoxLayout()
        nav.setContentsMargins(24, 10, 24, 6)
        nav.addWidget(button("服务首页", lambda: self.pages.setCurrentIndex(0)))
        nav.addWidget(button("我的需求与订单", lambda: self.pages.setCurrentIndex(1)))
        nav.addWidget(button("连接设置", lambda: self.pages.setCurrentIndex(2)))
        nav.addStretch()
        self.reload_button = button("重新加载", self.refresh)
        nav.addWidget(self.reload_button)
        shell.addLayout(nav)
        self.pages = QStackedWidget()
        self.home, self.home_layout = scroll_page()
        self.workspace, self.workspace_layout = scroll_page()
        self.config, self.config_layout = scroll_page()
        self.pages.addWidget(self.home)
        self.pages.addWidget(self.workspace)
        self.pages.addWidget(self.config)
        shell.addWidget(self.pages, 1)
        self.status_label = paragraph("就绪")
        self.status_label.setContentsMargins(26, 8, 26, 8)
        shell.addWidget(self.status_label)
        self.setCentralWidget(container)
        self.render_settings()

    def change_theme(self):
        self.settings.save(theme=self.theme.currentData())
        self.apply_theme()

    def apply_theme(self, *_):
        choice = self.settings.values["theme"]
        dark = choice == "dark" or (choice == "system" and QApplication.styleHints().colorScheme() == Qt.ColorScheme.Dark)
        colors = ({"bg": "#101b20", "card": "#192a30", "text": "#eef5f4", "sub": "#b4c9c9", "line": "#496065", "brand": "#90dbce", "onbrand": "#103d38", "notice": "#223c3e", "disabled": "#9eb5b5", "selected": "#2b5556"} if dark else {"bg": "#f4f7f7", "card": "#ffffff", "text": "#172d32", "sub": "#4b6268", "line": "#b3c5c9", "brand": "#135d58", "onbrand": "#ffffff", "notice": "#e2f0ed", "disabled": "#53666c", "selected": "#d6eae5"})
        self.colors = colors
        palette = QPalette()
        for role, color in ((QPalette.ColorRole.Window, "bg"), (QPalette.ColorRole.WindowText, "text"), (QPalette.ColorRole.Base, "card"), (QPalette.ColorRole.AlternateBase, "bg"), (QPalette.ColorRole.ToolTipBase, "card"), (QPalette.ColorRole.ToolTipText, "text"), (QPalette.ColorRole.Text, "text"), (QPalette.ColorRole.Button, "card"), (QPalette.ColorRole.ButtonText, "text"), (QPalette.ColorRole.Highlight, "brand"), (QPalette.ColorRole.HighlightedText, "onbrand"), (QPalette.ColorRole.PlaceholderText, "sub")):
            palette.setColor(role, QColor(colors[color]))
        for role in (QPalette.ColorRole.Text, QPalette.ColorRole.ButtonText, QPalette.ColorRole.WindowText):
            palette.setColor(QPalette.ColorGroup.Disabled, role, QColor(colors["disabled"]))
        QApplication.instance().setPalette(palette)
        QApplication.instance().setStyleSheet(f'''
            QWidget {{font-size:14px; color:{colors['text']};}}
            QMainWindow,QScrollArea,QScrollArea>QWidget>QWidget {{background:{colors['bg']};}}
            #header,QFrame[card="true"] {{background:{colors['card']};}}
            #notice {{background:{colors['notice']};color:{colors['text']};}}
            QFrame[card="true"] {{border:1px solid {colors['line']};border-radius:14px;}}
            QPushButton {{background:{colors['card']};border:1px solid {colors['line']};border-radius:7px;padding:7px 14px;}}
            QPushButton:hover {{border:1px solid {colors['brand']};background:{colors['selected']};}}
            QPushButton[primary="true"] {{background:{colors['brand']};color:{colors['onbrand']};border-color:{colors['brand']};}}
            QPushButton:disabled {{background:{colors['bg']};color:{colors['disabled']};}}
            QLineEdit,QTextEdit,QSpinBox,QComboBox,QListWidget {{background:{colors['card']};color:{colors['text']};border:1px solid {colors['line']};border-radius:6px;padding:7px;selection-background-color:{colors['brand']};selection-color:{colors['onbrand']};}}
            QComboBox QAbstractItemView {{background:{colors['card']};color:{colors['text']};selection-background-color:{colors['brand']};selection-color:{colors['onbrand']};}}
            QListWidget::item:selected {{background:{colors['selected']};color:{colors['text']};}}
            QScrollBar {{background:{colors['bg']};}} QScrollBar::handle {{background:{colors['line']};min-height:25px;}}
            QLabel[secondary="true"] {{color:{colors['sub']};}}
            QToolTip {{background:{colors['card']};color:{colors['text']};border:1px solid {colors['line']};}}
        ''')

    def card(self, title, text=""):
        frame = QFrame()
        frame.setProperty("card", True)
        layout = QVBoxLayout(frame)
        layout.setContentsMargins(22, 20, 22, 20)
        layout.setSpacing(14)
        layout.addWidget(heading(title))
        if text:
            description = paragraph(text)
            description.setProperty("secondary", True)
            layout.addWidget(description)
        return frame, layout

    def render_home(self):
        clear(self.home_layout)
        self.home_layout.addWidget(heading("明确需求，再开始服务", 28))
        self.home_layout.addWidget(paragraph("只专注三项服务。先说明目标、确认范围与报价，再跟进进度和交付。"))
        for index, service in enumerate(self.state.get("services") or []):
            frame, layout = self.card(f'{index + 1:02d}   {service.get("name", "服务")}', service.get("summary", ""))
            layout.addWidget(paragraph(service.get("description", "服务以确认的报价为准")))
            call = button("提交需求", lambda checked=False, item=service: self.create_case(item), True)
            call.setEnabled(bool(service.get("active", True)))
            layout.addWidget(call, alignment=Qt.AlignmentFlag.AlignLeft)
            self.home_layout.addWidget(frame)
        if not self.state.get("services"):
            self.home_layout.addWidget(heading("暂无开放服务"))
            self.home_layout.addWidget(button("重新加载服务目录", self.refresh))
        self.home_layout.addStretch()

    def render_workspace(self):
        clear(self.workspace_layout)
        self.workspace_layout.addWidget(heading("我的需求与订单", 26))
        if self.state.get("pending"):
            frame, layout = self.card("有一笔提交结果待核对", "请先重新加载核对。未查到不代表失败；原键重试不会重复创建同一操作。")
            layout.addWidget(button("重新核对", self.reconcile))
            layout.addWidget(button("使用原请求键重试", self.retry))
            self.workspace_layout.addWidget(frame)
        if not self.state.get("user"):
            self.workspace_layout.addWidget(paragraph("登录后查看自己的需求、报价、进度和交付。"))
            self.workspace_layout.addWidget(button("登录客户账号", self.account, True))
            self.workspace_layout.addStretch()
            return
        cases = self.state.get("cases") or []
        if not cases:
            frame, layout = self.card("还没有需求", "可以从服务首页提交第一份需求，也可以重新加载查看最新资料。")
            layout.addWidget(button("去选择服务", lambda: self.pages.setCurrentIndex(0), True))
            layout.addWidget(button("重新加载我的需求", self.refresh))
            self.workspace_layout.addWidget(frame)
            self.workspace_layout.addStretch()
            return
        chooser = QComboBox()
        chooser.setAccessibleName("选择需求或订单")
        for case in cases:
            status = (case.get("order") or {}).get("status", case["status"])
            chooser.addItem(f'{case["title"]}  ·  {STATUS.get(status, status)}', case["id"])
        selected = next((c for c in cases if c["id"] == self.selected_id), cases[0])
        self.selected_id = selected["id"]
        chooser.setCurrentIndex(max(0, chooser.findData(self.selected_id)))
        chooser.currentIndexChanged.connect(lambda _: self.select_case(chooser.currentData()))
        self.workspace_layout.addWidget(chooser)
        self.render_case(selected)
        self.workspace_layout.addStretch()

    def select_case(self, case_id):
        self.selected_id = case_id
        self.render_workspace()

    def render_case(self, case):
        order, offer = case.get("order") or {}, case.get("quote") or {}
        state = order.get("status", case["status"])
        frame, layout = self.card(case["title"], f'{STATUS.get(state, state)}  ·  v{case["version"]}  ·  {case.get("updated_at", "")}')
        layout.addWidget(paragraph(case.get("description", "")))
        extra = [str(case.get(k, "")) for k in ("discipline", "level", "language", "deadline") if case.get(k)]
        layout.addWidget(paragraph(" / ".join(extra)))
        if order.get("paused"):
            layout.addWidget(paragraph("服务已暂停 · 所有暂停事项解除后可继续。已约定期限不会自动顺延。"))
        self.workspace_layout.addWidget(frame)
        if offer:
            frame, layout = self.card("报价与服务约定", f'{money(offer.get("amount_minor"))}   ·  启动款 {money(offer.get("prepay_minor"))}   ·  {status_text(offer.get("status", ""))}')
            layout.addWidget(paragraph(offer.get("scope", "")))
            layout.addWidget(paragraph(f'有效期至 {offer.get("expires_at", "")}；含 {offer.get("revision_limit", 0)} 轮约定修改。'))
            if case["status"] == "awaiting_quote_accept" and offer.get("status") == "offered":
                layout.addWidget(button("确认本版报价并生成订单", lambda: self.perform(case, "accept_quote", {"quote_id": offer["id"]}, confirm=True), True))
                layout.addWidget(button("拒绝本版报价", lambda: self.text_action(case, "decline_quote", "拒绝报价的原因")))
            self.workspace_layout.addWidget(frame)
        if order:
            frame, layout = self.card("订单进度与资金", f'当前应付 {money(order.get("amount_minor"))} · 已收 {money(order.get("paid_minor"))} · 已退 {money(order.get("refunded_minor"))} · 退款处理中 {money(order.get("refund_held_minor"))}')
            layout.addWidget(paragraph(f'修改轮次 {order.get("revision_used", 0)} / {order.get("revision_limit", 0)}；资金以人工核实记录为准。'))
            for payment in order.get("payments") or []:
                layout.addWidget(paragraph(f'收款 {money(payment.get("amount_minor"))} · {status_text(payment.get("status", ""))} · 凭据 {payment.get("reference", "")}'))
            for refund in order.get("refunds") or []:
                layout.addWidget(paragraph(f'退款 {money(refund.get("amount_minor"))} · {status_text(refund.get("status", ""))}'))
            cancel = order.get("cancellation")
            if cancel and cancel.get("status") == "offered":
                layout.addWidget(paragraph(f'取消结算方案：最终应付 {money(cancel.get("settlement_minor"))}。{cancel.get("reason", "")}'))
                layout.addWidget(button("确认取消与最终结算", lambda: self.perform(case, "confirm_cancel", {}, confirm=True)))
                layout.addWidget(button("拒绝取消方案", lambda: self.perform(case, "reject_cancel", {}, confirm=True)))
            for change in order.get("changes") or []:
                if change.get("status") != "offered":
                    continue
                layout.addWidget(paragraph(f'变更方案：{money(change.get("amount_minor"))} · {change.get("deadline", "")}\n{change.get("scope", "")}'))
                layout.addWidget(button("确认服务变更", lambda checked=False, c=change: self.perform(case, "confirm_change", {"change_id": c["id"]}, confirm=True)))
                layout.addWidget(button("拒绝服务变更", lambda checked=False, c=change: self.perform(case, "reject_change", {"change_id": c["id"]}, confirm=True)))
            if state in ("completed", "cancelled"):
                layout.addWidget(button("发起售后", lambda: self.text_action(case, "after_sale", "说明售后问题")))
            for delivery in order.get("deliveries") or []:
                row = paragraph(f'{"售后" if delivery.get("after_sale_id") else "主服务"}交付 第{delivery.get("version", 1)}版 · {"已确认" if delivery.get("accepted_at") else "待确认"}\n{delivery.get("text", delivery.get("summary", ""))}')
                layout.addWidget(row)
            deliveries = [x for x in order.get("deliveries") or [] if not x.get("after_sale_id") and x.get("status", "released") == "released"]
            if deliveries and state in ("awaiting_acceptance", "revising"):
                latest = deliveries[-1]
                layout.addWidget(button("反馈修改意见", lambda: self.text_action(case, "revision", "说明修改意见", {"delivery_id": latest["id"]})))
                if state == "awaiting_acceptance":
                    layout.addWidget(button("确认验收最新主交付", lambda: self.perform(case, "accept_delivery", {"delivery_id": latest["id"]}, confirm=True), True))
            for after_sale in case.get("after_sales") or []:
                if after_sale.get("status") != "open":
                    continue
                group = [d for d in order.get("deliveries") or [] if d.get("after_sale_id") == after_sale["id"] and d.get("status") == "released"]
                if group and not group[-1].get("accepted_at"):
                    latest_after = group[-1]
                    layout.addWidget(button("售后交付：反馈修改", lambda checked=False, d=latest_after: self.text_action(case, "revision", "说明售后交付修改意见", {"delivery_id": d["id"]})))
                    layout.addWidget(button("验收最新售后交付", lambda checked=False, d=latest_after: self.perform(case, "accept_delivery", {"delivery_id": d["id"]}, confirm=True)))
            self.workspace_layout.addWidget(frame)
        frame, layout = self.card("材料与交付文件", "文件经服务器授权后获取；上传会保留独立版本。")
        for attachment in case.get("attachments") or []:
            item = button(attachment.get("name", attachment.get("filename", "附件")) + "  ·  下载", lambda checked=False, a=attachment: self.download(case, a))
            layout.addWidget(item)
        if not case.get("attachments"):
            layout.addWidget(paragraph("暂无文件。可以上传材料或重新加载查看交付附件。"))
        layout.addWidget(button("上传材料（最大8MB）", lambda: self.upload(case)))
        self.workspace_layout.addWidget(frame)
        frame, layout = self.card("沟通与时间线")
        for message in (case.get("messages") or [])[-15:]:
            layout.addWidget(paragraph(f'{message.get("author_name", message.get("author_id", "经办人"))}  {message.get("created_at", "")}\n{message.get("text", "")}'))
        if not case.get("messages"):
            layout.addWidget(paragraph("还没有留言。"))
        layout.addWidget(button("发送留言", lambda: self.text_action(case, "message", "留言内容")))
        if not order and case["status"] != "closed":
            layout.addWidget(button("补充需求说明", lambda: self.text_action(case, "supplement", "补充说明")))
        if not order and case["status"] != "closed":
            layout.addWidget(button("撤回未成交需求", lambda: self.text_action(case, "withdraw_request", "撤回需求的原因")))
        for event in (case.get("events") or [])[-12:]:
            layout.addWidget(paragraph(f'{event.get("created_at", "")} · {event.get("type", event.get("action", "进度更新"))}'))
        for after_sale in case.get("after_sales") or []:
            layout.addWidget(paragraph("售后：" + str(after_sale.get("text", after_sale.get("reason", ""))) + " · " + status_text(after_sale.get("status", ""))))
        self.workspace_layout.addWidget(frame)

    def render_settings(self):
        clear(self.config_layout)
        self.config_layout.addWidget(heading("连接设置", 26))
        self.config_layout.addWidget(paragraph("本机演示使用默认地址；连接远程服务器时使用管理员提供的 HTTPS 地址。更换地址会退出当前账号。"))
        form = QFormLayout()
        self.api_field = QLineEdit(self.settings.values["api"])
        self.timeout_field = QComboBox()
        for value in (1.5, 2.5, 5.0, 10.0):
            self.timeout_field.addItem(f"{value:g} 秒", value)
        self.timeout_field.setCurrentIndex(max(0, self.timeout_field.findData(float(self.settings.values["timeout"]))))
        form.addRow("服务器 API", self.api_field)
        form.addRow("请求超时", self.timeout_field)
        self.config_layout.addLayout(form)
        self.config_layout.addWidget(button("保存连接设置", self.save_connection, True))
        self.config_layout.addWidget(paragraph("连接失败时展示独立演示数据。真实写入超时会保留原请求键，待核对后继续。口令与登录令牌仅在本次进程内使用。"))
        self.config_layout.addStretch()

    def save_connection(self):
        if self.busy:
            return
        try:
            value = api_url(self.api_field.text())
            self.settings.save(api=value, timeout=self.timeout_field.currentData())
            self.generation += 1
            self.repo = Repository(self.settings)
            self.state = self.repo.snapshot()
            self.render_all()
            self.status_label.setText("连接设置已保存，请重新登录")
            self.refresh()
        except ApiError as error:
            self.error(error)

    def account(self):
        if self.busy:
            return
        if self.state.get("user"):
            if QMessageBox.question(self, "退出登录", "退出后会清空界面中的私人资料；待核对记录按账号保留。") == QMessageBox.StandardButton.Yes:
                self.generation += 1
                self.repo.reset()
                self.state = self.repo.snapshot()
                self.render_all()
            return
        dialog = QDialog(self)
        dialog.setWindowTitle("登录客户账号")
        dialog.setMinimumWidth(400)
        layout = QVBoxLayout(dialog)
        layout.addWidget(paragraph("请使用管理员分配的客户账号。离线时 customer 可进入独立演示。"))
        form = QFormLayout()
        account, password = QLineEdit("customer"), QLineEdit()
        password.setEchoMode(QLineEdit.EchoMode.Password)
        password.setPlaceholderText("输入客户口令")
        form.addRow("账号", account)
        form.addRow("口令", password)
        layout.addLayout(form)
        controls = QDialogButtonBox(QDialogButtonBox.StandardButton.Ok | QDialogButtonBox.StandardButton.Cancel)
        controls.accepted.connect(dialog.accept)
        controls.rejected.connect(dialog.reject)
        layout.addWidget(controls)
        if dialog.exec():
            credentials = (account.text().strip(), password.text())
            self.generation += 1
            self.run(lambda: self.repo.login(*credentials))

    def create_case(self, service):
        if self.busy:
            return
        if not self.state.get("user"):
            self.account()
            return
        dialog = QDialog(self)
        dialog.setWindowTitle("提交" + service["name"] + "需求")
        dialog.resize(620, 700)
        layout = QVBoxLayout(dialog)
        area, body = scroll_page()
        layout.addWidget(area)
        body.addWidget(paragraph("请说明真实目标和现有材料，顾问审核后提供明确报价。"))
        form = QFormLayout()
        fields = {}
        form_fields = [("title", "需求标题 *")]
        if service["id"] in ("graduation", "journal"):
            form_fields.append(("discipline", "专业 / 研究方向 *"))
        if service["id"] == "graduation":
            form_fields.append(("level", "学历 / 稿件阶段 *"))
        if service["id"] == "editing":
            form_fields.append(("language", "原文 → 目标语言 *"))
        form_fields += [("deadline", "期望日期 YYYY-MM-DD"), ("contact", "联系说明")]
        for key, label in form_fields:
            field = QLineEdit()
            field.setMaxLength(300)
            fields[key] = field
            form.addRow(label, field)
        fields["word_count"] = QSpinBox()
        fields["word_count"].setRange(0, 10_000_000)
        form.addRow("预计字数", fields["word_count"])
        fields["description"] = QTextEdit()
        fields["description"].setPlaceholderText({"graduation": "选题、进度、已有材料和需要的辅导", "journal": "目标刊物、投稿目标、稿件状态及咨询事项", "editing": "翻译 / 润色范围、术语与格式要求"}[service["id"]])
        fields["description"].setMinimumHeight(120)
        form.addRow("需求说明 *", fields["description"])
        body.addLayout(form)
        consent = QCheckBox("我确认有权提交这些材料，并同意用于本次服务评估。")
        consent.setWordWrap(True) if hasattr(consent, "setWordWrap") else None
        body.addWidget(consent)
        body.addWidget(paragraph("附件请在提交成功后的需求详情上传。服务范围、费用、交付和修改规则以确认报价为准。"))
        controls = QDialogButtonBox(QDialogButtonBox.StandardButton.Ok | QDialogButtonBox.StandardButton.Cancel)
        controls.accepted.connect(dialog.accept)
        controls.rejected.connect(dialog.reject)
        layout.addWidget(controls)
        if dialog.exec():
            data = {k: v.value() if isinstance(v, QSpinBox) else v.toPlainText().strip() if isinstance(v, QTextEdit) else v.text().strip() for k, v in fields.items()}
            data.update(service_id=service["id"], consent=consent.isChecked())
            required = {"graduation": ("title", "description", "discipline", "level"), "journal": ("title", "description", "discipline"), "editing": ("title", "description", "language")}[service["id"]]
            if any(not data.get(key) for key in required) or not data["consent"]:
                self.error(ApiError("请填写标注 * 的必填项并勾选材料授权"))
                return
            self.pages.setCurrentIndex(1)
            self.run(lambda: self.repo.mutate("/cases", data))

    def text_action(self, case, action, title, values=None):
        dialog = QDialog(self)
        dialog.setWindowTitle(title)
        dialog.resize(500, 320)
        layout = QVBoxLayout(dialog)
        text = QTextEdit()
        text.setPlaceholderText(title)
        layout.addWidget(text)
        controls = QDialogButtonBox(QDialogButtonBox.StandardButton.Ok | QDialogButtonBox.StandardButton.Cancel)
        controls.accepted.connect(dialog.accept)
        controls.rejected.connect(dialog.reject)
        layout.addWidget(controls)
        if dialog.exec() and text.toPlainText().strip():
            self.perform(case, action, {**(values or {}), "text": text.toPlainText().strip()})

    def perform(self, case, action, fields, confirm=False):
        if confirm and QMessageBox.question(self, "确认操作", "请确认已核对本版报价 / 交付 / 结算内容。继续提交？") != QMessageBox.StandardButton.Yes:
            return
        self.run(lambda: self.repo.mutate(f'/cases/{case["id"]}/actions', {"action": action, "expected_version": case["version"], **fields}))

    def upload(self, case):
        file, _ = QFileDialog.getOpenFileName(self, "选择本次服务材料")
        if file:
            self.run(lambda: self.repo.upload(case, file))

    def download(self, case, attachment):
        name = Path(str(attachment.get("name", attachment.get("filename", "附件")))).name
        destination, _ = QFileDialog.getSaveFileName(self, "保存私有附件", name)
        if destination:
            self.run(lambda: self.repo.download(case["id"], attachment["id"], destination))

    def refresh(self):
        if not self.busy:
            self.run(self.repo.refresh)

    def reconcile(self):
        self.run(self.repo.reconcile)

    def retry(self):
        if QMessageBox.question(self, "使用原请求键重试", "这将把完整原请求和原键发送到服务器核对或完成；不会生成新请求键。继续？") == QMessageBox.StandardButton.Yes:
            self.run(self.repo.retry_pending)

    def run(self, function):
        if self.busy:
            return
        self.busy = True
        self.reload_button.setEnabled(False)
        self.account_button.setEnabled(False)
        self.status_label.setText("正在请求服务器…")
        task = Task(function, self.generation)
        self.tasks.add(task)
        task.signals.finished.connect(lambda value, error, generation, job=task: self.finished(job, value, error, generation))
        self.pool.start(task)

    def finished(self, task, value, error, generation):
        self.tasks.discard(task)
        self.busy = False
        self.reload_button.setEnabled(True)
        self.account_button.setEnabled(True)
        if generation != self.generation:
            return
        self.state = self.repo.snapshot() if error else value
        self.render_all()
        if error:
            self.error(error)
        else:
            self.status_label.setText(self.state["notice"])

    def render_all(self):
        self.notice.setText(self.state["notice"])
        user = self.state.get("user")
        self.account_button.setText((user.get("name", "客户") + " · 退出") if user else "登录")
        self.render_home()
        self.render_workspace()

    def error(self, error):
        self.status_label.setText(str(error))
        if isinstance(error, UnknownWrite):
            QMessageBox.warning(self, "提交结果待核对", str(error))
        else:
            QMessageBox.information(self, "操作提示", str(error))

    def closeEvent(self, event):
        self.generation += 1
        self.refresh_timer.stop()
        self.pool.waitForDone(12_000)
        event.accept()


def main():
    parser = argparse.ArgumentParser(description="知序学术服务桌面客户端")
    parser.add_argument("--screenshot", type=Path, help="保存首屏截图后退出（验证用）")
    args = parser.parse_args()
    app = QApplication(sys.argv[:1])
    app.setApplicationName("Zhixu")
    app.setOrganizationName("Jobs")
    app.setStyle("Fusion")
    window = MainWindow()
    window.show()
    if args.screenshot:
        def capture():
            args.screenshot.parent.mkdir(parents=True, exist_ok=True)
            window.grab().save(str(args.screenshot))
            window.close()
            app.quit()
        QTimer.singleShot(3500, capture)
    return app.exec()


if __name__ == "__main__":
    raise SystemExit(main())
