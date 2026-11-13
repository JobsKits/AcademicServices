// Created by Jobs. Cashier changes order state only after explicit confirmation.
const {definePage,orderView}=require('../../Utils/ui');
const {editableOrder}=require('../../Utils/shop');
Page(definePage('orders',{order:null,source:'demo',cashier:false,channel:'alipay',rating:5,text:'',ratings:[1,2,3,4,5],editing:false,requirements:'',contact:'',delivery_requirements:''}, {
  onLoad(options){this.orderId=options.id;this.openCheckout=options.checkout==='1';},
  onShow(){if(!getApp().api.user)this.login();return this.reload();},
  async reload(){const api=getApp().api,id=this.readId=(this.readId||0)+1;this.setData({user:api.user});if(!api.user){this.setData({order:null,cashier:false,error:this.data.t.signInFirst});return;}if(this.formOwner&&this.formOwner!==api.user.id){this.formOwner=null;this.setData({editing:false,requirements:'',contact:'',delivery_requirements:'',text:''});}if(this.data.order&&api.user.role!=='admin'&&this.data.order.owner_id!==api.user.id)this.setData({order:null,cashier:false});try{const r=await api.order(this.orderId);if(id===this.readId){this.setData({...r,order:orderView(r.order),error:'',cashier:this.openCheckout&&r.order.status==='pending_payment'});this.openCheckout=false;}}catch(e){if(id===this.readId){if([401,403,404].includes(e.status))this.setData({order:null,cashier:false});this.fail(e);}}},
  openCashier(){this.setData({cashier:true,error:''});},
  closeCashier(){if(!this.data.busy)this.setData({cashier:false});},
  noop(){},
  channel(e){this.setData({channel:e.currentTarget.dataset.id});},
  text(e){this.formOwner=getApp().api.user?getApp().api.user.id:null;this.setData({text:e.detail.value});},
  rating(e){this.setData({rating:Number(e.detail.value)+1});},
  input(e){this.setData({[e.currentTarget.dataset.field]:e.detail.value});},
  edit(){if(getApp().api.user&&getApp().api.user.role!=='customer'){this.setData({error:this.data.t.sellerReadOnly});return;}if(!editableOrder(this.data.order)){this.setData({editing:false,error:this.data.t.orderLocked});return;}const o=this.data.order;this.formOwner=getApp().api.user?getApp().api.user.id:o.owner_id;this.setData({editing:true,requirements:o.requirements||'',contact:o.contact||'',delivery_requirements:o.delivery_requirements||'',error:''});},
  closeEdit(){if(!this.data.busy)this.setData({editing:false});},
  async saveRequirements(){if(!editableOrder(this.data.order)){this.setData({editing:false,error:this.data.t.orderLocked});return;}await this.perform('edit',{requirements:this.data.requirements,contact:this.data.contact,delivery_requirements:this.data.delivery_requirements});},
  async pay(){return this.perform('pay',{channel:this.data.channel});},
  async cancel(){return this.perform('cancel');},
  async accept(){return this.perform('accept');},
  async review(){if(!this.data.text.trim()){this.setData({error:this.data.t.required});return;}return this.perform('review',{text:this.data.text.trim(),rating:this.data.rating});},
  async perform(action,extras={}){if(this.data.busy||!this.data.order)return;if(getApp().api.user&&getApp().api.user.role!=='customer'){this.setData({error:this.data.t.sellerReadOnly});return;}this.setData({busy:true,error:''});try{const r=await getApp().api.action(this.data.order,action,extras);this.setData({...r,order:orderView(r.order),cashier:false,editing:false});}catch(e){if([401,403,404].includes(e.status))this.setData({order:null,cashier:false});this.fail(e);}finally{this.setData({busy:false});}},
}));
