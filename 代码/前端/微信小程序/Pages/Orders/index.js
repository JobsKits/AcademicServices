// Created by Jobs. Transaction states are buyer filters; fulfillment is separate.
const {definePage,orderView,keepLive}=require('../../Utils/ui');
Page(definePage('orders',{orders:[],visibleOrders:[],filter:'',source:'demo',pending:false,states:['pending_payment','pending_completion','pending_review','completed']}, {
  onShow(){if(!getApp().api.user)this.login();if(typeof getApp().orderFilter==='string'){this.setData({filter:getApp().orderFilter});delete getApp().orderFilter;}return this.reload();},
  async reload(){const api=getApp().api,id=this.readId=(this.readId||0)+1;this.setData({pending:!!api.pendingShop,user:api.user});if(!api.user){this.viewerId=null;this.setData({orders:[],visibleOrders:[],error:this.data.t.signInFirst});return;}if(this.viewerId&&this.viewerId!==api.user.id)this.setData({orders:[],visibleOrders:[]});this.viewerId=api.user.id;try{const r=await api.orders();if(id===this.readId){if(keepLive(r.source,this.data.source,this.data.orders.length>0))this.setData({source:'stale',error:''});else this.setData({...r,orders:r.orders.map(orderView),error:''});this.filterOrders();}}catch(e){if(id===this.readId){if([401,403,404].includes(e.status))this.setData({orders:[],visibleOrders:[],pending:false});this.fail(e);}}},
  filter(e){this.setData({filter:e.currentTarget.dataset.id});this.filterOrders();},
  filterOrders(){this.setData({visibleOrders:this.data.orders.filter(o=>!this.data.filter||o.status===this.data.filter)});},
  detail(e){wx.navigateTo({url:'/Pages/Order/index?id='+encodeURIComponent(e.currentTarget.dataset.id)});},
  async reconcile(){if(this.data.busy)return;this.setData({busy:true});try{await getApp().api.reconcileShop();await this.reload();}catch(e){this.fail(e);}finally{this.setData({busy:false,pending:!!getApp().api.pendingShop});}},
  async retry(){if(this.data.busy)return;this.setData({busy:true});try{await getApp().api.retryShop();await this.reload();}catch(e){this.fail(e);}finally{this.setData({busy:false,pending:!!getApp().api.pendingShop});}},
}));
