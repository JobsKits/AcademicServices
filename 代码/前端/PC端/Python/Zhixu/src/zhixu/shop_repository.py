"""商城数据仓库：每次先请求API，演示数据与真实订单保持隔离。"""
import copy
import uuid
from datetime import datetime, timezone

from .repository import ApiError, HttpClient, OfflineError, UnknownWrite


def stamp():
    return datetime.now(timezone.utc).isoformat()


def demo_products():
    rows = [
        ("graduation-outline", "graduation", "论文提纲", 49800, "course"),
        ("graduation-proposal", "graduation", "开题指导报告课", 1, "course"),
        ("graduation-mentoring", "graduation", "毕业论文一对一", 5000, "service"),
        ("journal-submission", "journal", "审测投稿", 9900, "service"),
        ("journal-mentoring", "journal", "普刊论文一对一", 20000, "service"),
        ("journal-assessment", "journal", "论文专业测评", 60000, "service"),
        ("journal-training", "journal", "普刊训练营", 219900, "course"),
        ("editing-translation", "editing", "学术翻译", 19900, "service"),
        ("editing-polish", "editing", "学术润色", 15900, "service"),
    ]
    return [dict(id=pid, category_id=cat, name=name, price_minor=price,
                 kind=kind, currency="CNY", active=True, in_stock=True,
                 image="", version=1, is_demo=True, summary=name,
                 description="课程与服务内容可在后台编辑；当前为演示商品。",
                 sections=[]) for pid, cat, name, price, kind in rows]


class ShopRepository:
    def __init__(self, settings, client=None):
        self.settings = settings
        self.client = client or HttpClient(settings.values["api"], settings.values["timeout"])
        self.user = None
        self.live_session = False
        self.source = "demo"
        self.products = demo_products()
        self.orders = []
        self.demo_orders = []
        self.pending = {}
        self.pending_request = None
        self.receipts = {}

    def _request(self, method, path, body=None, key=None):
        try:
            return self.client.request(method, path, body, key)
        except ApiError as error:
            # A missing commerce resource uses the same isolated demo fallback as an outage.
            if error.status == 404:
                raise OfflineError(str(error), 404) from error
            if error.status in (401, 403):
                self.logout()
            raise

    def login(self, account, password):
        self.client.token = ""
        self.user = None
        self.live_session = False
        self.orders = []
        self.demo_orders = []
        self.pending.clear()
        self.pending_request = None
        self.receipts.clear()
        try:
            result = self._request("POST", "/auth/login", {"account": account, "password": password})
            if not isinstance(result.get("token"), str) or not isinstance(result.get("user"), dict):
                raise OfflineError("Invalid login response")
            if result["user"].get("role") != "customer":
                raise ApiError("Customer account required", 403)
            self.client.token = result["token"]
            self.user = result["user"]
            self.live_session = True
        except OfflineError:
            if account != "customer":
                raise ApiError("Offline sample account: customer")
            self.user = {"id": "demo-customer", "role": "customer"}
        return self.refresh()

    def logout(self):
        self.client.token = ""
        self.user = None
        self.live_session = False
        self.orders = []
        self.demo_orders = []
        self.pending.clear()
        self.pending_request = None
        self.receipts.clear()

    @staticmethod
    def _products(value):
        items = value.get("products")
        if not isinstance(items, list):
            raise OfflineError("Invalid product list")
        for item in items:
            if (not isinstance(item, dict) or not isinstance(item.get("id"), str)
                    or not isinstance(item.get("name"), str)
                    or type(item.get("price_minor")) is not int
                    or type(item.get("version")) is not int
                    or type(item.get("active")) is not bool
                    or type(item.get("in_stock")) is not bool
                    or item.get("category_id") not in ("graduation", "journal", "editing")
                    or item.get("kind") not in ("course", "service")
                    or not all(isinstance(item.get(k, ""), str) for k in ("description", "summary", "image"))
                    or not isinstance(item.get("sections", []), list)):
                raise OfflineError("Invalid product")
            if any(not isinstance(s, dict) or not all(isinstance(s.get(k), str) for k in ("title", "body")) for s in item.get("sections", [])):
                raise OfflineError("Invalid product sections")
        return items

    @classmethod
    def _order(cls, value, owner_id):
        if (not isinstance(value, dict) or not isinstance(value.get("id"), str)
                or value.get("owner_id") != owner_id
                or value.get("status") not in ("pending_payment", "pending_completion", "pending_review", "completed", "cancelled")
                or value.get("fulfillment_status") not in ("pending", "in_progress", "delivered")
                or type(value.get("amount_minor")) is not int or type(value.get("version")) is not int):
            raise OfflineError("Invalid order")
        cls._products({"products": [value.get("product_snapshot")]})
        for name in ("payment", "review"):
            if value.get(name) is not None and not isinstance(value[name], dict):
                raise OfflineError("Invalid order detail")
        if not isinstance(value.get("delivery_text", ""), str):
            raise OfflineError("Invalid delivery text")
        payment = value.get("payment")
        if payment and (payment.get("channel") not in ("alipay", "wechat") or payment.get("mode") != "mock"):
            raise OfflineError("Invalid payment")
        review = value.get("review")
        if review and (type(review.get("rating")) is not int or not isinstance(review.get("text"), str)):
            raise OfflineError("Invalid review")
        return value

    def refresh(self):
        try:
            products = self._products(self._request("GET", "/products"))
            orders = []
            if self.live_session:
                value = self._request("GET", "/shop-orders")
                orders = value.get("orders")
                if not isinstance(orders, list) or any(not isinstance(x, dict) or x.get("owner_id") != self.user["id"] for x in orders):
                    raise OfflineError("Invalid order list")
                for order in orders:
                    self._order(order, self.user["id"])
            self.products = copy.deepcopy(products)
            self.orders = copy.deepcopy(orders)
            self.source = "live"
        except OfflineError:
            self.source = "demo"
            self.orders = copy.deepcopy(self.demo_orders)
        return self.snapshot()

    def snapshot(self):
        return copy.deepcopy(dict(products=self.products, orders=self.orders, source=self.source, user=self.user))

    def write(self, path, body, operation=None):
        if not self.user:
            raise ApiError("Login required", 401)
        signature = operation or (path, repr(body))
        if self.pending_request and (path != self.pending_request["path"] or body != self.pending_request["body"]):
            raise UnknownWrite("操作结果待确认，请先核对或重试原请求")
        key = self.pending.setdefault(signature, "desktop-shop-" + uuid.uuid4().hex)
        try:
            result = self._request("POST", path, body, key)
            order = result.get("order")
            self._order(order, self.user["id"])
            self.pending.pop(signature, None)
            self.pending_request = None
            self.source = "live"
        except OfflineError:
            # A timeout can follow a committed server write. Keep the same key for retry.
            if self.live_session:
                self.pending_request = dict(path=path, body=copy.deepcopy(body), key=key)
                raise UnknownWrite("操作结果待确认，请先核对或重试原请求")
            order = self.receipts.get(key)
            if order is None:
                order = self._demo_write(path, body)
                self.receipts[key] = copy.deepcopy(order)
            self.source = "demo"
        self.orders = [copy.deepcopy(order)] + [x for x in self.orders if x["id"] != order["id"]]
        return copy.deepcopy(order)

    def reconcile(self):
        pending = self.pending_request
        if not pending:
            return self.snapshot()
        try:
            result = self._request("GET", "/shop-operations/" + pending["key"])
        except OfflineError as error:
            raise UnknownWrite("操作结果待确认，请稍后核对或重试原请求") from error
        order = self._order(result.get("order"), self.user["id"])
        self.pending_request = None
        self.pending.clear()
        self.orders = [copy.deepcopy(order)] + [x for x in self.orders if x["id"] != order["id"]]
        self.source = "live"
        return self.snapshot()

    def retry(self):
        pending = self.pending_request
        if pending:
            self.write(pending["path"], pending["body"])
        return self.snapshot()

    def buy(self, product):
        return self.write("/shop-orders", {"product_id": product["id"], "product_version": product["version"]})

    def action(self, order, action, **fields):
        if order["id"].startswith("demo-"):
            body = dict(action=action, expected_version=order["version"], **fields)
            # Still try the API; an isolated sample can never become a real server order.
            try:
                self._request("POST", "/shop-orders/" + order["id"] + "/actions", body, "sample-" + uuid.uuid4().hex)
            except ApiError:
                pass
            result = self._demo_write("/shop-orders/" + order["id"] + "/actions", body)
            self.orders = copy.deepcopy(self.demo_orders)
            self.source = "demo"
            return result
        return self.write("/shop-orders/" + order["id"] + "/actions", dict(action=action, expected_version=order["version"], **fields))

    def _demo_write(self, path, body):
        if path == "/shop-orders":
            product = next((x for x in self.products if x["id"] == body["product_id"]), None)
            if not product or not product["active"] or not product["in_stock"] or product["version"] != body["product_version"]:
                raise ApiError("Unavailable product")
            order = dict(id="demo-" + uuid.uuid4().hex[:12], owner_id=self.user["id"],
                         product_snapshot=copy.deepcopy(product), amount_minor=product["price_minor"],
                         currency="CNY", quantity=1, status="pending_payment", fulfillment_status="pending",
                         version=1, created_at=stamp())
            self.demo_orders.insert(0, order)
            return copy.deepcopy(order)
        oid = path.split("/")[2]
        order = next((x for x in self.demo_orders if x["id"] == oid), None)
        if not order:
            raise ApiError("Reconnect and reload the real order before retrying")
        if order["version"] != body["expected_version"]:
            raise ApiError("Order version conflict")
        action = body["action"]
        if action == "pay" and order["status"] == "pending_payment" and body.get("channel") in ("alipay", "wechat"):
            order.update(status="pending_completion", paid_at=stamp(), payment=dict(mode="mock", channel=body["channel"], status="succeeded", amount_minor=order["amount_minor"]))
        elif action == "cancel" and order["status"] == "pending_payment":
            order["status"] = "cancelled"
        elif action == "accept" and order["status"] == "pending_completion" and order["fulfillment_status"] == "delivered":
            order["status"] = "pending_review"
        elif action == "review" and order["status"] == "pending_review" and 1 <= body.get("rating", 0) <= 5 and body.get("text", "").strip():
            order.update(status="completed", review=dict(rating=body["rating"], text=body["text"]), completed_at=stamp())
        else:
            raise ApiError("Action unavailable")
        order["version"] += 1
        return copy.deepcopy(order)
