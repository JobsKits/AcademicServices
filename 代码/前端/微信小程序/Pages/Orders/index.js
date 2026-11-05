// Created by Jobs. Transaction states are buyer filters; fulfillment is separate.
const {definePage,orderView}=require('../../Utils/ui');
Page(definePage('orders',{orders:[],visibleOrders:[],filter:'',source:'demo',pending:false,states:['pending_payment','pending_completion','pending_review','completed']}, {
  onShow(){return this.reload();},
  async reload(){const id=this.readId=(this.readId||0)+1;this.setData({pending:!!getApp().api.pendingShop});if(!getApp().api.user){this.setData({orders:[],visibleOrders:[],error:this.data.t.signInFirst});return;}try{const r=await getApp().api.orders();if(id===this.readId){this.setData({...r,orders:r.orders.map(orderView),error:''});this.filterOrders();}}catch(e){if(id===this.readId)this.fail(e);}},
  filter(e){this.setData({filter:e.currentTarget.dataset.id});this.filterOrders();},
  filterOrders(){this.setData({visibleOrders:this.data.orders.filter(o=>!this.data.filter||o.status===this.data.filter)});},
  detail(e){wx.navigateTo({url:'/Pages/Order/index?id='+encodeURIComponent(e.currentTarget.dataset.id)});},
  async reconcile(){if(this.data.busy)return;this.setData({busy:true});try{await getApp().api.reconcileShop();await this.reload();}catch(e){this.fail(e);}finally{this.setData({busy:false,pending:!!getApp().api.pendingShop});}},
  async retry(){if(this.data.busy)return;this.setData({busy:true});try{await getApp().api.retryShop();await this.reload();}catch(e){this.fail(e);}finally{this.setData({busy:false,pending:!!getApp().api.pendingShop});}},
}));
