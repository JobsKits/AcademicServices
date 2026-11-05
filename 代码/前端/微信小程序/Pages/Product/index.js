// Created by Jobs. Product snapshot is confirmed before an order is created.
const {definePage,productView}=require('../../Utils/ui');
Page(definePage('details',{product:null,source:'demo'}, {
  onLoad(options){this.productId=options.id;},
  onShow(){return this.reload();},
  async reload(){const id=this.readId=(this.readId||0)+1;try{const r=await getApp().api.product(this.productId);if(id===this.readId)this.setData({...r,product:productView(r.product),failedImages:{},error:''});}catch(e){if(id===this.readId)this.fail(e);}},
  async buy(){if(this.data.busy)return;if(!getApp().api.user){this.login();return;}this.setData({busy:true,error:''});try{const r=await getApp().api.create(this.data.product);wx.navigateTo({url:'/Pages/Order/index?id='+encodeURIComponent(r.order.id)+'&checkout=1'});}catch(e){this.fail(e);}finally{this.setData({busy:false});}},
}));
