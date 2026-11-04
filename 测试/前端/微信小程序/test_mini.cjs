// Created by Jobs. Run: node --test 测试/前端/微信小程序/test_mini.cjs
const {test}=require('node:test');const assert=require('node:assert/strict');
const {Client}=require('../../../代码/前端/微信小程序/Utils/api');
const fs=require('node:fs');const path=require('node:path');const vm=require('node:vm');
function pageHarness(page,api,wx={}){
  let definition;vm.runInNewContext(fs.readFileSync(path.join(__dirname,'../../../代码/前端/微信小程序/Pages',page,'index.js'),'utf8'),{Page:value=>definition=value,getApp:()=>({api}),wx,require});
  return {...definition,data:JSON.parse(JSON.stringify(definition.data)),setData(value){Object.assign(this.data,value)}};
}
function harness(handler){const wx={getStorageSync(){return ''},setStorageSync(){},request(o){handler(o)}};return new Client(wx)}
const customer={id:'customer',name:'客户',role:'customer'};
test('真实空服务列表保留空态，不回填假服务',async()=>{const a=harness(o=>o.success({statusCode:200,data:{services:[]}}));const r=await a.listServices();assert.deepEqual(r.services,[]);assert.equal(r.source,'live')});
test('网络失败服务回退三服务，恢复后自动使用真数据',async()=>{let fail=true;const a=harness(o=>fail?o.fail():o.success({statusCode:200,data:{services:[{id:'editing',name:'编译'}]}}));assert.equal((await a.listServices()).source,'demo');fail=false;assert.equal((await a.listServices()).services.length,1)});
test('401清空私有缓存和会话，不作为演示成功',async()=>{const a=harness(o=>o.success({statusCode:401,data:{error:{message:'expired'}}}));a.user=customer;a.token='secret';a.cases=[{id:'private'}];await assert.rejects(a.workspace(),e=>e.status===401);assert.equal(a.user,null);assert.deepEqual(a.cases,[])});
test('403拒绝写入，不产生演示数据',async()=>{const a=harness(o=>o.success({statusCode:403,data:{error:{message:'forbidden'}}}));a.user=customer;await assert.rejects(a.write('/cases',{}),e=>e.status===403);assert.equal(a.pending,null);assert.deepEqual(a.cases,[])});
test('真实写入断网进入待核对，保留原键并禁止重复写入',async()=>{let calls=0;const a=harness(o=>{calls++;o.fail()});a.user=customer;a.token='real';await assert.rejects(a.write('/cases',{title:'A'}),/待核对/);const key=a.pending.key;await assert.rejects(a.write('/cases',{title:'A'}),/先核对/);assert.equal(a.pending.key,key);assert.equal(calls,1)});
test('未知写入核对查询原键，返回最新记录后解除阻塞',async()=>{let failed=true;const a=harness(o=>{if(failed)o.fail();else{o.success({statusCode:200,data:{operation:{status:'succeeded'},case:{id:'r',owner_id:'customer',version:2}}})}});a.user=customer;await assert.rejects(a.write('/cases',{}));failed=false;const c=await a.reconcile();assert.equal(c.id,'r');assert.equal(a.pending,null)});
test('演示写入仅在隔离身份断网时运行，不自动上传',async()=>{let calls=0;const a=harness(o=>{calls++;o.fail()});await a.login('customer','demo-customer',true);assert.equal(a.user.id,'demo');const c=await a.write('/cases',{title:'演示',service_id:'editing'});assert.equal(c.owner_id,'demo');assert.equal(a.mode,'demo');assert.equal(calls,2);assert.equal(a.pending,null)});
test('重新配置地址清除账户私有缓存',()=>{const a=harness(()=>{});a.user=customer;a.token='token';a.cases=[{id:'private'}];a.configure('https://example.org/api/v1');assert.equal(a.user,null);assert.equal(a.token,'');assert.deepEqual(a.cases,[])});
test('账户改变后迟到回包不得重新带回旧数据',async()=>{let callback;const a=harness(o=>{callback=o});a.user=customer;const work=a.workspace();a.logout();callback.success({statusCode:200,data:{cases:[{id:'private',owner_id:'customer',version:1}]}});await assert.rejects(work);assert.deepEqual(a.cases,[])});
test('畸形2xx写入保留待核对而不报告成功',async()=>{const a=harness(o=>o.success({statusCode:200,data:{case:{}}}));a.user=customer;await assert.rejects(a.write('/cases',{}),/待核对/);assert.ok(a.pending)});

test('读取真实数据失败后清除真实缓存，不能标成演示详情',async()=>{const a=harness(o=>o.fail());a.user=customer;a.cases=[{id:'private',owner_id:'customer',version:1}];assert.deepEqual(await a.workspace(),[]);assert.deepEqual(a.cases,[])});
test('新会话恢复同账户待核对记录，重试保持原键原文',async()=>{const data=new Map();let failed=true,captured;const wx={getStorageSync:k=>data.get(k)||'',setStorageSync:(k,v)=>data.set(k,v),request(o){if(o.url.endsWith('/auth/login'))o.success({statusCode:200,data:{token:'t',user:customer}});else if(failed)o.fail();else{captured=o;o.success({statusCode:201,data:{case:{id:'r',owner_id:'customer',version:1}}})}}};const a=new Client(wx);await a.login('customer','pw');await assert.rejects(a.write('/cases',{title:'original'}));const original=a.pending.key;const b=new Client(wx);await b.login('customer','pw');assert.equal(b.pending.key,original);failed=false;await b.retryPending();assert.equal(captured.header['Idempotency-Key'],original);assert.deepEqual(captured.data,{title:'original'});assert.equal(b.pending,null)});
test('旧账户迟到401不能登出新账户',async()=>{let callback;const a=harness(o=>callback=o);a.user=customer;const r=a.workspace();a.logout();a.user={id:'new',role:'customer'};callback.success({statusCode:401,data:{}});await assert.rejects(r);assert.equal(a.user.id,'new')});
test('选择附件期间换号，不把旧账户文件送到新会话',async()=>{const a=harness(()=>{});a.user=customer;let selection;let uploads=0;a.wx.chooseMessageFile=()=>new Promise(r=>selection=r);a.wx.uploadFile=()=>uploads++;const upload=a.upload({id:'old',version:1});a.logout();a.user={id:'new',role:'customer'};selection({tempFiles:[{path:'test.txt'}]});await assert.rejects(upload);assert.equal(uploads,0)});

test('连接设置保留短超时，重启后的真实读写均使用同一超时',async()=>{
  const storage=new Map();const calls=[];
  const wx={getStorageSync:key=>storage.get(key)||'',setStorageSync:(key,value)=>storage.set(key,value),request(o){calls.push(o);if(o.method==='POST')o.success({statusCode:201,data:{case:{id:'saved',owner_id:'customer',version:1}}});else o.success({statusCode:200,data:{services:[]}})}};
  const first=new Client(wx);assert.equal(first.timeoutMs,2500);first.configure('https://example.org/api/v1',900);
  const restored=new Client(wx);assert.equal(restored.timeoutMs,900);await restored.listServices();restored.user=customer;await restored.write('/cases',{title:'A'});
  assert.deepEqual(calls.map(call=>call.timeout),[900,900]);assert.equal(restored.mode,'live');assert.equal(restored.cases[0].id,'saved');
});
test('非法超时不能注销现有会话或覆盖有效连接配置',()=>{
  const a=harness(()=>{});a.user=customer;a.token='current';const original=a.base;
  for(const value of [0,499,10001,'bad',1.5])assert.throws(()=>a.configure('https://example.org/api/v1',value),/请求超时/);
  assert.equal(a.user.id,'customer');assert.equal(a.token,'current');assert.equal(a.base,original);assert.equal(a.timeoutMs,2500);
});

test('同账户旧列表回包或故障不能覆盖后发请求的真实结果',async()=>{
  for(const failOld of [false,true]){
    const requests=[];const a=harness(o=>requests.push(o));a.user=customer;
    const old=a.workspace(),latest=a.workspace();requests[1].success({statusCode:200,data:{cases:[{id:'r',owner_id:'customer',version:2}]}});await latest;
    if(failOld)requests[0].fail();else requests[0].success({statusCode:200,data:{cases:[{id:'r',owner_id:'customer',version:1}]}});
    await old;assert.equal(a.cases[0].version,2);assert.equal(a.mode,'live');
  }
});
test('写入后的版本不被此前在途列表读覆盖',async()=>{
  let request;const a=harness(o=>request=o);a.user=customer;const old=a.workspace();a.upsert({id:'r',owner_id:'customer',version:3});request.success({statusCode:200,data:{cases:[{id:'r',owner_id:'customer',version:1}]}});await old;assert.equal(a.cases[0].version,3);
});
test('首页较早读取的离线回退不能覆盖后来显示的真实服务',async()=>{
  const requests=[];const a=harness(o=>requests.push(o));const page=pageHarness('Home',a);
  const old=page.reload(),latest=page.reload();requests[1].success({statusCode:200,data:{services:[{id:'live',name:'服务端'}]}});await latest;requests[0].fail();await old;assert.equal(page.data.source,'live');assert.equal(page.data.services[0].id,'live');
});
test('新建页演示与真实提交共用必填授权校验，拒绝后不发写请求',async()=>{
  let writes=0,redirects=0;const api={user:customer,write:async()=>{writes++;return {id:'new'}}};const page=pageHarness('Create',api,{redirectTo(){redirects++}});
  await page.submit();assert.match(page.data.error,/需求标题/);
  page.data.form.title='研究需求';page.data.form.description='材料与目标';page.data.form.discipline='计算机';await page.submit();assert.match(page.data.error,/授权/);assert.equal(writes,0);
  page.data.consent=true;page.data.form.word_count='1.5';await page.submit();assert.match(page.data.error,/非负整数/);assert.equal(writes,0);
  page.data.form.word_count='500';await page.submit();assert.equal(writes,1);assert.equal(redirects,1);
});
