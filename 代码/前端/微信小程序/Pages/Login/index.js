// Created by Jobs. Login, registration and password recovery share one account door.
const {definePage}=require('../../Utils/ui');
Page(definePage('account',{authMode:'login',account:'',email:'',username:'',code:'',password:'',confirmPassword:'',demoMode:false,credentials:[],sendingCode:false,notice:'',cooldown:0},{
  onLoad(options){if(options&&['login','register','reset'].includes(options.mode))this.setData({authMode:options.mode});this.returnTab=options&&options.next==='profile'?'/Pages/Profile/index':options&&options.next==='orders'?'/Pages/Orders/index':null;},
  async onShow(){this.setData({demoMode:false,credentials:[]});const id=this.configRead=(this.configRead||0)+1;try{const api=getApp().api;if(!api.shopConfig)return;const config=await api.shopConfig();if(id===this.configRead)this.setData({demoMode:config.demo_mode,credentials:config.demo_mode?config.demo_credentials:[]});}catch(e){if(id===this.configRead)this.fail(e);}},
  onUnload(){this.destroyed=true;this.configRead=(this.configRead||0)+1;if(this.codeTimer)clearInterval(this.codeTimer);},
  mode(e){if(this.data.busy||this.data.sendingCode)return;const mode=e.currentTarget.dataset.mode;if(['login','register','reset'].includes(mode))this.setData({authMode:mode,error:'',notice:''});},
  input(e){this.setData({[e.currentTarget.dataset.field]:e.detail.value});},
  async sendCode(){
    if(this.data.sendingCode||this.data.cooldown>0)return;
    this.setData({sendingCode:true,error:'',notice:''});
    try{const r=await getApp().api.requestEmailCode(this.data.email,this.data.authMode==='register'?'register':'reset_password');if(this.destroyed)return;
      this.setData({notice:r.delivery==='demo'?this.data.t.demoEmailCode+': '+r.demo_code:this.data.t.codeSent,cooldown:60});
      if(this.codeTimer)clearInterval(this.codeTimer);
      this.codeTimer=setInterval(()=>{this.setData({cooldown:Math.max(0,this.data.cooldown-1)});if(!this.data.cooldown){clearInterval(this.codeTimer);this.codeTimer=null;}},1000);
    }catch(e){if(!this.destroyed)this.fail(e);}finally{if(!this.destroyed)this.setData({sendingCode:false});}
  },
  async submit(){
    if(this.data.busy)return;
    const {authMode,account,email,username,code,password,confirmPassword}=this.data;
    if(!password||(authMode==='login'?!account:!email||!code||!confirmPassword||authMode==='register'&&!username)){this.setData({error:this.data.t.required});return;}
    this.setData({busy:true,error:'',notice:''});
    try{
      const api=getApp().api;
      if(authMode==='login')await api.login(account,password,this.data.demoMode);
      else if(authMode==='register')await api.register({email,code,username,password,confirmPassword});
      else{await api.resetPassword({email,code,password,confirmPassword});this.setData({authMode:'login',account:email,password:'',confirmPassword:'',code:'',notice:this.data.t.passwordReset});return;}
      if(this.destroyed)return;this.setData({password:'',confirmPassword:'',code:''});wx.showToast({title:this.data.t.signedIn,icon:'success'});if(this.returnTab)wx.switchTab({url:this.returnTab});else wx.navigateBack({fail:()=>wx.switchTab({url:'/Pages/Shop/index'})});
    }catch(e){if(e.status===401)this.setData({error:this.data.t.invalidCredentials});else this.fail(e);}finally{this.setData({busy:false});}
  },
  copyCredential(e){if(!this.data.demoMode)return;const credential=this.data.credentials[Number(e.currentTarget.dataset.index)],field=e.currentTarget.dataset.field;if(!credential||!['role','account','password'].includes(field))return;wx.setClipboardData({data:credential[field],success:()=>wx.showToast({title:this.data.t.copied,icon:'success'})});},
  logout(){getApp().api.logout();this.setData({password:'',error:''});this.applyAppearance();},
}));
