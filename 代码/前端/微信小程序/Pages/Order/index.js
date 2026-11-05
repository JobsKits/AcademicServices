// Created by Jobs. Cashier changes order state only after explicit confirmation.
const {definePage,orderView}=require('../../Utils/ui');
Page(definePage('orders',{order:null,source:'demo',cashier:false,channel:'alipay',rating:5,text:'',ratings:[1,2,3,4,5]}, {
  onLoad(options){this.orderId=options.id;this.openCheckout=options.checkout==='1';},
  onShow(){return this.reload();},
  async reload(){const api=getApp().api,id=this.readId=(this.readId||0)+1;if(!api.user){this.setData({order:null,cashier:false,error:this.data.t.signInFirst});return;}if(this.data.order&&this.data.order.owner_id!==api.user.id)this.setData({order:null,cashier:false});try{const r=await api.order(this.orderId);if(id===this.readId){this.setData({...r,order:orderView(r.order),error:'',cashier:this.openCheckout&&r.order.status==='pending_payment'});this.openCheckout=false;}}catch(e){if(id===this.readId){if(e.status===401)this.setData({order:null,cashier:false});this.fail(e);}}},
  openCashier(){this.setData({cashier:true,error:''});},
  closeCashier(){if(!this.data.busy)this.setData({cashier:false});},
  noop(){},
  channel(e){this.setData({channel:e.currentTarget.dataset.id});},
  text(e){this.setData({text:e.detail.value});},
  rating(e){this.setData({rating:Number(e.detail.value)+1});},
  async pay(){return this.perform('pay',{channel:this.data.channel});},
  async cancel(){return this.perform('cancel');},
  async accept(){return this.perform('accept');},
  async review(){if(!this.data.text.trim()){this.setData({error:this.data.t.required});return;}return this.perform('review',{text:this.data.text.trim(),rating:this.data.rating});},
  async perform(action,extras={}){if(this.data.busy||!this.data.order)return;this.setData({busy:true,error:''});try{const r=await getApp().api.action(this.data.order,action,extras);this.setData({...r,order:orderView(r.order),cashier:false});}catch(e){this.fail(e);}finally{this.setData({busy:false});}},
}));
