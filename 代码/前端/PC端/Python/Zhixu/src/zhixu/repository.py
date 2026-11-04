"""HTTP 与隔离演示仓库；未知真实写入只能核对或携原键重试。"""
import copy
import hashlib
import json
import mimetypes
import socket
import uuid
from datetime import datetime, timezone
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import quote, urlsplit
from urllib.request import Request, urlopen

SERVICES = [
    {"id": "graduation", "name": "毕业论文", "summary": "选题、结构与写作辅导", "description": "提交学习目标与现有材料，确认辅导范围、时间和交付后再开始。", "active": True},
    {"id": "journal", "name": "普刊", "summary": "期刊咨询与稿件服务", "description": "说明学科、目标和稿件状态，由顾问明确服务与第三方费用。", "active": True},
    {"id": "editing", "name": "编译", "summary": "学术翻译与语言润色", "description": "说明原文语言、目标语言、篇幅和术语要求，服务以确认报价为准。", "active": True},
]
STATUS = {"pending_review": "待审核", "awaiting_material": "待补材料", "awaiting_quote_accept": "待确认报价", "converted": "已转订单", "closed": "已关闭", "pending_start": "待开始", "in_service": "服务中", "awaiting_acceptance": "待验收", "revising": "修改中", "completed": "已完成", "cancelled": "已取消"}


class ApiError(Exception):
    def __init__(self, message, status=0, code=""):
        super().__init__(message)
        self.status = status
        self.code = code


class OfflineError(ApiError):
    pass


class UnknownWrite(ApiError):
    pass


def now():
    return datetime.now(timezone.utc).isoformat()


def api_url(value):
    value = value.strip().rstrip("/")
    parsed = urlsplit(value)
    if parsed.username or parsed.password or parsed.query or parsed.fragment:
        raise ApiError("服务器地址不能包含账号、查询参数或片段")
    if parsed.scheme not in ("http", "https") or not parsed.hostname:
        raise ApiError("请输入完整 http:// 或 https:// 服务器地址")
    if parsed.scheme == "http" and parsed.hostname not in ("127.0.0.1", "localhost", "::1"):
        raise ApiError("远程服务器请使用 HTTPS；HTTP 仅用于本机调试")
    if not parsed.path.endswith("/api/v1"):
        value += "/api/v1"
    return value


class HttpClient:
    def __init__(self, base, timeout=2.5):
        self.base = api_url(base)
        self.timeout = float(timeout)
        self.token = ""

    def request(self, method, path, body=None, key=None, raw=False, content_type=None):
        from urllib.request import HTTPRedirectHandler, build_opener
        class RedirectBlocked(HTTPRedirectHandler):
            def redirect_request(self, req, fp, code, msg, headers, newurl):
                return None
        headers = {"Accept": "application/json"}
        if self.token:
            headers["Authorization"] = "Bearer " + self.token
        if key:
            headers["Idempotency-Key"] = key
        if body is not None:
            headers["Content-Type"] = content_type or "application/json"
        payload = body if isinstance(body, bytes) else (json.dumps(body, ensure_ascii=False, separators=(",", ":")).encode() if body is not None else None)
        request = Request(self.base + path, data=payload, headers=headers, method=method)
        try:
            with build_opener(RedirectBlocked).open(request, timeout=self.timeout) as response:
                data = response.read(25 * 1024 * 1024 + 1)
                if len(data) > 25 * 1024 * 1024:
                    raise ApiError("服务器返回内容超过客户端限制")
                if raw:
                    return data
                try:
                    value = json.loads(data)
                    if not isinstance(value, dict):
                        raise ValueError()
                    return value
                except (ValueError, UnicodeDecodeError) as error:
                    raise OfflineError("服务器响应无法解析，请稍后重载") from error
        except HTTPError as error:
            message = f"服务器返回 {error.code}"
            code = ""
            try:
                content = json.loads(error.read(64 * 1024))
                message = str(content["error"]["message"])
                code = str(content["error"].get("code", ""))
            except (ValueError, KeyError, TypeError):
                pass
            finally:
                error.close()
            if error.code >= 500:
                raise OfflineError(message, error.code, code) from error
            raise ApiError(message, error.code, code) from error
        except (URLError, socket.timeout, TimeoutError, OSError) as error:
            raise OfflineError("暂时无法连接服务器") from error


def valid_case(case):
    if not isinstance(case, dict) or not all(isinstance(case.get(k), str) for k in ("id", "owner_id", "service_id", "title", "description", "status")):
        raise OfflineError("服务器需求数据格式不完整")
    for field in ("discipline", "level", "language", "deadline", "contact", "created_at", "updated_at"):
        if field in case and not isinstance(case[field], str):
            raise OfflineError("服务器需求文字格式不正确")
    if type(case.get("version")) is not int or case["version"] < 1:
        raise OfflineError("服务器需求版本不正确")
    for k in ("attachments", "messages", "events", "after_sales"):
        if case.get(k) is not None and not isinstance(case[k], list):
            raise OfflineError("服务器列表数据不正确")
    if case.get("order") is not None and not isinstance(case["order"], dict):
        raise OfflineError("服务器订单数据不正确")
    for field in ("attachments", "messages", "events", "after_sales"):
        for item in case.get(field) or []:
            if not isinstance(item, dict) or not isinstance(item.get("id"), str):
                raise OfflineError("服务器明细数据不完整")
            for text in ("name", "text", "status", "created_at", "author_name", "action", "type"):
                if text in item and not isinstance(item[text], str):
                    raise OfflineError("服务器明细文字格式不正确")
    offer = case.get("quote")
    if offer is not None:
        if not isinstance(offer, dict) or not all(isinstance(offer.get(k), str) for k in ("id", "scope", "status", "expires_at")):
            raise OfflineError("服务器报价数据不完整")
        for k in ("amount_minor", "prepay_minor", "revision_limit"):
            if type(offer.get(k)) is not int or offer[k] < 0:
                raise OfflineError("服务器报价金额或修改额度不正确")
    order = case.get("order")
    if order is not None:
        if not all(isinstance(order.get(k), str) for k in ("id", "status")):
            raise OfflineError("服务器订单标识不完整")
        for k in ("amount_minor", "original_amount_minor", "prepay_minor", "paid_minor", "refunded_minor", "refund_held_minor", "revision_used", "revision_limit"):
            if type(order.get(k)) is not int or order[k] < 0:
                raise OfflineError("服务器订单金额或修改额度不正确")
        for field in ("deliveries", "payments", "refunds", "feedback", "holds", "changes"):
            items = order.get(field) or []
            if not isinstance(items, list) or not all(isinstance(x, dict) and isinstance(x.get("id"), str) for x in items):
                raise OfflineError("服务器订单明细数据不正确")
        if order.get("cancellation") is not None and not isinstance(order["cancellation"], dict):
            raise OfflineError("服务器取消结算数据不正确")
    return case


def valid_services(services):
    if not isinstance(services, list):
        raise OfflineError("服务目录格式不正确")
    seen = set()
    for service in services:
        if not isinstance(service, dict) or service.get("id") not in ("graduation", "journal", "editing") or service["id"] in seen:
            raise OfflineError("服务目录分类不正确")
        if not all(isinstance(service.get(k), str) for k in ("name", "summary", "description")) or type(service.get("active")) is not bool:
            raise OfflineError("服务目录内容不完整")
        seen.add(service["id"])
    return services


class Repository:
    def __init__(self, settings, client=None):
        self.settings = settings
        self.client = client or HttpClient(settings.values["api"], settings.values["timeout"])
        self.user = None
        self.real_session = False
        self.source = "demo"
        self.notice = "本地演示 · 示例资料不会上传到服务器"
        self.services = copy.deepcopy(SERVICES)
        self.cases = []
        self.demo_cases = []
        self.pending = None
        self.pending_path = None

    def snapshot(self):
        return copy.deepcopy({"user": self.user, "source": self.source, "notice": self.notice, "services": self.services, "cases": self.cases, "pending": self.pending, "real_session": self.real_session})

    def reset(self):
        self.client.token = ""
        self.user = None
        self.real_session = False
        self.cases = []
        self.demo_cases = []
        self.pending = None
        self.pending_path = None
        self.source = "demo"

    def login(self, account, password):
        self.reset()
        try:
            result = self.client.request("POST", "/auth/login", {"account": account, "password": password})
            user, token = result.get("user"), result.get("token")
            if not isinstance(user, dict) or not isinstance(token, str) or not token or user.get("role") != "customer" or not isinstance(user.get("id"), str):
                raise ApiError("请使用客户账号登录桌面用户端")
            self.client.token, self.user, self.real_session = token, user, True
            self.source = "real"
        except OfflineError:
            if account != "customer":
                raise ApiError("离线演示仅提供 customer 样例账号")
            self.user = {"id": "demo-customer", "name": "演示客户", "role": "customer"}
            self.source = "demo"
            self.notice = "本地演示 · 网络恢复后重新登录可进入真实账号，样例不会同步"
        scope = hashlib.sha256((self.client.base + "|" + self.user["id"]).encode()).hexdigest()
        self.pending_path = self.settings.root / ("pending-" + scope + ".json")
        if self.real_session and self.pending_path.exists():
            try:
                self.pending = json.loads(self.pending_path.read_text(encoding="utf-8"))
            except (ValueError, OSError):
                raise ApiError("待核对记录损坏，请保留本地记录并联系管理员")
        return self.refresh()

    def refresh(self):
        try:
            if self.real_session:
                value = self.client.request("GET", "/workspace")
                identity = value.get("user", {})
                if identity.get("id") != self.user["id"] or identity.get("role") != "customer":
                    self.reset()
                    raise ApiError("会话身份变化，请重新登录", 401)
                cases, services = value.get("cases"), value.get("services")
                if not isinstance(cases, list) or not isinstance(services, list):
                    raise OfflineError("服务器工作台格式不正确")
                valid_services(services)
                for case in cases:
                    valid_case(case)
                    if case["owner_id"] != self.user["id"]:
                        raise ApiError("服务器返回了不属于当前账号的资料", 403)
                self.cases, self.services = cases, services
                self.source, self.notice = "real", "已连接服务器 · 真实业务资料"
                if self.pending:
                    self.reconcile()
            else:
                value = self.client.request("GET", "/services")
                services = value.get("services")
                valid_services(services)
                self.services = services
                self.notice = "服务器已连接 · 请重新登录后使用真实业务，演示资料不会同步"
                self.cases = copy.deepcopy(self.demo_cases)
            return self.snapshot()
        except ApiError as error:
            if error.status in (401, 403):
                self.reset()
                raise
            if not isinstance(error, OfflineError):
                raise
            self.source = "demo"
            self.cases = copy.deepcopy(self.demo_cases)
            self.notice = "本地演示 · 服务器不可用；真实写入待核对" if self.pending else "本地演示 · 示例资料不会上传到服务器"
            return self.snapshot()

    def _save_pending(self):
        if self.pending_path:
            if self.pending:
                self.settings.write_json(self.pending_path, self.pending)
            else:
                self.pending_path.unlink(missing_ok=True)

    def _replace(self, case):
        valid_case(case)
        if case["owner_id"] != self.user["id"]:
            raise ApiError("响应账号与当前账号不一致", 403)
        self.cases = [case] + [x for x in self.cases if x["id"] != case["id"]]
        self.source, self.notice = "real", "已保存到服务器"

    def reconcile(self):
        if not self.pending:
            return self.snapshot()
        try:
            result = self.client.request("GET", "/operations/" + quote(self.pending["key"], safe=""))
        except ApiError as error:
            if error.status in (401, 403):
                self.reset()
                raise
            if error.status == 404:
                self.notice = "尚未查到该操作；可能仍在处理中，可稍后核对或用原键重试"
                return self.snapshot()
            raise
        if result.get("operation", {}).get("status") == "succeeded":
            self._replace(result.get("case"))
            self.pending = None
            self._save_pending()
            self.notice = "原操作已在服务器完成，已核对最新资料"
        return self.snapshot()

    def retry_pending(self):
        if not self.pending:
            return self.snapshot()
        operation = copy.deepcopy(self.pending)
        return self._send(operation)

    def _send(self, operation):
        self.pending = operation
        self._save_pending()
        try:
            body = operation["body"]
            content_type = None
            if operation.get("upload"):
                body = bytes.fromhex(body)
                content_type = operation["content_type"]
            result = self.client.request("POST", operation["path"], body, key=operation["key"], content_type=content_type)
            self._replace(result.get("case"))
            self.pending = None
            self._save_pending()
            return self.snapshot()
        except OfflineError as error:
            raise UnknownWrite("提交结果待核对。请重载核对；重试时将保留原请求键，不能当作未提交。") from error
        except ApiError as error:
            if error.status and error.status < 500:
                self.pending = None
                self._save_pending()
            if error.status in (401, 403):
                self.reset()
            raise

    def mutate(self, path, body):
        if not self.user:
            raise ApiError("请先登录")
        if self.pending:
            raise UnknownWrite("上一笔真实写入尚待核对，请先处理待核对记录")
        operation = {"path": path, "body": body, "key": str(uuid.uuid4()), "created_at": now()}
        if self.real_session:
            if self.source != "real" and path != "/cases":
                raise ApiError("当前为样例资料，重载真实资料后才能处理真实订单")
            return self._send(operation)
        try:
            self.client.request("POST", path, body, key=operation["key"])
            raise ApiError("服务器已恢复，请先重新登录")
        except OfflineError:
            self._demo_mutate(path, body)
            self.source, self.notice = "demo", "本地演示操作已保存到本次会话；不会上传"
            self.cases = copy.deepcopy(self.demo_cases)
            return self.snapshot()
        except ApiError as error:
            if error.status == 401:
                raise ApiError("服务器已恢复，请重新登录真实账号", 401) from error
            raise

    def _demo_mutate(self, path, body):
        if path == "/cases":
            if not body.get("consent") or not str(body.get("title", "")).strip() or not str(body.get("description", "")).strip():
                raise ApiError("请填写标题、需求说明并确认授权")
            item = {**copy.deepcopy(body), "id": "demo-" + str(uuid.uuid4()), "owner_id": self.user["id"], "status": "pending_review", "version": 1, "created_at": now(), "updated_at": now(), "quote": None, "order": None, "attachments": [], "events": [], "messages": [], "after_sales": []}
            self.demo_cases.insert(0, item)
            return
        case_id = path.split("/")[2]
        item = next((x for x in self.demo_cases if x["id"] == case_id), None)
        if not item:
            raise ApiError("样例资料不存在")
        if body.get("expected_version") != item["version"]:
            raise ApiError("样例版本变化，请重载")
        action = body["action"]
        if action in ("message", "supplement"):
            if not body.get("text", "").strip():
                raise ApiError("内容不能为空")
            item["messages"].append({"text": body["text"], "created_at": now(), "author_name": "演示客户"})
            if action == "supplement" and item["status"] == "awaiting_material":
                item["status"] = "pending_review"
        elif action == "after_sale" and (item.get("order") or {}).get("status") == "completed":
            item["after_sales"].append({"id": str(uuid.uuid4()), "text": body.get("text"), "status": "open"})
        else:
            raise ApiError("离线演示支持需求提交、留言与补充材料；报价、资金及验收请连接服务器")
        item["version"] += 1
        item["updated_at"] = now()

    def upload(self, case, file):
        if not self.real_session or self.source != "real":
            raise ApiError("附件仅在真实登录与连接时上传，样例不会读取或上传本地文件")
        if self.pending:
            raise UnknownWrite("请先核对上一次写入")
        file = Path(file)
        if file.stat().st_size > 8 * 1024 * 1024:
            raise ApiError("附件不能超过8MB")
        boundary = "zhixu-" + uuid.uuid4().hex
        name = file.name.replace('"', "_").replace("\r", "_").replace("\n", "_")
        mime = mimetypes.guess_type(file.name)[0] or "application/octet-stream"
        data = (f'--{boundary}\r\nContent-Disposition: form-data; name="expected_version"\r\n\r\n{case["version"]}\r\n--{boundary}\r\nContent-Disposition: form-data; name="file"; filename="{name}"\r\nContent-Type: {mime}\r\n\r\n').encode() + file.read_bytes() + f"\r\n--{boundary}--\r\n".encode()
        return self._send({"path": f'/cases/{quote(case["id"], safe="")}/attachments', "body": data.hex(), "upload": True, "content_type": "multipart/form-data; boundary=" + boundary, "key": str(uuid.uuid4()), "created_at": now()})

    def download(self, case_id, attachment_id, destination):
        if not self.real_session or self.source != "real":
            raise ApiError("请连接服务器下载附件")
        try:
            data = self.client.request("GET", f"/cases/{quote(case_id, safe='')}/attachments/{quote(attachment_id, safe='')}", raw=True)
        except ApiError as error:
            if error.status in (401, 403):
                self.reset()
            raise
        path = Path(destination)
        if path.exists():
            raise ApiError("目标文件已存在，请换一个新文件名")
        with path.open("xb") as stream:
            stream.write(data)
        return self.snapshot()
