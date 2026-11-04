"""Real Go process regression. GO_BIN can point at a portable Go executable."""
from __future__ import annotations
import concurrent.futures
import contextlib
import datetime as dt
import json
import os
from pathlib import Path
import shutil
import signal
import socket
import subprocess
import tempfile
import time
import unittest
import urllib.error
import urllib.request
import uuid

ROOT = next(parent for parent in Path(__file__).resolve().parents if (parent / '代码').is_dir() and (parent / '测试').is_dir())

class HTTPRegression(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory(prefix='zhixu-http-')
        cls.runtime = Path(cls.tmp.name)
        cls.binary = cls.runtime / ('server.exe' if os.name == 'nt' else 'server')
        go = os.environ.get('GO_BIN') or shutil.which('go')
        if not go:
            raise RuntimeError('Set GO_BIN to a working Go SDK; no tests were run.')
        subprocess.run([go, 'build', '-trimpath', '-o', str(cls.binary), './cmd/server'], cwd=ROOT/'代码/后端/后端代码', check=True)
        with contextlib.closing(socket.socket()) as sock:
            sock.bind(('127.0.0.1',0)); cls.port = sock.getsockname()[1]
        cls.base = f'http://127.0.0.1:{cls.port}/api/v1'
        cls.log = (cls.runtime/'server.log').open('wb')
        cls.env = {**os.environ, 'APP_ENV':'test', 'LISTEN_ADDR':f'127.0.0.1:{cls.port}', 'DATA_DIR':str(cls.runtime/'data'), 'DATABASE_URL':'', 'CORS_ORIGINS':'', 'ADMIN_PASSWORD':'demo-admin-change-me', 'DEMO_CUSTOMER_PASSWORD':'demo-customer'}
        cls.start()
    @classmethod
    def start(cls):
        cls.proc = subprocess.Popen([str(cls.binary)],env=cls.env,stdout=cls.log,stderr=subprocess.STDOUT)
        for _ in range(100):
            if cls.proc.poll() is not None: raise RuntimeError('server failed to start; '+(cls.runtime/'server.log').read_text())
            try:
                urllib.request.urlopen(cls.base+'/health',timeout=.2).close(); break
            except (OSError,urllib.error.URLError): time.sleep(.05)
        else: raise RuntimeError('server readiness timeout')
    @classmethod
    def stop(cls):
        cls.proc.send_signal(signal.SIGINT)
        try: cls.proc.wait(timeout=5)
        except subprocess.TimeoutExpired: cls.proc.kill(); cls.proc.wait(); raise
    @classmethod
    def tearDownClass(cls):
        cls.stop(); cls.log.close(); cls.tmp.cleanup()
    def setUp(self):
        if not hasattr(type(self), '_tokens'):
            type(self)._tokens=(self.login('customer','demo-customer'),self.login('customer2','demo-customer'),self.login('admin','demo-admin-change-me'))
        self.customer,self.other,self.admin=type(self)._tokens
    def req(self,path,token=None,body=None,*,key=None,expected=200,raw=False):
        data=body if raw else (json.dumps(body,ensure_ascii=False).encode() if body is not None else None)
        headers={'Content-Type':'application/json'}
        if token: headers['Authorization']='Bearer '+token
        if body is not None: headers['Idempotency-Key']=key or str(uuid.uuid4())
        if raw: headers['Content-Type']='multipart/form-data; boundary=zhixu-test-boundary'
        request=urllib.request.Request(self.base+path,data=data,headers=headers)
        try:
            with urllib.request.urlopen(request,timeout=8) as r: code,payload=r.status,r.read()
        except urllib.error.HTTPError as e:
            with e: code,payload=e.code,e.read()
        allowed=(200,201) if expected==200 and (path=='/cases' or raw) else (expected,)
        self.assertIn(code,allowed, f'{path}: {payload[:500]!r}')
        if not payload:return None
        try:return json.loads(payload)
        except (json.JSONDecodeError,UnicodeDecodeError):return payload
    def login(self,account,password):return self.req('/auth/login',body={'account':account,'password':password})['token']
    def new(self,**extra):
        return self.req('/cases',self.customer,{'service_id':'graduation','title':'结构与方法咨询','description':'本人稿件整理与方法辅导','discipline':'计算机','level':'本科','consent':True,**extra})['case']
    def act(self,c,action,token=None,expected=200,**fields):
        result=self.req('/cases/'+c['id']+'/actions',token or self.admin,{'action':action,'expected_version':c['version'],**fields},expected=expected)
        return result['case'] if expected==200 else result
    def ordered(self,amount=100000,prepay=0,rounds=2):
        c=self.new(); c=self.act(c,'quote',amount_minor=amount,prepay_minor=prepay,scope='方法辅导与格式整理，修改轮次与交付明确',expires_at=(dt.datetime.now(dt.timezone.utc)+dt.timedelta(days=1)).isoformat(),revision_limit=rounds)
        return self.act(c,'accept_quote',self.customer,quote_id=c['quote']['id'])
    def upload(self,c):
        body=(f'--zhixu-test-boundary\r\nContent-Disposition: form-data; name="expected_version"\r\n\r\n{c["version"]}\r\n--zhixu-test-boundary\r\nContent-Disposition: form-data; name="file"; filename="material.txt"\r\nContent-Type: text/plain\r\n\r\nprivate document\r\n--zhixu-test-boundary--\r\n').encode()
        return self.req('/cases/'+c['id']+'/attachments',self.customer,body,raw=True)['case']
    def test_01_three_services_and_empty_lists(self):
        r=self.req('/services'); self.assertEqual([s['id'] for s in r['services']],['graduation','journal','editing'])
        self.assertIsInstance(self.req('/workspace',self.customer)['cases'],list)
    def test_02_auth_and_validation(self):
        self.req('/workspace',expected=401)
        self.req('/auth/login',body={'account':'customer','password':'wrong'},expected=401)
        self.req('/cases',self.customer,{'service_id':'editing','title':'翻译','description':'本人稿件','consent':True},expected=422)
    def test_03_stable_idempotency(self):
        key=str(uuid.uuid4()); body={'service_id':'editing','title':'翻译','description':'本人材料','language':'中文→英文','consent':True}
        a=self.req('/cases',self.customer,body,key=key)['case']; b=self.req('/cases',self.customer,body,key=key)['case']; self.assertEqual(a['id'],b['id'])
        self.req('/cases',self.customer,{**body,'title':'不同正文'},key=key,expected=409)
        self.assertEqual(self.req('/operations/'+key,self.customer)['case']['id'],a['id'])
        self.req('/operations/'+key,self.other,expected=404)
    def test_04_ownership_and_staff_authority(self):
        c=self.new();self.req('/cases/'+c['id'],self.other,expected=404)
        self.act(c,'need_material',self.customer,text='越权',expected=403)
    def test_05_concurrent_acceptance(self):
        c=self.new();c=self.act(c,'quote',amount_minor=10000,prepay_minor=0,revision_limit=2,scope='明确服务',expires_at=(dt.datetime.now(dt.timezone.utc)+dt.timedelta(hours=1)).isoformat())
        body={'action':'accept_quote','expected_version':c['version'],'quote_id':c['quote']['id']}
        def send(_):
            data=json.dumps(body).encode();req=urllib.request.Request(self.base+'/cases/'+c['id']+'/actions',data=data,headers={'Content-Type':'application/json','Authorization':'Bearer '+self.customer,'Idempotency-Key':str(uuid.uuid4())})
            try:
                with urllib.request.urlopen(req,timeout=10) as r:return r.status
            except urllib.error.HTTPError as e:
                with e:return e.code
        with concurrent.futures.ThreadPoolExecutor(2) as pool:codes=list(pool.map(send,range(2)))
        self.assertEqual(sorted(codes),[200,409])
    def test_06_version_and_receipt_replay(self):
        c=self.new();key=str(uuid.uuid4()); body={'action':'message','expected_version':c['version'],'text':'同一条消息'}
        a=self.req('/cases/'+c['id']+'/actions',self.customer,body,key=key)['case']; b=self.req('/cases/'+c['id']+'/actions',self.customer,body,key=key)['case']
        self.assertEqual(a['version'],b['version']);self.assertEqual(len(a['messages']),1)
        self.act(c,'message',self.customer,text='旧版本',expected=409)
    def test_07_private_attachment_gateway(self):
        c=self.upload(self.new()); fid=c['attachments'][0]['id'];path='/cases/'+c['id']+'/attachments/'+fid
        self.assertEqual(self.req(path,self.customer),b'private document');self.req(path,self.other,expected=404);self.req(path,expected=401)
    def test_08_prepayment_and_multiple_holds(self):
        c=self.ordered(prepay=30000);self.act(c,'start',expected=409)
        c=self.act(c,'record_payment',amount_minor=30000,reference=str(uuid.uuid4()))
        c=self.act(c,'pause',hold_id='materials',text='等待本人材料');c=self.act(c,'pause',hold_id='scope',text='待确认范围')
        c=self.act(c,'resume',hold_id='materials');self.assertTrue(c['order']['paused']);self.act(c,'start',expected=409)
        c=self.act(c,'resume',hold_id='scope');c=self.act(c,'start');self.assertEqual(c['order']['status'],'in_service')
    def test_09_cancel_settlement_and_refund(self):
        c=self.ordered();c=self.act(c,'record_payment',amount_minor=30000,reference=str(uuid.uuid4()));payment=c['order']['payments'][0]['id']
        c=self.act(c,'cancel',text='协商取消，最终应收100元',settlement_minor=10000);c=self.act(c,'confirm_cancel',self.customer)
        c=self.act(c,'refund',amount_minor=20000,payment_id=payment);rid=c['order']['refunds'][0]['id'];self.assertEqual(c['order']['refunded_minor'],0)
        c=self.act(c,'approve_refund',refund_id=rid);self.assertEqual(c['order']['refund_held_minor'],20000)
        c=self.act(c,'mark_refund_unknown',refund_id=rid);self.act(c,'fail_refund',refund_id=rid,text='超时',expected=409)
        c=self.act(c,'confirm_refund',refund_id=rid,reference=str(uuid.uuid4()))
        o=c['order'];self.assertEqual((o['status'],o['original_amount_minor'],o['amount_minor'],o['paid_minor']-o['refunded_minor'],o['refund_held_minor']),('cancelled',100000,10000,10000,0))
    def test_10_delivery_revision_and_after_sale(self):
        c=self.upload(self.ordered());c=self.act(c,'start');c=self.act(c,'deliver',text='第一版',attachment_ids=[c['attachments'][0]['id']]);d=c['order']['deliveries'][-1]['id']
        c=self.act(c,'revision',self.customer,text='补充格式说明',delivery_id=d);feedback=c['order']['feedback'][-1]['id']
        c=self.act(c,'accept_revision',feedback_id=feedback,round_id='round-a',count_units=1);self.assertEqual(c['order']['revision_used'],1)
        c=self.act(c,'deliver',text='修订正式版',attachment_ids=[c['attachments'][0]['id']]);latest=c['order']['deliveries'][-1]['id']
        self.act(c,'accept_delivery',self.customer,delivery_id=d,expected=409)
        c=self.act(c,'accept_delivery',self.customer,delivery_id=latest);self.assertEqual(c['order']['status'],'completed')
        c=self.act(c,'after_sale',self.customer,text='补交格式说明');self.assertEqual(c['order']['status'],'completed')
        af=c['after_sales'][-1]['id'];c=self.act(c,'deliver',text='售后补充文件',attachment_ids=[c['attachments'][0]['id']],after_sale_id=af);self.assertEqual(c['order']['status'],'completed')
    def test_11_change_requires_customer_acceptance(self):
        c=self.ordered();c=self.act(c,'propose_change',amount_minor=80000,scope='双方协商缩小范围')
        self.assertEqual(c['order']['amount_minor'],100000);change=c['order']['changes'][-1]['id']
        c=self.act(c,'confirm_change',self.customer,change_id=change);self.assertEqual(c['order']['amount_minor'],80000);self.assertEqual(c['order']['original_amount_minor'],100000)
    def test_12_supplement_invalidates_unaccepted_quote(self):
        c=self.new();c=self.act(c,'quote',amount_minor=10000,prepay_minor=0,revision_limit=2,scope='旧材料范围',expires_at=(dt.datetime.now(dt.timezone.utc)+dt.timedelta(hours=1)).isoformat());old=c['quote']['id']
        c=self.act(c,'need_material',text='需新材料');c=self.act(c,'supplement',self.customer,text='新的服务材料')
        self.act(c,'accept_quote',self.customer,quote_id=old,expected=409)
    def test_13_readiness_and_session_no_cache(self):
        self.req('/health');self.req('/operations/does-not-exist',self.customer,expected=404)
    @unittest.skipUnless(hasattr(signal, 'SIGHUP'), 'Requires Unix hangup signal')
    def test_98_hangup_releases_lock_and_preserves_business(self):
        c=self.new()
        data=self.runtime/'data'
        snapshot=(data/'state.json').read_bytes()
        self.proc.send_signal(signal.SIGHUP)
        code=self.proc.wait(timeout=30)
        marker_removed=not (data/'.server-lock').exists()
        unchanged=(data/'state.json').read_bytes()==snapshot
        self.start()
        del type(self)._tokens
        self.assertEqual(code,0)
        self.assertTrue(marker_removed,'Hangup left an active lock marker')
        self.assertTrue(unchanged,'Hangup changed committed business data')
        token=self.login('customer','demo-customer')
        self.assertEqual(self.req('/cases/'+c['id'],token)['case']['id'],c['id'])
    def test_99_restart_preserves_business_and_receipt(self):
        c=self.new();key=str(uuid.uuid4());body={'action':'message','expected_version':c['version'],'text':'重启后保留'}
        self.req('/cases/'+c['id']+'/actions',self.customer,body,key=key)
        self.stop();self.start();self.req('/workspace',self.customer,expected=401)
        self.customer=self.login('customer','demo-customer');r=self.req('/operations/'+key,self.customer)
        self.assertEqual(r['case']['messages'][-1]['text'],'重启后保留')

if __name__=='__main__':unittest.main(verbosity=2)
