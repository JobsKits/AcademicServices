// Created by Jobs. Home and category child pages use the same native layout.
const {definePage,productView}=require('../../Utils/ui');
Page(definePage('shop',{products:[],category:'',source:'demo',categories:['graduation','journal','editing']}, {
  onLoad(options){this.setData({category:options.category||''});},
  onShow(){return this.reload();},
  async reload(){const id=this.readId=(this.readId||0)+1;try{const r=await getApp().api.catalog(this.data.category);if(id===this.readId)this.setData({...r,products:r.products.map(productView),failedImages:{},error:''});}catch(e){if(id===this.readId)this.fail(e);}},
  category(e){wx.navigateTo({url:'/Pages/Shop/index?category='+e.currentTarget.dataset.id});},
  product(e){wx.navigateTo({url:'/Pages/Product/index?id='+encodeURIComponent(e.currentTarget.dataset.id)});},
}));
