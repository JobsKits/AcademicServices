// Created by Jobs. WeChat business-domain restrictions require an explicit copy fallback.
const {definePage}=require('../../Utils/ui');
const {validLink}=require('../../Utils/shop');
Page(definePage('openWebView',{url:'',showWeb:false},{
  onLoad(options){let url='';try{url=decodeURIComponent(options.url||'');}catch(e){}if(validLink(url)&&url.startsWith('https://'))this.setData({url,showWeb:true});else this.setData({url:validLink(url)?url:'',showWeb:false});},
  failed(){this.setData({showWeb:false});},
  copy(){if(!this.data.url)return;wx.setClipboardData({data:this.data.url,success:()=>wx.showToast({title:this.data.t.copied,icon:'success'})});},
}));
