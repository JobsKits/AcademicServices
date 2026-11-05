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
class ShopClient extends Client {
  constructor(wx) { super(wx); this.demoOrders=[]; this.shopOrders=[]; this.pendingShop=null; this.orderRead=0; }
  logout() { super.logout(); this.shopOrders=[]; this.demoOrders=[]; this.pendingShop=null; this.shopLock=null; this.orderRead=(this.orderRead||0)+1; }
  async login(account,password,allowDemo=true) {
    const user = await super.login(account,password,allowDemo);
    this.pendingShop = this.wx.getStorageSync(this.pendingName()) || null;
    return user;
  }
  pendingName() { return 'shopPending:'+this.base+':'+(this.user ? this.user.id : ''); }
  saveShopPending(value) { this.pendingShop=value; if (this.user && this.user.id !== 'demo') this.wx.setStorageSync(this.pendingName(),value||''); }
  async catalog(category='') {
    try {
      const r=await this.request('/products'+(category?'?category_id='+encodeURIComponent(category):''));
      check(r.products,items=>Array.isArray(items)&&items.every(validProduct));
      return {products:r.products,source:'live'};
    } catch(e) {
      if (e.status && e.status<500) throw e;
      return {products:clone(seeds.filter(p=>!category||p.category_id===category)),source:'demo'};
    }
  }
  async product(id) {
    try { const r=await this.request('/products/'+encodeURIComponent(id)); return {product:check(r.product,validProduct),source:'live'}; }
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
  async create(product) {
    if(!validProduct(product)||!product.active||!product.in_stock) throw new ApiError('outOfStock',422);
    return this.shopWrite('/shop-orders',{product_id:product.id,product_version:product.version},product);
  }
  async action(order,action,extras={}) {
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
        seller_status:'awaiting_payment',version:1,created_at:new Date().toISOString(),payment:null,review:null,delivery_text:''};
    } else {
      const id=decodeURIComponent(path.split('/')[2]);
      order=clone(this.demoOrders.find(o=>o.id===id)||null); if(!order||order.version!==body.expected_version) throw new ApiError('version',409);
      if(body.action==='pay' && order.status==='pending_payment' && ['alipay','wechat'].includes(body.channel)) {
        order.status='pending_completion'; order.payment={id:mutationKey(),mode:'mock',channel:body.channel,status:'succeeded',amount_minor:order.amount_minor,currency:'CNY',reference:'MOCK-'+mutationKey()};
      } else if(body.action==='cancel' && order.status==='pending_payment') order.status='cancelled';
      else if(body.action==='accept' && order.status==='pending_completion' && order.fulfillment_status==='delivered') order.status='pending_review';
      else if(body.action==='review' && order.status==='pending_review' && Number.isInteger(body.rating) && body.rating>=1 && body.rating<=5 && body.text.trim()) {
        order.status='completed'; order.review={rating:body.rating,text:body.text,created_at:new Date().toISOString()};
      } else throw new ApiError('state',422);
      order.version++;
    }
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
module.exports={ShopClient,seeds,validProduct,validOrder};
