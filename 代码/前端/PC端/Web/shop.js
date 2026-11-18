const $ = s => document.querySelector(s);
const escape = v => String(v ?? '').replace(/[&<>"']/g, x => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[x]));
const languages = {'zh':'简体中文','zh-Hant':'繁體中文','bo':'བོད་ཡིག','en':'English','ja':'日本語','fr':'Français','es':'Español','de':'Deutsch','ru':'Русский','ko':'한국어'};
const storage = {get(k,d){try{return localStorage.getItem('zhixu-native-'+k)??d;}catch{return d;}},set(k,v){try{localStorage.setItem('zhixu-native-'+k,v);}catch{}}};
const state = {epoch:0,lang:storage.get('language','zh'),theme:storage.get('theme','system'),api:storage.get('api',location.protocol==='file:'?'http://127.0.0.1:8080/api/v1':location.origin+'/api/v1'),timeout:Number(storage.get('timeout','2500')),products:[],orders:[],demoOrders:[],user:null,token:'',live:false,source:'demo',category:'all',filter:'all',pending:null,banners:null};
const [strings, seed] = await Promise.all(['shop_strings.json','products.json'].map(x=>fetch('Assets/'+x).then(r=>r.json())));
state.products=structuredClone(seed);
const t = key => strings[state.lang]?.[key]??strings.zh[key]??key;
const money = n => '¥'+(Number(n)/100).toFixed(2);
class ApiError extends Error {constructor(message,status=0){super(message);this.status=status;}}
async function request(path,{method='GET',body,key}={}){
  const epoch=state.epoch;const api=state.api;const token=state.token;const controller=new AbortController();const timeout=setTimeout(()=>controller.abort(),state.timeout);
  try{
    const response=await fetch(api.replace(/\/$/,'')+path,{method,signal:controller.signal,redirect:'error',headers:{'Content-Type':'application/json',...(token?{Authorization:'Bearer '+token}:{}),...(key?{'Idempotency-Key':key}:{})},body:body?JSON.stringify(body):undefined});
    if(epoch!==state.epoch)throw new ApiError(t('reselect'),499);
    if(response.status===401){logout();throw new ApiError(t('signInFirst'),401);}
    let result;try{result=await response.json();}catch{throw new ApiError(t('unexpected_response'));}
    if(epoch!==state.epoch)throw new ApiError(t('reselect'),499);
    if(!response.ok){if(response.status===401){logout();}throw new ApiError(result.error?.message??result.message??String(result.error??response.status),response.status);}
    return result;
  }catch(error){if(epoch!==state.epoch)throw new ApiError(t('reselect'),499);throw error;}finally{clearTimeout(timeout);}
}
const recoverable = e => !e.status || e.status>=500;
let refreshRevision = 0;
let activeWrite = null;
let formRevision = 0;
let bannerIndex = 0;
let carouselTimer;
let carouselHover = false;
const motionPreference=matchMedia('(prefers-reduced-motion: reduce)');
const validProduct = p => p && typeof p.id === 'string' && typeof p.name === 'string'
  && Number.isSafeInteger(p.version) && p.version > 0 && Number.isSafeInteger(p.price_minor) && p.price_minor >= 0
  && typeof p.active === 'boolean' && typeof p.in_stock === 'boolean'
  && (!p.sections || (Array.isArray(p.sections) && p.sections.every(s => typeof s.title === 'string' && typeof s.body === 'string')));
const validOrder = o => o && typeof o.id === 'string' && Number.isSafeInteger(o.version) && o.version > 0
  && Number.isSafeInteger(o.amount_minor) && o.amount_minor >= 0 && typeof o.status === 'string'
  && o.product_snapshot && typeof o.product_snapshot.name === 'string';
function notify(message){$('#notice').textContent=message;$('#notice').hidden=false;clearTimeout(notify.timer);notify.timer=setTimeout(()=>$('#notice').hidden=true,6000);}
function applyPreferences(){document.documentElement.lang=state.lang;document.documentElement.dataset.theme=state.theme;document.querySelectorAll('[data-i]').forEach(e=>e.textContent=t(e.dataset.i));}
function image(product){return product.image||'Assets/'+(product.category_id??'graduation')+'.png';}
function picture(src,cls=''){return `<img class="${cls}" src="${escape(src.startsWith('Assets/')?src:'Assets/brand.svg')}" ${src.startsWith('Assets/')?'':`data-remote="${escape(src)}"`} alt="" loading="lazy" onerror="this.onerror=null;this.src='Assets/brand.svg'">`;}
function hydratePictures(){for(const image of document.querySelectorAll('img[data-remote]')){const source=image.dataset.remote;delete image.dataset.remote;const loader=new Image();loader.onload=()=>{if(image.isConnected)image.src=source;};loader.src=source;}}
function bannerItems(){return state.banners??['graduation','journal','editing'].map(category=>({id:category,image:'Assets/'+category+'.png',title:t(category)}));}
function carousel(){
  const items=bannerItems();
  if(!items.length)return '';
  bannerIndex%=items.length;
  const banner=items[bannerIndex];
  let target;
  try{const u=new URL(banner.target_url);if(['https:','http:'].includes(u.protocol)&&!u.username&&!u.password)target=u.href;}catch{}
  const visual=picture(banner.image||'Assets/brand.svg');
  return `<div class="banner-visual">${target?`<a href="${escape(target)}" target="_blank" rel="noopener noreferrer" aria-label="${escape(banner.title||t('details'))}">${visual}</a>`:visual}</div>`
    + (items.length>1?`<div class="banner-dots">${items.map((b,i)=>`<button type="button" data-banner="${i}" aria-label="${escape(b.title||t('banners'))}" aria-pressed="${i===bannerIndex}"><span></span></button>`).join('')}</div>`:'');
}
function scheduleCarousel(){
  clearTimeout(carouselTimer);
  if(document.hidden||motionPreference.matches||carouselHover||$('#modal').open||!$('#carousel')||($('#carousel').contains(document.activeElement)&&document.activeElement.matches(':focus-visible'))||bannerItems().length<2)return;
  carouselTimer=setTimeout(()=>{bannerIndex++;$('#carousel').innerHTML=carousel();hydratePictures();scheduleCarousel();},5000);
}
function empty(key){return `<section class="empty">${picture('Assets/brand.svg')}<h2>${t(key)}</h2><p>${t('emptyHint')}</p><button data-action="reload">${t('reload')}</button></section>`;}
function render(){
  applyPreferences();const page=location.hash.slice(1)||'home';
  $('nav').querySelectorAll('a').forEach(a=>a.setAttribute('aria-current',a.hash==='#'+page?'page':'false'));
  $('#account').textContent=state.user?.name??t('login');$('#source').textContent=t(state.source==='live'?'online':'offline');
  const main=$('#main');
  if(page==='orders'){
    main.innerHTML=`<h1>${t('myOrders')}</h1>`+(!state.user?`<p>${t('signInFirst')}</p><button data-action="login">${t('login')}</button>`:`<div class="filters">${['all','pending_payment','pending_completion','pending_review','completed','cancelled'].map(s=>`<button data-filter="${s}" class="${state.filter===s?'selected':''}">${t(s)}</button>`).join('')}</div>`+orderList());
  }else if(page==='mine'){
    main.innerHTML=`<h1>${t('mine')}</h1>`+(state.user?`${picture(state.user.avatar_url||'Assets/brand.svg','account-avatar')}<h2>${escape(state.user.name)}</h2><p>${escape(state.user.email??state.user.username??'')}</p><div class="row"><button data-action="profile">${t('saveProfile')}</button><button data-action="settings">${t('settings')}</button><button data-action="logout">${t('logout')}</button></div>`:`<p>${t('signInFirst')}</p><button data-action="login">${t('login')}</button>`);
  }else if(page.startsWith('product/')){
    let id;try{id=decodeURIComponent(page.slice(8));}catch{}
    const p=state.products.find(x=>x.id===id);
    main.innerHTML=!p?empty('emptyProducts'):`<article class="detail"><a href="#home">${t('back')}</a><h1>${escape(p.name)}</h1>${picture(image(p))}<p class="price">${money(p.price_minor)}</p><p class="prose">${escape(p.description)}</p>${(p.sections??[]).map(s=>`<h2>${escape(s.title)}</h2><p class="prose">${escape(s.body)}</p>`).join('')}<button class="primary" data-buy="${escape(p.id)}" ${!p.in_stock?'disabled':''}>${t(p.in_stock?'buy':'outOfStock')}</button></article>`;
  }else{
    const products=state.products.filter(p=>p.active&&(state.category==='all'||p.category_id===state.category));
    main.innerHTML=`<section class="hero"><div><h1>${t('hero')}</h1><p>${t('intro')}</p></div><div id="carousel" aria-label="${escape(t('banners'))}">${carousel()}</div></section><h2>${t('shop')}</h2><div class="filters">${['all','graduation','journal','editing'].map(c=>`<button data-category="${c}" class="${state.category===c?'selected':''}">${t(c)}</button>`).join('')}</div>`+(products.length?`<div class="grid">${products.map(p=>`<article class="card">${picture(image(p))}<div class="card-body"><span class="tag">${t(p.category_id)} / ${t(p.kind)}</span><h2>${escape(p.name)}</h2><p>${escape(p.summary)}</p><div class="card-bottom"><span class="price">${money(p.price_minor)}</span><a href="#product/${encodeURIComponent(p.id)}">${t('details')}</a></div></div></article>`).join('')}</div>`:empty('emptyProducts'));
  }
  if($('#carousel')){
    $('#carousel').onmouseenter=()=>{if(matchMedia('(hover: hover)').matches){carouselHover=true;clearTimeout(carouselTimer);}};
    $('#carousel').onmouseleave=()=>{carouselHover=false;scheduleCarousel();};
    $('#carousel').onfocusin=()=>clearTimeout(carouselTimer);
    $('#carousel').onfocusout=()=>queueMicrotask(scheduleCarousel);
  }else carouselHover=false;
  hydratePictures();
  scheduleCarousel();
}
function orderList(){
  const list=state.orders.filter(o=>state.filter==='all'||state.filter===o.status);
  if(!list.length)return empty('emptyOrders');
  return list.map(o=>`<article class="order"><small>${escape(o.id)}</small><h2>${escape(o.product_snapshot?.name)}</h2><div class="row"><strong class="price">${money(o.amount_minor)}</strong><span>${t(o.status)}</span><span>${t(o.fulfillment_status)}</span></div><p class="prose">${escape(o.requirements)}</p>${o.delivery_text?`<h3>${t('delivered')}</h3><p class="prose">${escape(o.delivery_text)}</p>`:''}<div class="row">${o.editable?`<button data-edit="${escape(o.id)}">${t('editRequirements')}</button>`:''}${o.status==='pending_payment'?`<button data-pay="${escape(o.id)}" class="primary">${t('checkout')}</button><button data-order="${escape(o.id)}" data-command="cancel">${t('cancel')}</button>`:''}${o.status==='pending_completion'&&o.fulfillment_status==='delivered'?`<button data-order="${escape(o.id)}" data-command="accept">${t('accept')}</button>`:''}${o.status==='pending_review'?`<button data-review="${escape(o.id)}">${t('review')}</button>`:''}</div></article>`).join('');
}
async function refresh(){
  const epoch=state.epoch;
  const revision=++refreshRevision;
  const current=()=>epoch===state.epoch && revision===refreshRevision;
  let config, banners, products, orders;
  try{config=await request('/shop-config');}catch{}
  if(!current())return;
  try{const b=await request('/banners');if(Array.isArray(b.banners))banners=b.banners;}catch{}
  if(!current())return;
  try{
    const p=await request('/products');
    if(!Array.isArray(p.products)||!p.products.every(validProduct))throw new ApiError(t('unexpected_response'));
    products=p.products;
    if(state.live){
      const o=await request('/shop-orders');
      if(!Array.isArray(o.orders)||!o.orders.every(validOrder))throw new ApiError(t('unexpected_response'));
      orders=o.orders;
    }
  }catch(e){if(!current())return;if(state.source==='live')notify(t('updateFailed'));}
  if(!current())return;
  if(config)state.demoMode=config.demo_mode===true;
  if(banners)state.banners=banners;
  if(products){state.products=products;if(!state.user||state.live)state.source='live';}
  if(orders&&!activeWrite)state.orders=orders;
  if(!state.live)state.orders=state.demoOrders;
  render();
}
function field(key,value='',type='text'){return `<label>${t(key)}<input name="${key}" type="${type}" value="${escape(value)}" ${['api','timeout'].includes(key)?'':'required'}></label>`;}
function area(key,value=''){return `<label>${t(key)}<textarea name="${key}">${escape(value)}</textarea></label>`;}
let submit;
function modal(title,html,handler,button='save'){formRevision++;$('#submit').disabled=false;$('#dialog-content').innerHTML=`<h2>${t(title)}</h2>${html}`;$('#form-error').textContent='';$('#submit').textContent=t(button);submit=handler;if(!$('#modal').open)$('#modal').showModal();scheduleCarousel();}
function auth(mode='login'){
  logout(false);
  const tabs=`<div class="auth-tabs">${['login','register','forgotPassword'].map(x=>`<button type="button" data-auth="${x}">${t(x)}</button>`).join('')}</div>`;
  modal(mode,tabs+(mode==='login'?field('account')+field('password','','password'):`${field('email','','email')}<button type="button" data-code="${mode==='register'?'register':'reset_password'}">${t('sendCode')}</button>${field('code')}${mode==='register'?field('username'):''}${field('password','','password')}${field('confirmPassword','','password')}`)+`<p>${t('loginHint')}</p>`,async data=>{
    if(mode==='login'){
      try{const r=await request('/auth/login',{method:'POST',body:data});if(r.user?.role!=='customer'||!r.token)throw new ApiError(t('customer'),403);state.token=r.token;state.user=r.user;state.live=true;state.orders=[];}
      catch(e){if(!recoverable(e)||data.account!=='customer'||data.password!=='demo-customer')throw e;state.user={id:'demo-customer',name:'customer',username:'customer'};state.live=false;state.source='demo';state.products=structuredClone(seed);state.orders=state.demoOrders;}
    }else{
      if(data.password!==data.confirmPassword)throw new ApiError(t('required'));
      await request('/auth/'+(mode==='register'?'register':'reset-password'),{method:'POST',body:{...data,confirm_password:data.confirmPassword}});
      auth();return false;
    }
    await refresh();return true;
  },'continueAuth');
}
function settings(){
  const select=(key,options)=>`<label>${t(key)}<select name="${key}">${Object.entries(options).map(([v,s])=>`<option value="${v}" ${state[key=== 'language'?'lang':key]===v?'selected':''}>${escape(s)}</option>`).join('')}</select></label>`;
  modal('settings',select('language',languages)+select('theme',Object.fromEntries(['system','light','dark'].map(k=>[k,t(k)])))+field('api',state.api,'url')+field('timeout',state.timeout,'number'),async d=>{
    const u=new URL(d.api);if(!['https:','http:'].includes(u.protocol)||u.username||u.password||u.search||u.hash)throw new ApiError(t('invalidLink'));
    if(!Number.isFinite(+d.timeout)||+d.timeout<500||+d.timeout>10000)throw new ApiError(t('timeout'));
    if(d.api!==state.api){logout();state.api=d.api;state.products=structuredClone(seed);}
    state.lang=d.language;state.theme=d.theme;state.timeout=+d.timeout;for(const k of ['language','theme','api','timeout'])storage.set(k,d[k]);render();await refresh();
  });
}
function logout(closeForm=true){state.epoch++;refreshRevision++;activeWrite=null;state.source='demo';state.products=structuredClone(seed);state.banners=null;state.user=null;state.token='';state.live=false;state.orders=[];state.demoOrders=[];state.pending=null;if(closeForm){formRevision++;$('#modal').close();}render();}
async function mutate(path,body){
  if(!state.user)throw new ApiError(t('signInFirst'),401);
  if(activeWrite)throw new ApiError(t('pendingWrite'),409);
  const existing=state.pending;
  if(existing&&(existing.path!==path||JSON.stringify(existing.body)!==JSON.stringify(body)))throw new ApiError(t('pendingWrite'));
  const key=existing?.key??'web-shop-'+crypto.randomUUID();
  const epoch=state.epoch, live=state.live, ticket={};
  state.pending={path,body:structuredClone(body),key};
  activeWrite=ticket;
  refreshRevision++;
  try{
    const r=await request(path,{method:'POST',body,key});
    if(epoch!==state.epoch)return;
    if(!validOrder(r.order))throw new ApiError(t('unexpected_response'));
    if(path==='/shop-orders'){
      if(r.order.product_snapshot.id!==body.product_id)throw new ApiError(t('unexpected_response'));
    }else if(path!=='/shop-orders/'+encodeURIComponent(r.order.id)+'/actions'||r.order.version<=body.expected_version)throw new ApiError(t('unexpected_response'));
    state.pending=null;state.source='live';state.orders=[r.order,...state.orders.filter(o=>o.id!==r.order.id)];
  }catch(e){
    if(epoch!==state.epoch)throw e;
    if(!recoverable(e)){state.pending=null;throw e;}
    if(live)throw new ApiError(t('pendingWrite'));
    demoMutation(path,body);state.pending=null;
  }finally{
    if(activeWrite===ticket){activeWrite=null;refreshRevision++;}
  }
  render();
}
function demoMutation(path,body){
  let order;
  if(path==='/shop-orders'){
    const p=state.products.find(p=>p.id===body.product_id);if(!p?.in_stock||p.version!==body.product_version)throw new ApiError(t('version'));
    order={id:'demo-'+crypto.randomUUID(),product_snapshot:structuredClone(p),amount_minor:p.price_minor,status:'pending_payment',fulfillment_status:'pending',version:1,editable:true,...body};state.demoOrders.unshift(order);
  }else{
    order=state.demoOrders.find(o=>path.includes(o.id));if(!order||order.version!==body.expected_version)throw new ApiError(t('version'));
    if(body.action==='pay'&&order.status==='pending_payment'){order.status='pending_completion';order.payment={mode:'mock',channel:body.channel};}
    else if(body.action==='cancel'&&order.status==='pending_payment')order.status='cancelled';
    else if(body.action==='edit'&&order.editable)Object.assign(order,{requirements:body.requirements,contact:body.contact,delivery_requirements:body.delivery_requirements});
    else if(body.action==='accept'&&order.fulfillment_status==='delivered')order.status='pending_review';
    else if(body.action==='review'&&order.status==='pending_review'){order.status='completed';order.review={rating:+body.rating,text:body.text};}
    else throw new ApiError(t('state'));order.version++;
  }
  state.orders=state.demoOrders;state.source='demo';
}
function buy(id){if(!state.user){auth();return;}const p=state.products.find(p=>p.id===id);modal('buy',`<h3>${escape(p.name)} · ${money(p.price_minor)}</h3>${area('requirements')}${field('contact')}${area('deliveryRequirements')}`,d=>mutate('/shop-orders',{product_id:p.id,product_version:p.version,requirements:d.requirements,contact:d.contact,delivery_requirements:d.deliveryRequirements}),'buy');}
function orderAction(id,action){const o=state.orders.find(o=>o.id===id);return extra=>mutate('/shop-orders/'+encodeURIComponent(id)+'/actions',{action,expected_version:o.version,...extra});}
document.addEventListener('click',async event=>{
  const e=event.target.closest('button');if(!e)return;
  if(e.dataset.banner!==undefined){bannerIndex=Number(e.dataset.banner);const dots=$('#carousel').querySelectorAll('[data-banner]');const visual=$('#carousel .banner-visual');visual.innerHTML=new DOMParser().parseFromString(carousel(),'text/html').querySelector('.banner-visual').innerHTML;dots.forEach((dot,i)=>dot.setAttribute('aria-pressed',i===bannerIndex));hydratePictures();scheduleCarousel();}
  if(e.dataset.category){state.category=e.dataset.category;render();}
  if(e.dataset.filter){state.filter=e.dataset.filter;render();}
  if(e.dataset.auth)auth(e.dataset.auth);
  if(e.dataset.action==='reload')await refresh();
  if(e.dataset.action==='login')auth();
  if(e.dataset.action==='logout')logout();
  if(e.dataset.action==='settings')settings();
  if(e.dataset.buy)buy(e.dataset.buy);
  if(e.dataset.pay)modal('checkout',`<p>${t('mockHint')}</p><label>${t('checkout')}<select name="channel"><option value="alipay">${t('alipay')}</option><option value="wechat">${t('wechat')}</option></select></label>`,orderAction(e.dataset.pay,'pay'),'confirmPay');
  if(e.dataset.order)modal(e.dataset.command,`<p>${t(e.dataset.command)}</p>`,orderAction(e.dataset.order,e.dataset.command),e.dataset.command);
  if(e.dataset.edit){const o=state.orders.find(o=>o.id===e.dataset.edit);modal('editRequirements',area('requirements',o.requirements)+field('contact',o.contact)+area('deliveryRequirements',o.delivery_requirements),d=>orderAction(o.id,'edit')({requirements:d.requirements,contact:d.contact,delivery_requirements:d.deliveryRequirements}));}
  if(e.dataset.review)modal('review',`<label>${t('rating')}<select name="rating">${[5,4,3,2,1].map(v=>`<option>${v}</option>`).join('')}</select></label>${area('text')}`,d=>{if(!d.text.trim())throw new ApiError(t('requiredReview'));return orderAction(e.dataset.review,'review')({rating:+d.rating,text:d.text});},'review');
  if(e.dataset.code){const revision=formRevision;e.disabled=true;try{const result=await request('/auth/email-code',{method:'POST',body:{email:$('#form [name=email]').value,purpose:e.dataset.code}});if(revision===formRevision)$('#form-error').textContent=result.demo_code?t('demoCode')+': '+result.demo_code:t('codeSent');}catch(error){if(revision===formRevision)$('#form-error').textContent=error.message;}finally{e.disabled=false;}}
  if(e.dataset.action==='profile')modal('saveProfile',field('username',state.user.username||state.user.name)+`<label>${t('uploadAvatar')}<input name="avatar" type="file" accept="image/png,image/jpeg,image/webp"></label>`,async d=>{
    const epoch=state.epoch;const file=$('#form [name=avatar]').files[0];let avatar;
    if(file){if(file.size>2*1024*1024)throw new ApiError(t('invalidAvatar'));avatar=await new Promise((ok,no)=>{const r=new FileReader();r.onload=()=>ok(r.result);r.onerror=no;r.readAsDataURL(file);});}
    if(epoch!==state.epoch)throw new ApiError(t('reselect'),499);
    try{const r=await request('/auth/profile',{method:'PUT',body:{username:d.username,...(avatar?{avatar:avatar}:{})}});if(!r.user||r.user.id!==state.user?.id)throw new ApiError(t('unexpected_response'));state.user=r.user;}
    catch(error){if(state.live||!recoverable(error))throw error;Object.assign(state.user,{name:d.username,username:d.username,...(avatar?{avatar_url:avatar}:{})});}render();
  });
});
$('#form').onsubmit=async e=>{e.preventDefault();const revision=formRevision;const handler=submit;$('#submit').disabled=true;$('#form-error').textContent='';try{const done=await handler(Object.fromEntries(new FormData(e.target)));if(done!==false&&revision===formRevision)$('#modal').close();}catch(error){if(revision===formRevision)$('#form-error').textContent=error.message;}finally{if(revision===formRevision)$('#submit').disabled=false;}};
$('#close').onclick=()=>{formRevision++;$('#modal').close();};$('#modal').addEventListener('cancel',()=>formRevision++);$('#account').onclick=()=>state.user?location.hash='mine':auth();$('#settings').onclick=settings;$('#reload').onclick=()=>refresh();
window.addEventListener('hashchange',()=>{render();window.scrollTo(0,0);refresh();});window.addEventListener('focus',()=>refresh());
document.addEventListener('visibilitychange',scheduleCarousel);motionPreference.addEventListener('change',scheduleCarousel);$('#modal').addEventListener('close',scheduleCarousel);
render();refresh();
