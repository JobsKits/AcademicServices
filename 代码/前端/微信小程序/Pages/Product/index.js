// Created by Jobs. Product snapshot is confirmed before an order is created.
const {definePage,productView,keepLive}=require('../../Utils/ui');
Page(definePage('details',{product:null,source:'demo',requirements:'',contact:'',delivery_requirements:''}, {
  onLoad(options){this.productId=options.id;},
  onShow(){return this.reload();},
  async reload(){const id=this.readId=(this.readId||0)+1;try{const r=await getApp().api.product(this.productId);if(id===this.readId){if(keepLive(r.source,this.data.source,!!this.data.product))this.setData({source:'stale',error:''});else this.setData({...r,product:productView(r.product),failedImages:{},error:''});}}catch(e){if(id===this.readId){if([403,404].includes(e.status))this.setData({product:null});this.fail(e);}}},
  input(e){this.setData({[e.currentTarget.dataset.field]:e.detail.value});},
  async buy(){if(this.data.busy)return;if(!getApp().api.user){this.login();return;}if(getApp().api.user.role!=='customer'){this.setData({error:this.data.t.sellerReadOnly});return;}this.setData({busy:true,error:''});try{const r=await getApp().api.create(this.data.product,{requirements:this.data.requirements,contact:this.data.contact,delivery_requirements:this.data.delivery_requirements});wx.navigateTo({url:'/Pages/Order/index?id='+encodeURIComponent(r.order.id)+'&checkout=1'});}catch(e){this.fail(e);}finally{this.setData({busy:false});}},
}));
