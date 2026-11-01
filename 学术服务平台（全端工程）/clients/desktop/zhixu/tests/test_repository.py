import copy
import json
import tempfile
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from unittest.mock import patch

from zhixu.repository import ApiError, HttpClient, OfflineError, Repository, SERVICES, UnknownWrite, api_url
from zhixu.settings import Settings


def case():
    return {"id": "case-a", "owner_id": "customer", "service_id": "editing", "title": "翻译", "description": "本人稿件", "status": "pending_review", "version": 1, "order": None, "attachments": [], "messages": [], "events": [], "after_sales": []}


class FakeClient:
    def __init__(self):
        self.base = "http://127.0.0.1:8080/api/v1"
        self.token = ""
        self.calls = []
        self.mode = "real"
        self.case = case()
        self.operation = False

    def request(self, method, path, body=None, key=None, **kwargs):
        self.calls.append((method, path, copy.deepcopy(body), key))
        if self.mode == "offline":
            raise OfflineError("offline")
        if self.mode == "unauthorized":
            raise ApiError("expired", 401)
        if self.mode == "forbidden":
            raise ApiError("forbidden", 403)
        if path == "/auth/login":
            if body["password"] != "correct":
                raise ApiError("bad password", 401)
            return {"token": "secret", "user": {"id": "customer", "name": "客户", "role": "customer"}}
        if path == "/services":
            return {"services": copy.deepcopy(SERVICES)}
        if path == "/workspace":
            return {"user": {"id": "customer", "role": "customer"}, "services": copy.deepcopy(SERVICES), "cases": [copy.deepcopy(self.case)] if self.case else []}
        if path.startswith("/operations/"):
            if not self.operation:
                raise ApiError("not found", 404)
            return {"operation": {"status": "succeeded"}, "case": copy.deepcopy(self.case)}
        if method == "POST":
            self.case["version"] += 1
            self.operation = True
            if self.mode == "commit-timeout":
                raise OfflineError("timeout after commit")
            if self.mode == "reject":
                raise ApiError("invalid", 422)
            return {"case": copy.deepcopy(self.case)}
        return b"download"


class RepositoryTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.settings = Settings(self.temp.name)
        self.client = FakeClient()
        self.repo = Repository(self.settings, self.client)

    def tearDown(self):
        self.temp.cleanup()

    def login(self):
        return self.repo.login("customer", "correct")

    def test_real_login_and_empty_list_is_not_demo(self):
        self.client.case = None
        state = self.login()
        self.assertEqual(state["source"], "real")
        self.assertEqual(state["cases"], [])

    def test_bad_password_never_becomes_demo(self):
        with self.assertRaises(ApiError) as caught:
            self.repo.login("customer", "wrong")
        self.assertEqual(caught.exception.status, 401)
        self.assertIsNone(self.repo.user)

    def test_offline_login_and_demo_write_attempts_api_first(self):
        self.client.mode = "offline"
        self.repo.login("customer", "anything")
        self.repo.mutate("/cases", {"title": "示例", "description": "内容", "service_id": "editing", "consent": True})
        self.assertEqual(self.client.calls[-1][1], "/cases")
        self.assertEqual(len(self.repo.cases), 1)
        self.assertTrue(self.repo.cases[0]["id"].startswith("demo-"))
        self.assertIsNone(self.repo.pending)

    def test_other_account_cannot_use_demo(self):
        self.client.mode = "offline"
        with self.assertRaises(ApiError):
            self.repo.login("admin", "password")

    def test_read_fallback_isolates_private_cases_and_auto_recovers(self):
        self.login()
        self.client.mode = "offline"
        self.assertEqual(self.repo.refresh()["cases"], [])
        self.assertEqual(self.repo.source, "demo")
        self.client.mode = "real"
        self.assertEqual(self.repo.refresh()["cases"][0]["id"], "case-a")
        self.assertEqual(self.repo.source, "real")

    def test_private_401_revokes_and_clears_state(self):
        self.login()
        self.client.mode = "unauthorized"
        with self.assertRaises(ApiError):
            self.repo.refresh()
        self.assertEqual(self.repo.cases, [])
        self.assertEqual(self.client.token, "")
        self.assertIsNone(self.repo.user)

    def test_private_403_revokes(self):
        self.login()
        self.client.mode = "forbidden"
        with self.assertRaises(ApiError):
            self.repo.refresh()
        self.assertIsNone(self.repo.user)

    def test_wrong_owner_response_rejected(self):
        self.client.case["owner_id"] = "someone-else"
        with self.assertRaises(ApiError) as caught:
            self.login()
        self.assertEqual(caught.exception.status, 403)
        self.assertEqual(self.repo.cases, [])

    def test_malformed_case_falls_to_isolated_demo(self):
        self.client.case.pop("version")
        self.assertEqual(self.login()["source"], "demo")
        self.assertEqual(self.repo.cases, [])

    def test_nested_bad_quote_and_message_fall_back(self):
        for field, value in (("quote", {"id": "missing-fields"}), ("messages", ["bad item"]), ("order", {"id": "missing-money"})):
            with self.subTest(field=field):
                self.client.case = case()
                self.client.case[field] = value
                self.assertEqual(self.repo.login("customer", "correct")["source"], "demo")
                self.assertEqual(self.repo.cases, [])

    def test_nested_bad_service_falls_back_without_crash(self):
        self.login()
        with patch.object(self.client, "request", return_value={"user": {"id": "customer", "role": "customer"}, "cases": [], "services": [{"id": "editing"}]}):
            self.assertEqual(self.repo.refresh()["source"], "demo")

    def test_failed_auth_write_removes_definite_pending_record(self):
        self.login()
        record = self.repo.pending_path
        self.client.mode = "unauthorized"
        with self.assertRaises(ApiError):
            self.repo.mutate("/cases", {"title": "test"})
        self.assertFalse(record.exists())
        self.assertIsNone(self.repo.user)

    def test_unknown_write_keeps_key_durable_and_blocks_another(self):
        self.login()
        self.client.mode = "commit-timeout"
        with self.assertRaises(UnknownWrite):
            self.repo.mutate("/cases/case-a/actions", {"action": "message", "text": "hello", "expected_version": 1})
        pending = copy.deepcopy(self.repo.pending)
        self.assertEqual(json.loads(self.repo.pending_path.read_text())["key"], pending["key"])
        with self.assertRaises(UnknownWrite):
            self.repo.mutate("/cases", {})
        self.client.mode = "real"
        self.repo.retry_pending()
        self.assertEqual(self.client.calls[-1][3], pending["key"])
        self.assertEqual(self.client.calls[-1][2], pending["body"])
        self.assertIsNone(self.repo.pending)

    def test_committed_unknown_write_reconciles_without_replay(self):
        self.login()
        self.client.mode = "commit-timeout"
        with self.assertRaises(UnknownWrite):
            self.repo.mutate("/cases", {"title": "hello"})
        writes = sum(x[0] == "POST" for x in self.client.calls)
        self.client.mode = "real"
        self.repo.refresh()
        self.assertIsNone(self.repo.pending)
        self.assertEqual(writes, sum(x[0] == "POST" for x in self.client.calls))
        self.assertFalse(self.repo.pending_path.exists())

    def test_missing_operation_retains_pending(self):
        self.login()
        self.client.mode = "offline"
        with self.assertRaises(UnknownWrite):
            self.repo.mutate("/cases", {"title": "hello"})
        self.client.mode = "real"
        self.repo.reconcile()
        self.assertIsNotNone(self.repo.pending)
        self.assertIn("可能仍在处理", self.repo.notice)

    def test_422_is_not_demo_success(self):
        self.login()
        self.client.mode = "reject"
        with self.assertRaises(ApiError) as caught:
            self.repo.mutate("/cases", {"title": "hello"})
        self.assertEqual(caught.exception.status, 422)
        self.assertIsNone(self.repo.pending)
        self.assertEqual(self.repo.source, "real")

    def test_logout_does_not_keep_private_data(self):
        self.login()
        self.repo.reset()
        self.assertEqual(self.repo.cases, [])
        self.assertEqual(self.repo.demo_cases, [])
        self.assertIsNone(self.repo.pending)

    def test_demo_recovery_never_syncs_demo_writes(self):
        self.client.mode = "offline"
        self.repo.login("customer", "")
        self.repo.mutate("/cases", {"title": "示例", "description": "内容", "service_id": "editing", "consent": True})
        self.client.mode = "real"
        self.login()
        self.assertEqual([x["id"] for x in self.repo.cases], ["case-a"])
        self.assertEqual(self.repo.demo_cases, [])

    def test_upload_refuses_offline_before_reading_file(self):
        self.client.mode = "offline"
        self.repo.login("customer", "")
        with self.assertRaises(ApiError):
            self.repo.upload({}, Path("not-existing-secret.txt"))

    def test_settings_never_persist_credentials(self):
        self.settings.save(theme="dark")
        self.login()
        text = self.settings.path.read_text()
        self.assertNotIn("secret", text)
        self.assertNotIn("correct", text)
        self.assertEqual(Settings(self.temp.name).values["theme"], "dark")

    def test_download_auth_failure_clears_private_state(self):
        for mode in ("unauthorized", "forbidden"):
            with self.subTest(mode=mode):
                self.client.mode = "real"
                self.login()
                self.client.mode = mode
                with self.assertRaises(ApiError):
                    self.repo.download("case-a", "attachment-a", Path(self.temp.name) / "private.txt")
                self.assertIsNone(self.repo.user)
                self.assertEqual(self.repo.cases, [])
                self.assertEqual(self.client.token, "")
                self.assertFalse((Path(self.temp.name) / "private.txt").exists())

    def test_direct_reconcile_auth_failure_clears_private_state(self):
        self.login()
        self.client.mode = "commit-timeout"
        with self.assertRaises(UnknownWrite):
            self.repo.mutate("/cases", {"title": "unknown"})
        pending_path = self.repo.pending_path
        self.client.mode = "unauthorized"
        with self.assertRaises(ApiError):
            self.repo.reconcile()
        self.assertIsNone(self.repo.user)
        self.assertEqual(self.repo.cases, [])
        self.assertTrue(pending_path.exists())

    def test_upload_over_backend_limit_is_rejected_before_read_or_send(self):
        self.login()
        file = Path(self.temp.name) / "large.bin"
        with file.open("wb") as stream:
            stream.truncate(8 * 1024 * 1024 + 1)
        sent = len(self.client.calls)
        with self.assertRaisesRegex(ApiError, "8MB"), patch.object(Path, "read_bytes", side_effect=AssertionError("oversized file was read")):
            self.repo.upload(self.client.case, file)
        self.assertEqual(len(self.client.calls), sent)
        self.assertIsNone(self.repo.pending)

    def test_bad_case_description_falls_back_before_qt_render(self):
        self.client.case["description"] = {"bad": "object"}
        state = self.login()
        self.assertEqual(state["source"], "demo")
        self.assertEqual(state["cases"], [])

    def test_url_policy(self):
        self.assertEqual(api_url("http://localhost:8080"), "http://localhost:8080/api/v1")
        self.assertEqual(api_url("https://example.org/api/v1/"), "https://example.org/api/v1")
        for url in ("http://example.org", "https://user:pass@example.org", "file:///tmp/a", "https://example.org?token=a"):
            with self.subTest(url=url), self.assertRaises(ApiError):
                api_url(url)


class HttpTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.seen = []
        class Handler(BaseHTTPRequestHandler):
            def do_GET(self):
                HttpTests.seen.append((self.path, self.headers.get("Authorization")))
                code = {"/api/v1/401": 401, "/api/v1/503": 503, "/api/v1/redirect": 302}.get(self.path, 200)
                self.send_response(code)
                if code == 302:
                    self.send_header("Location", "/api/v1/secret")
                self.end_headers()
                self.wfile.write(b"not json" if self.path.endswith("bad") else b'{"ok":true,"error":{"message":"rejected"}}')
            def log_message(self, *_):
                pass
        cls.server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()
        cls.client = HttpClient(f"http://127.0.0.1:{cls.server.server_port}/api/v1")
        cls.client.token = "private-token"

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()
        cls.thread.join()

    def test_real_http_authorization_header(self):
        self.assertTrue(self.client.request("GET", "/ok")["ok"])
        self.assertEqual(self.seen[-1][1], "Bearer private-token")

    def test_real_http_401_not_offline(self):
        with self.assertRaises(ApiError) as caught:
            self.client.request("GET", "/401")
        self.assertNotIsInstance(caught.exception, OfflineError)
        self.assertEqual(caught.exception.status, 401)

    def test_real_http_503_is_offline(self):
        with self.assertRaises(OfflineError):
            self.client.request("GET", "/503")

    def test_bad_200_response_is_not_success(self):
        with self.assertRaises(OfflineError):
            self.client.request("GET", "/bad")

    def test_redirect_does_not_forward_token(self):
        before = len(self.seen)
        with self.assertRaises(ApiError) as caught:
            self.client.request("GET", "/redirect")
        self.assertEqual(caught.exception.status, 302)
        self.assertEqual(len(self.seen), before + 1)


if __name__ == "__main__":
    unittest.main()
