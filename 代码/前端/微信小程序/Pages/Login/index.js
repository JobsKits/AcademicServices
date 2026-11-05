// Created by Jobs. Password rejection stays a server error; offline demo is isolated.
const {definePage}=require('../../Utils/ui');
Page(definePage('account',{account:'customer',password:''},{
  input(e){this.setData({[e.currentTarget.dataset.field]:e.detail.value});},
  async submit(){return this.authenticate(this.data.account,this.data.password);},
  async demo(){return this.authenticate('customer','demo-customer');},
  async authenticate(account,password){if(this.data.busy)return;this.setData({busy:true,error:''});try{await getApp().api.login(account,password,true);this.setData({password:''});wx.navigateBack();}catch(e){this.fail(e);}finally{this.setData({busy:false});}},
  logout(){getApp().api.logout();this.setData({password:'',error:''});this.applyAppearance();},
}));
