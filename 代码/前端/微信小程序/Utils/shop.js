// Created by Jobs. Virtual goods, isolated demo state and idempotent writes.
const { Client, ApiError } = require('./api');
const clone = value => JSON.parse(JSON.stringify(value));
const seeds = [
  ['graduation-outline','graduation','course','论文提纲','从选题到结构的论文提纲辅导',49800],
  ['graduation-proposal','graduation','course','开题指导报告课','开题思路与研究方案课程',1],
  ['graduation-mentoring','graduation','service','毕业论文一对一','针对现有写作材料的一对一辅导',5000],
  ['journal-submission','journal','service','审测投稿','期刊咨询与投稿流程服务',9900],
  ['journal-mentoring','journal','service','普刊论文一对一','稿件结构与表达的一对一辅导',20000],
  ['journal-assessment','journal','service','论文专业测评','稿件问题梳理与专业测评',60000],
  ['journal-training','journal','course','普刊训练营','普刊写作与投稿知识课程',219900],
  ['editing-translation','editing','service','学术翻译','基于本人稿件的学术语言翻译',19900],
  ['editing-polish','editing','service','学术润色','学术语言表达与格式润色',15900],
].map(([id,category_id,kind,name,summary,price_minor]) => ({id,category_id,kind,name,summary,
  description:summary,price_minor,currency:'CNY',active:true,in_stock:true,version:1,is_demo:true,
  sections:[{title:'服务内容',body:summary},{title:'购买与交付',body:'虚拟课程／服务，无物流。付款后由站方交付，买方确认完成后评价。'}], image:''}));
function mutationKey() { return 'mini-shop-'+Date.now().toString(36)+'-'+Math.random().toString(36).slice(2); }
function validProduct(p) { return p && typeof p.id === 'string' && typeof p.name === 'string' && Number.isSafeInteger(p.price_minor) && p.price_minor >= 0 && Number.isInteger(p.version) && p.version > 0 && typeof p.active === 'boolean' && typeof p.in_stock === 'boolean' && Array.isArray(p.sections); }
function validOrder(o) { return o && typeof o.id === 'string' && typeof o.owner_id === 'string' && Number.isInteger(o.version) && validProduct(o.product_snapshot) && Number.isSafeInteger(o.amount_minor) && ['pending_payment','pending_completion','pending_review','completed','cancelled'].includes(o.status); }
function check(value, predicate) { if (!predicate(value)) throw new ApiError('unexpected_response',502); return value; }
const bannerSeeds = [
  {id:'local-guide',title:'bannerGuide',image:'/Assets/Banners/graduation.png',target_url:'',active:true,sort_order:0,version:1},
  {id:'local-service',title:'bannerService',image:'/Assets/Banners/journal.png',target_url:'',active:true,sort_order:1,version:1},
  {id:'local-progress',title:'bannerProgress',image:'/Assets/Banners/editing.png',target_url:'',active:true,sort_order:2,version:1},
];
function validLink(value) { return typeof value==='string' && /^https?:\/\/[^\s/]+(?:[/?#][^\s]*)?$/.test(value) && !/^https?:\/\/[^/]*@/i.test(value); }
function editableOrder(o) { return !!o && !o.accepted_at && o.fulfillment_status==='pending' && (o.status==='pending_payment'||o.status==='pending_completion') && o.editable===true; }
function validRequirements(details) { return ['requirements','contact','delivery_requirements'].every((field,index)=>typeof(details[field]||'')==='string'&&Array.from(details[field]||'').length<=[10000,200,2000][index]&&!(details[field]||'').includes('\0')); }
class ShopClient extends Client {
  constructor(wx) { super(wx); this.demoOrders=[]; this.shopOrders=[]; this.pendingShop=null; this.orderRead=0; this.config={demo_mode:false}; this.imageCache=new Map(); this.demoAccounts=new Map(); this.emailCodes=new Map(); }
  configure(base,timeoutMs=this.timeoutMs) { super.configure(base,timeoutMs); this.config={demo_mode:false}; this.bannerCache=undefined; this.demoAccounts.clear(); this.emailCodes.clear(); }
  logout() { super.logout(); this.shopOrders=[]; this.demoOrders=[]; this.pendingShop=null; this.shopLock=null; this.orderRead=(this.orderRead||0)+1; }
  async login(account,password,allowDemo=false) {
    account=account.trim();
    const credential=this.config.demo_mode && Array.isArray(this.config.demo_credentials) && this.config.demo_credentials.find(c=>c.account===account&&c.password===password);
    const saved=[...this.demoAccounts.values()].find(row=>(row.email===account.toLowerCase()||row.username.toLowerCase()===account.toLowerCase())&&row.password===password);
    const user = await super.login(account,password,!!(allowDemo&&this.config.demo_mode&&(credential||saved)));
    if(user.id==='demo') {
      if(saved){this.user={...saved};delete this.user.password;}
      else this.user={id:'demo',name:credential.account,username:credential.account,role:credential.role,avatar_url:'',avatar_color:['#905737','#4d7083','#627a51','#91648b'][Math.floor(Math.random()*4)]};
    }
    this.pendingShop = this.wx.getStorageSync(this.pendingName()) || null;
    return this.user;
  }
  authContext(generation,base) { if(generation!==this.generation||base!==this.base)throw new ApiError('accountChanged',409); }
  fallback(error) { return !error.status||error.status>=500; }
  validateAccount(username,password,confirmation) {
    if(password!==confirmation)throw new ApiError('passwordMismatch',422);
    if(Array.from(password).length<8||password.length>512)throw new ApiError('passwordTooShort',422);
    if(username&&(!/^[\p{L}\p{N}_-]{3,32}$/u.test(username)))throw new ApiError('invalidUsername',422);
  }
  async requestEmailCode(email,purpose) {
    email=email.trim().toLowerCase();const generation=this.generation,base=this.base;
    try {
      const result=await this.request('/auth/email-code','POST',{email,purpose});this.authContext(generation,base);
      if(result.demo_code&&this.config.demo_mode)this.emailCodes.set(email+':'+purpose,{code:result.demo_code,sent:Date.now(),attempts:0});
      return result;
    } catch(e) {
      this.authContext(generation,base);if(!this.config.demo_mode||!this.fallback(e))throw e;
      if(!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)||!['register','reset_password'].includes(purpose))throw new ApiError('invalidEmail',422);
      const key=email+':'+purpose,prior=this.emailCodes.get(key);
      if(prior&&Date.now()-prior.sent<60000)throw new ApiError('codeCooldown',429);
      const code=String(Math.floor(Math.random()*1000000)).padStart(6,'0');
      this.emailCodes.set(key,{code,sent:Date.now(),attempts:0});return {delivery:'demo',demo_code:code,retry_after:60,expires_in:600};
    }
  }
  verifyDemoCode(email,purpose,code) {
    const saved=this.emailCodes.get(email+':'+purpose);
    if(!saved||saved.attempts>=5||Date.now()-saved.sent>=600000||saved.code!==code){if(saved)saved.attempts++;throw new ApiError('invalidCode',422);}
  }
  async register({email,code,username,password,confirmPassword}) {
    email=email.trim().toLowerCase();username=username.trim();this.validateAccount(username,password,confirmPassword);if(!username)throw new ApiError('invalidUsername',422);
    const generation=this.generation,base=this.base;
    try{await this.request('/auth/register','POST',{email,code,username,password,confirm_password:confirmPassword});this.authContext(generation,base);}
    catch(e){this.authContext(generation,base);if(!this.config.demo_mode||!this.fallback(e))throw e;this.verifyDemoCode(email,'register',code);
      if(['admin','customer'].includes(username.toLowerCase())||[...this.demoAccounts.values()].some(row=>row.email===email||row.username.toLowerCase()===username.toLowerCase()))throw new ApiError('usernameTaken',409);
      this.demoAccounts.set(email,{id:'demo',name:username,username,email,password,role:'customer',avatar_url:'',avatar_color:['#905737','#4d7083','#627a51','#91648b'][Math.floor(Math.random()*4)]});this.emailCodes.delete(email+':register');}
    return this.login(email,password,this.config.demo_mode);
  }
  async resetPassword({email,code,password,confirmPassword}) {
    email=email.trim().toLowerCase();this.validateAccount('',password,confirmPassword);const generation=this.generation,base=this.base;
    try{await this.request('/auth/reset-password','POST',{email,code,password,confirm_password:confirmPassword});this.authContext(generation,base);}
    catch(e){this.authContext(generation,base);if(!this.config.demo_mode||!this.fallback(e))throw e;this.verifyDemoCode(email,'reset_password',code);const saved=this.demoAccounts.get(email);if(!saved)throw new ApiError('invalidCode',422);saved.password=password;this.emailCodes.delete(email+':reset_password');}
    this.logout();
  }
  async updateProfile(username,avatar) {
    this.requireUser();username=username.trim();this.validateAccount(username,'unused-password','unused-password');if(!username)throw new ApiError('invalidUsername',422);
    const generation=this.generation,base=this.base;
    try{const result=await this.request('/auth/profile','PUT',{username,...(avatar!==undefined?{avatar}:{})});this.authContext(generation,base);check(result.user,row=>row&&row.id===this.user.id&&typeof row.name==='string');this.user=result.user;}
    catch(e){this.authContext(generation,base);if(!this.config.demo_mode||this.token||!this.fallback(e))throw e;
      if([...this.demoAccounts.values()].some(row=>row.email!==this.user.email&&row.username.toLowerCase()===username.toLowerCase()))throw new ApiError('usernameTaken',409);
      this.user={...this.user,name:username,username,...(avatar!==undefined?{avatar_url:avatar}:{})};const saved=this.demoAccounts.get(this.user.email);if(saved)Object.assign(saved,this.user);}
    return this.user;
  }
  async avatarData(filePath,size) {
    if(size>2*1024*1024)throw new ApiError('avatarTooLarge',422);
    const manager=this.wx.getFileSystemManager();
    const data=await new Promise((resolve,reject)=>manager.readFile({filePath,encoding:'base64',success:r=>resolve(r.data),fail:reject}));
    const mime=data.startsWith('iVBOR')?'png':data.startsWith('/9j/')?'jpeg':data.startsWith('UklGR')?'webp':'';
    if(!mime||data.length>Math.ceil(2*1024*1024/3)*4)throw new ApiError('invalidAvatar',422);
    return 'data:image/'+mime+';base64,'+data;
  }
  async shopConfig() {
    const generation=this.generation;
    try {
      const r=await this.request('/shop-config');
      if(generation!==this.generation)throw new ApiError('state',409);
      check(r,c=>typeof c.demo_mode==='boolean'&&(!c.demo_mode||Array.isArray(c.demo_credentials)&&c.demo_credentials.every(v=>['customer','admin'].includes(v.role)&&typeof v.account==='string'&&typeof v.password==='string')));
      this.config={demo_mode:r.demo_mode,payment_mode:r.payment_mode,...(r.demo_mode?{demo_credentials:r.demo_credentials}:{})};return clone(this.config);
    } catch(e) { if(generation!==this.generation||e.status&&e.status<500)throw e; return clone(this.config); }
  }
  async banners() {
    const generation=this.generation,read=this.bannerRead=(this.bannerRead||0)+1;
    try {
      const r=await this.request('/banners');
      check(r.banners,v=>Array.isArray(v)&&v.every(b=>b&&typeof b.id==='string'&&typeof b.title==='string'&&typeof b.image==='string'&&typeof b.active==='boolean'&&(!b.target_url||validLink(b.target_url))));
      const active=r.banners.filter(b=>b.active).sort((a,b)=>(a.sort_order||0)-(b.sort_order||0));
      const prepared=await this.prepareImages(active);
      if(generation!==this.generation)throw new ApiError('state',409);
      if(read===this.bannerRead)this.bannerCache=prepared;
      return {banners:clone(prepared),bannerSource:'live'};
    } catch(e) { if(generation!==this.generation||e.status&&e.status<500)throw e; return this.bannerCache===undefined?{banners:clone(bannerSeeds),bannerSource:'local'}:{banners:clone(this.bannerCache),bannerSource:'stale'}; }
  }
  async imageSource(src) {
    if(typeof src!=='string'||!src.startsWith('data:'))return src||'';
    if(!/^data:image\/(png|jpeg|webp);base64,[A-Za-z0-9+/=]+$/.test(src))return '';
    if(!this.wx.getFileSystemManager||!this.wx.env)return '';
    if(this.imageCache.has(src))return this.imageCache.get(src);
    const parts=src.split(','),extension=parts[0].includes('jpeg')?'jpg':parts[0].includes('webp')?'webp':'png';
    const fs=this.wx.getFileSystemManager(),file=this.wx.env.USER_DATA_PATH+'/shop-image-'+mutationKey()+'.'+extension;
    try{await new Promise((resolve,reject)=>fs.writeFile({filePath:file,data:parts[1],encoding:'base64',success:resolve,fail:reject}));
      this.imageCache.set(src,file);
      if(this.imageCache.size>32){const [firstKey,firstFile]=this.imageCache.entries().next().value;this.imageCache.delete(firstKey);fs.unlink({filePath:firstFile,fail:()=>{}});}
      return file;
    }catch(e){return '';}
  }
  async prepareImages(items) { return Promise.all(items.map(async item=>({...item,image:await this.imageSource(item.image)}))); }
  pendingName() { return 'shopPending:'+this.base+':'+(this.user ? this.user.id : ''); }
  saveShopPending(value) { this.pendingShop=value; if (this.user && this.user.id !== 'demo') this.wx.setStorageSync(this.pendingName(),value||''); }
  async catalog(category='') {
    try {
      const r=await this.request('/products'+(category?'?category_id='+encodeURIComponent(category):''));
      check(r.products,items=>Array.isArray(items)&&items.every(validProduct));
      return {products:await this.prepareImages(r.products),source:'live'};
    } catch(e) {
      if (e.status && e.status<500) throw e;
      return {products:clone(seeds.filter(p=>!category||p.category_id===category)),source:'demo'};
    }
  }
  async product(id) {
    try { const r=await this.request('/products/'+encodeURIComponent(id));const p=check(r.product,validProduct);return {product:(await this.prepareImages([p]))[0],source:'live'}; }
    catch(e) {
      if(e.status && e.status<500) throw e;
      const product=seeds.find(p=>p.id===id); if(!product) throw new ApiError('state',404);
      return {product:clone(product),source:'demo'};
    }
  }
  requireUser() { if(!this.user) throw new ApiError('signInFirst',401); }
  owns(o) { return validOrder(o) && this.user && (this.user.role==='admin'||o.owner_id===this.user.id); }
  matchesWrite(o,path,body) {
    if(!this.owns(o))return false;
    if(path==='/shop-orders')return o.product_snapshot.id===body.product_id&&o.product_snapshot.version===body.product_version;
    return o.id===decodeURIComponent(path.split('/')[2]);
  }
  async orders() {
    this.requireUser(); const generation=this.generation,read=++this.orderRead;
    try {
      const r=await this.request('/shop-orders'); check(r.orders,v=>Array.isArray(v)&&v.every(o=>this.owns(o)));
      if(generation!==this.generation) throw new ApiError('state',409);
      if(read===this.orderRead) this.shopOrders=r.orders;
      return {orders:clone(this.shopOrders),source:'live'};
    } catch(e) {
      if(generation!==this.generation || (e.status && e.status<500)) throw e;
      if(read===this.orderRead) this.shopOrders=clone(this.demoOrders);
      return {orders:clone(this.shopOrders),source:'demo'};
    }
  }
  async order(id) {
    this.requireUser();
    try { const r=await this.request('/shop-orders/'+encodeURIComponent(id)); return {order:check(r.order,o=>this.owns(o)),source:'live'}; }
    catch(e) {
      if(e.status && e.status<500) throw e;
      const order=this.demoOrders.find(o=>o.id===id); if(!order) throw e;
      return {order:clone(order),source:'demo'};
    }
  }
  async create(product,details={}) {
    if(!validProduct(product)||!product.active||!product.in_stock) throw new ApiError('outOfStock',422);
    if(!validRequirements(details))throw new ApiError('required',422);
    const fields={};for(const field of ['requirements','contact','delivery_requirements'])if(typeof details[field]==='string')fields[field]=details[field];
    return this.shopWrite('/shop-orders',{product_id:product.id,product_version:product.version,...fields},product);
  }
  async action(order,action,extras={}) {
    if(action==='edit'&&!editableOrder(order))throw new ApiError('orderLocked',409);
    if(action==='edit'&&!validRequirements(extras))throw new ApiError('required',422);
    return this.shopWrite('/shop-orders/'+encodeURIComponent(order.id)+'/actions',{action,expected_version:order.version,...extras});
  }
  async shopWrite(path,body,product) {
    this.requireUser(); if(this.pendingShop||this.shopLock) throw new ApiError('pendingWrite',409);
    const lock=this.shopLock={};
    const generation=this.generation,requestKey=mutationKey(),isolated=this.user.id==='demo';
    try {
      const r=await this.request(path,'POST',body,requestKey); check(r.order,o=>this.matchesWrite(o,path,body));
      if(generation!==this.generation) throw new ApiError('state',409);
      this.orderRead++; this.shopOrders=[r.order,...this.shopOrders.filter(o=>o.id!==r.order.id)];
      return {order:r.order,source:'live'};
    } catch(e) {
      if(generation!==this.generation || (e.status && e.status<500)) throw e;
      if(isolated) return {order:this.demoWriteShop(path,body,product),source:'demo'};
      this.saveShopPending({key:requestKey,path,body}); throw new ApiError('pendingWrite',503);
    } finally { if(this.shopLock===lock)this.shopLock=null; }
  }
  demoWriteShop(path,body,product) {
    let order;
    if(path==='/shop-orders') {
      order={id:'demo-'+mutationKey(),owner_id:'demo',product_snapshot:clone(product),quantity:1,
        amount_minor:product.price_minor,currency:'CNY',status:'pending_payment',fulfillment_status:'pending',
        seller_status:'awaiting_payment',version:1,created_at:new Date().toISOString(),payment:null,review:null,delivery_text:'',requirements:body.requirements||'',contact:body.contact||'',delivery_requirements:body.delivery_requirements||'',accepted_at:'',editable:true};
    } else {
      const id=decodeURIComponent(path.split('/')[2]);
      order=clone(this.demoOrders.find(o=>o.id===id)||null); if(!order||order.version!==body.expected_version) throw new ApiError('version',409);
      if(body.action==='pay' && order.status==='pending_payment' && ['alipay','wechat'].includes(body.channel)) {
        order.status='pending_completion'; order.payment={id:mutationKey(),mode:'mock',channel:body.channel,status:'succeeded',amount_minor:order.amount_minor,currency:'CNY',reference:'MOCK-'+mutationKey()};
      } else if(body.action==='edit'&&editableOrder(order)) {
        for(const field of ['requirements','contact','delivery_requirements'])order[field]=body[field]||'';
      } else if(body.action==='cancel' && order.status==='pending_payment') order.status='cancelled';
      else if(body.action==='accept' && order.status==='pending_completion' && order.fulfillment_status==='delivered') order.status='pending_review';
      else if(body.action==='review' && order.status==='pending_review' && Number.isInteger(body.rating) && body.rating>=1 && body.rating<=5 && body.text.trim()) {
        order.status='completed'; order.review={rating:body.rating,text:body.text,created_at:new Date().toISOString()};
      } else throw new ApiError('state',422);
      order.version++;
      order.editable=editableOrder(order);
    }
    order.seller_status=order.status==='pending_payment'?'awaiting_payment':order.status==='pending_completion'?(order.fulfillment_status==='delivered'?'awaiting_confirmation':order.fulfillment_status==='in_progress'?'in_progress':'pending_delivery'):order.status==='pending_review'?'awaiting_review':order.status;
    this.demoOrders=[order,...this.demoOrders.filter(o=>o.id!==order.id)]; this.shopOrders=clone(this.demoOrders); this.orderRead++;
    return clone(order);
  }
  async reconcileShop() {
    this.requireUser(); if(!this.pendingShop) return null;
    const pending=this.pendingShop,r=await this.request('/shop-operations/'+encodeURIComponent(pending.key));
    if(!r.operation || r.operation.status!=='succeeded'||r.operation.resource_type!=='order'||r.operation.resource_id!==r.order?.id||r.operation.action!==(pending.path==='/shop-orders'?'create_order':pending.body.action)) throw new ApiError('pendingWrite',502);
    check(r.order,o=>this.matchesWrite(o,pending.path,pending.body)); this.saveShopPending(null); this.orderRead++;
    this.shopOrders=[r.order,...this.shopOrders.filter(o=>o.id!==r.order.id)];
    return r.order;
  }
  async retryShop() {
    this.requireUser(); if(!this.pendingShop) return null;
    const p=this.pendingShop,r=await this.request(p.path,'POST',p.body,p.key);
    check(r.order,o=>this.matchesWrite(o,p.path,p.body)); this.saveShopPending(null); this.orderRead++;this.shopOrders=[r.order,...this.shopOrders.filter(o=>o.id!==r.order.id)];return r.order;
  }
}
module.exports={ShopClient,seeds,validProduct,validOrder,bannerSeeds,validLink,editableOrder};
