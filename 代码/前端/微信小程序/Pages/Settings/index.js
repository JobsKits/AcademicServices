// Created by Jobs. Preferences remain local; connection edits reset the session.
const {definePage,locales}=require('../../Utils/ui');
Page(definePage('settings',{base:'',timeoutMs:2500}, {
  onShow(){this.setData({base:getApp().api.base,timeoutMs:getApp().api.timeoutMs});},
  language(e){wx.setStorageSync('shopLocale',locales[Number(e.detail.value)]);this.applyAppearance();},
  theme(e){wx.setStorageSync('shopTheme',['system','light','dark'][Number(e.detail.value)]);this.applyAppearance();},
  input(e){this.setData({[e.currentTarget.dataset.field]:e.detail.value});},
  save(){try{getApp().api.configure(this.data.base,this.data.timeoutMs);this.setData({error:''});this.applyAppearance();wx.showToast({title:this.data.t.save,icon:'success'});}catch(e){this.setData({error:this.data.t.required});}},
}));
