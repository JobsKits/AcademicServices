"""仅对独立本机开发实例执行桌面仓库与真实Go后端的闭环验证。"""
import argparse
import json
import os
import tempfile
import uuid
from datetime import datetime, timedelta, timezone
from pathlib import Path
from urllib.parse import urlsplit

from zhixu.repository import HttpClient, Repository
from zhixu.settings import Settings


def run(base):
    if urlsplit(base).hostname not in ("127.0.0.1", "localhost"):
        raise RuntimeError("本脚本只能连接本机隔离开发实例")
    checks = []
    def check(name, value):
        if not value:
            raise AssertionError(name)
        checks.append(name)
    with tempfile.TemporaryDirectory(prefix="zhixu-desktop-live-") as folder:
        settings = Settings(folder)
        settings.save(api=base)
        repo = Repository(settings)
        state = repo.login("customer", os.getenv("DEMO_CUSTOMER_PASSWORD", "demo-customer"))
        check("真实客户登录", state["source"] == "real")
        admin = HttpClient(base)
        result = admin.request("POST", "/auth/login", {"account": "admin", "password": os.getenv("ADMIN_PASSWORD", "demo-admin-change-me")})
        admin.token = result["token"]
        check("管理员独立登录", result["user"]["role"] == "admin")
        def current(case_id):
            repo.refresh()
            return next(c for c in repo.cases if c["id"] == case_id)
        def admin_action(case_id, action, **fields):
            c = current(case_id)
            return admin.request("POST", "/cases/" + case_id + "/actions", {"action": action, "expected_version": c["version"], **fields}, key=str(uuid.uuid4()))["case"]
        def client_action(case_id, action, **fields):
            c = current(case_id)
            repo.mutate("/cases/" + case_id + "/actions", {"action": action, "expected_version": c["version"], **fields})
            return next(c for c in repo.cases if c["id"] == case_id)
        ids = []
        for service in ("graduation", "journal", "editing"):
            repo.mutate("/cases", {"service_id": service, "title": "桌面集成测试-" + uuid.uuid4().hex[:8], "description": "本人材料的服务需求", "discipline": "计算机", "level": "本科", "word_count": 5000, "language": "中文", "deadline": (datetime.now(timezone.utc) + timedelta(days=30)).strftime("%Y-%m-%d"), "contact": "测试本机", "consent": True})
            ids.append(repo.cases[0]["id"])
        check("三服务需求真实创建", len(set(ids)) == 3)
        case_id = ids[2]
        document = Path(folder) / "中文稿件.txt"
        document.write_text("This is the author's own manuscript.\n", encoding="utf-8")
        repo.upload(current(case_id), document)
        c = current(case_id)
        attachment = c["attachments"][0]
        destination = Path(folder) / "下载材料.txt"
        repo.download(case_id, attachment["id"], destination)
        check("授权上传下载内容一致", destination.read_bytes() == document.read_bytes())
        offer = admin_action(case_id, "quote", amount_minor=30000, prepay_minor=2000, scope="翻译与润色，本人稿件；两轮修改", revision_limit=2, expires_at=(datetime.now(timezone.utc)+timedelta(hours=2)).isoformat())
        c = client_action(case_id, "accept_quote", quote_id=offer["quote"]["id"])
        check("客户确认本版报价生成订单", c["order"]["status"] == "pending_start")
        admin_action(case_id, "record_payment", amount_minor=30000, reference="desktop-pay-"+uuid.uuid4().hex)
        admin_action(case_id, "start")
        admin_action(case_id, "pause", hold_id="materials", text="等待作者核对术语")
        admin_action(case_id, "resume", hold_id="materials")
        c = admin_action(case_id, "deliver", text="正式译稿第一版", attachment_ids=[attachment["id"]])
        delivery = c["order"]["deliveries"][-1]
        client_action(case_id, "revision", delivery_id=delivery["id"], text="请统一术语")
        c = current(case_id)
        admin_action(case_id, "accept_revision", feedback_id=c["order"]["feedback"][-1]["id"], round_id="round-1", count_units=1)
        c = admin_action(case_id, "deliver", text="术语已统一第二版", attachment_ids=[attachment["id"]])
        c = client_action(case_id, "accept_delivery", delivery_id=c["order"]["deliveries"][-1]["id"])
        check("交付修改受理及验收完成", c["order"]["status"] == "completed" and c["order"]["revision_used"] == 1)
        c = client_action(case_id, "after_sale", text="请核对引用格式")
        after_id = c["after_sales"][-1]["id"]
        c = admin_action(case_id, "deliver", after_sale_id=after_id, text="售后引用格式已核对", attachment_ids=[attachment["id"]])
        c = client_action(case_id, "accept_delivery", delivery_id=c["order"]["deliveries"][-1]["id"])
        c = admin_action(case_id, "close_after_sale", after_sale_id=after_id, text="用户已确认")
        check("售后分组交付独立验收", c["order"]["status"] == "completed" and c["after_sales"][-1]["status"] == "closed")
        cancel_id = ids[1]
        c = admin_action(cancel_id, "quote", amount_minor=10000, prepay_minor=0, scope="稿件服务范围", revision_limit=1, expires_at=(datetime.now(timezone.utc)+timedelta(hours=2)).isoformat())
        client_action(cancel_id, "accept_quote", quote_id=c["quote"]["id"])
        c = admin_action(cancel_id, "record_payment", amount_minor=3000, reference="desktop-cancel-pay-"+uuid.uuid4().hex)
        payment_id = c["order"]["payments"][0]["id"]
        admin_action(cancel_id, "cancel", text="双方协商最终结算", settlement_minor=1000)
        c = client_action(cancel_id, "confirm_cancel")
        check("取消结算保留原始合同", c["order"]["amount_minor"] == 1000 and c["order"]["original_amount_minor"] == 10000)
        c = admin_action(cancel_id, "refund", payment_id=payment_id, amount_minor=2000)
        refund_id = c["order"]["refunds"][-1]["id"]
        admin_action(cancel_id, "approve_refund", refund_id=refund_id)
        c = admin_action(cancel_id, "confirm_refund", refund_id=refund_id, reference="desktop-refund-"+uuid.uuid4().hex)
        check("取消后净收与最终结算相等", c["order"]["paid_minor"]-c["order"]["refunded_minor"] == c["order"]["amount_minor"] == 1000)
        c = client_action(ids[0], "withdraw_request", text="不再需要本次咨询")
        check("未成交需求撤回", c["status"] == "closed")
        check("桌面写入无残留未知记录", repo.pending is None)
    return {"passed": len(checks), "checks": checks}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--api", default="http://127.0.0.1:18082/api/v1")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    result = run(args.api)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(result, ensure_ascii=False, indent=2))
