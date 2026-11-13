// Created by Jobs. Profile edits publish immediately; connection controls belong to Demo.
const {definePage,locales}=require('../../Utils/ui');
const {preferences,intervals}=require('../../Utils/carousel');
Page(definePage('settings',{base:'',timeoutMs:2500,demoMode:false,username:''}, {
  async onShow(){const api=getApp().api,prefs=preferences(wx);this.setData({base:api.base,timeoutMs:api.timeoutMs,demoMode:false,username:api.user?(api.user.username||api.user.name):'',...prefs,intervalLabels:intervals.map(ms=>String(ms/1000)),intervalIndex:intervals.indexOf(prefs.carouselInterval)});if(api.shopConfig){try{const config=await api.shopConfig();this.setData({demoMode:config.demo_mode===true});}catch(e){this.fail(e);}}},
  autoplay(e){wx.setStorageSync('shopCarouselEnabled',e.detail.value===true);this.setData(preferences(wx));},
  motion(e){wx.setStorageSync('shopReduceMotion',e.detail.value===true);this.setData(preferences(wx));},
  interval(e){const index=Number(e.detail.value);if(intervals[index]){wx.setStorageSync('shopCarouselInterval',intervals[index]);this.setData({carouselInterval:intervals[index],intervalIndex:index});}},
  language(e){wx.setStorageSync('shopLocale',locales[Number(e.detail.value)]);this.applyAppearance();},
  theme(e){wx.setStorageSync('shopTheme',['system','light','dark'][Number(e.detail.value)]);this.applyAppearance();},
  input(e){this.setData({[e.currentTarget.dataset.field]:e.detail.value});},
  save(){if(!this.data.demoMode)return;try{getApp().api.configure(this.data.base,this.data.timeoutMs);this.setData({error:''});this.applyAppearance();wx.showToast({title:this.data.t.save,icon:'success'});}catch(e){this.setData({error:this.data.t.required});}},
  async saveProfile(){if(this.data.busy)return;if(!this.requireUser())return;this.setData({busy:true,error:''});try{await getApp().api.updateProfile(this.data.username);this.applyAppearance();wx.showToast({title:this.data.t.save,icon:'success'});}catch(e){this.fail(e);}finally{this.setData({busy:false});}},
  async avatar(){
    if(this.data.busy||!this.requireUser())return;
    const api=getApp().api,generation=api.generation,base=api.base;
    try{
      const chosen=await new Promise((resolve,reject)=>{
        if(wx.chooseMedia)wx.chooseMedia({count:1,mediaType:['image'],sizeType:['compressed'],sourceType:['album','camera'],success:r=>resolve({path:r.tempFiles[0].tempFilePath,size:r.tempFiles[0].size}),fail:reject});
        else wx.chooseImage({count:1,sizeType:['compressed'],success:r=>resolve({path:r.tempFilePaths[0],size:r.tempFiles&&r.tempFiles[0].size}),fail:reject});
      });
      api.authContext(generation,base);this.setData({busy:true,error:''});
      const avatar=await api.avatarData(chosen.path,chosen.size);api.authContext(generation,base);
      await api.updateProfile(this.data.username,avatar);this.applyAppearance();wx.showToast({title:this.data.t.save,icon:'success'});
    }catch(e){if(!/cancel/i.test(e.errMsg||''))this.fail(e);}finally{this.setData({busy:false});}
  },
  logout(){getApp().api.logout();this.applyAppearance();this.setData({username:''});},
}));
