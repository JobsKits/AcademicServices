// Created by Jobs. Shared native tab routes with localized icon labels.
Component({
  data:{selected:0,theme:'light',t:require('../Utils/strings.json').zh,tabs:[
    {path:'/Pages/Shop/index',label:'home',icon:'home'},
    {path:'/Pages/Orders/index',label:'myOrders',icon:'shopping-bag'},
    {path:'/Pages/Profile/index',label:'mine',icon:'user'},
  ]},
  methods:{select(e){const index=Number(e.currentTarget.dataset.index);if(!this.data.tabs[index])return;if(index>0&&!getApp().api.user){wx.navigateTo({url:'/Pages/Login/index?next='+(index===2?'profile':'orders')});return;}wx.switchTab({url:this.data.tabs[index].path});}},
});
