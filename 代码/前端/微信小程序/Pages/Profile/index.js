// Created by Jobs. Customer identity and four order shortcuts share one profile.
const {definePage}=require('../../Utils/ui');
Page(definePage('mine',{counts:{},states:[
  {id:'pending_payment',icon:'credit-card'},{id:'pending_completion',icon:'clock'},
  {id:'pending_review',icon:'star'},{id:'completed',icon:'check-circle'},
]},{
  onShow(){if(!getApp().api.user){this.setData({user:null,counts:{}});wx.switchTab({url:'/Pages/Shop/index',success:()=>wx.navigateTo({url:'/Pages/Login/index?next=profile'})});return;}return this.reload();},
  async reload(){const api=getApp().api,id=this.readId=(this.readId||0)+1;this.setData({user:api.user,failedImages:{},error:''});if(!api.user){this.setData({counts:{}});return;}try{const result=await api.orders();if(id!==this.readId)return;const counts={};result.orders.forEach(o=>counts[o.status]=(counts[o.status]||0)+1);this.setData({counts});}catch(e){if(id===this.readId){this.setData({counts:{},user:api.user});this.fail(e);}}},
  orderStatus(e){if(!this.requireUser())return;getApp().orderFilter=e.currentTarget.dataset.id;wx.switchTab({url:'/Pages/Orders/index'});},
}));
