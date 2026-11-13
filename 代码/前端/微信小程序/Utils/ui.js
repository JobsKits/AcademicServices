// Created by Jobs. Shared locale and appearance for every storefront page.
const strings=require('./strings.json');
const languages=['简体中文','繁體中文','བོད་ཡིག','English','日本語','Français','Español','Deutsch','Русский','한국어'];
const locales=['zh','zh-Hant','bo','en','ja','fr','es','de','ru','ko'];
function appearance(wx,app) {
  const saved=wx.getStorageSync('shopLocale'),locale=locales.includes(saved)?saved:'zh';
  const chosen=wx.getStorageSync('shopTheme'),preference=['light','dark','system'].includes(chosen)?chosen:'system';
  const t=strings[locale],theme=preference==='system'?(app.systemTheme||'light'):preference;
  return {t,locale,theme,preference,languages,languageIndex:locales.indexOf(locale),themeIndex:['system','light','dark'].indexOf(preference),themes:[t.system,t.light,t.dark]};
}
function money(amount) { return '¥'+(amount/100).toFixed(2); }
function productView(p) { return {...p,amount:money(p.price_minor)}; }
function orderView(o) { const {editableOrder}=require('./shop');return {...o,editable:editableOrder(o),amount:money(o.amount_minor),product_snapshot:productView(o.product_snapshot)}; }
function keepLive(source,previous,hasContent){return source==='demo'&&['live','stale'].includes(previous)&&hasContent;}
function roleView(t,user){const isSeller=!!user&&user.role==='admin';return {user,isSeller,orderLabels:isSeller?{pending_payment:t.awaiting_payment,pending_completion:t.sellerProcessing,pending_review:t.awaiting_review,completed:t.completed,cancelled:t.cancelled}:t};}
function definePage(titleKey,data,methods) {
  const ownShow=methods.onShow;
  return {data:{t:strings.zh,orderLabels:strings.zh,user:null,isSeller:false,avatarSource:'',avatarText:'',theme:'light',failedImages:{},error:'',busy:false,...data},
    ...methods,
    onShow(){this.applyAppearance();if(ownShow)return ownShow.call(this);},
    applyAppearance(){const api=getApp().api,a=appearance(wx,getApp()),user=api.user,generation=api.generation,avatarRead=this.avatarRead=(this.avatarRead||0)+1;this.setData({...a,...roleView(a.t,user),avatarSource:'',avatarText:user?Array.from(user.name||user.username||'?')[0]:''});
      if(user&&user.avatar_url){const source=api.imageSource?api.imageSource(user.avatar_url):Promise.resolve(user.avatar_url);Promise.resolve(source).then(path=>{if(api.generation===generation&&this.avatarRead===avatarRead&&api.user&&api.user.id===user.id)this.setData({avatarSource:path});}).catch(()=>{});}
      wx.setNavigationBarTitle({title:a.t[titleKey]});wx.setNavigationBarColor({frontColor:a.theme==='dark'?'#ffffff':'#000000',backgroundColor:a.theme==='dark'?'#191612':'#fbf7f0'});
      if(wx.setBackgroundColor)wx.setBackgroundColor({backgroundColor:a.theme==='dark'?'#191612':'#fbf7f0'});
      const bar=this.getTabBar&&this.getTabBar();
      if(bar&&bar.setData)bar.setData({t:a.t,theme:a.theme,selected:{home:0,shop:0,orders:1,mine:2}[titleKey]||0});
    },
    fail(error){const key=error.message;this.setData({...(error.status===401?{user:null}:{}),error:this.data.t[key]||(error.status===401?this.data.t.signInFirst:error.status===403?this.data.t.permissionDenied:error.status===404?this.data.t.resourceUnavailable:error.status===409?this.data.t.version:error.status===422?this.data.t.required:this.data.t.requestFailed)});},
    imageError(e){this.setData({['failedImages.'+e.currentTarget.dataset.id]:true});},
    shop(){wx.switchTab({url:'/Pages/Shop/index'});},
    requireUser(){if(getApp().api.user)return true;this.login();return false;},
    orders(){if(this.requireUser())wx.switchTab({url:'/Pages/Orders/index'});},
    profile(){wx.switchTab({url:'/Pages/Profile/index'});},
    register(){wx.navigateTo({url:'/Pages/Login/index?mode=register'});},
    login(){wx.navigateTo({url:'/Pages/Login/index'});},
    settings(){wx.navigateTo({url:'/Pages/Settings/index'});},
  };
}
module.exports={definePage,appearance,productView,orderView,keepLive,roleView,money,languages,locales,strings};
