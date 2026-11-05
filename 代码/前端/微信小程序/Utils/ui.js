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
function orderView(o) { return {...o,amount:money(o.amount_minor),product_snapshot:productView(o.product_snapshot)}; }
function definePage(titleKey,data,methods) {
  const ownShow=methods.onShow;
  return {data:{t:strings.zh,theme:'light',failedImages:{},error:'',busy:false,...data},
    ...methods,
    onShow(){this.applyAppearance();if(ownShow)return ownShow.call(this);},
    applyAppearance(){const a=appearance(wx,getApp());this.setData({...a,user:getApp().api.user});
      wx.setNavigationBarTitle({title:a.t[titleKey]});wx.setNavigationBarColor({frontColor:a.theme==='dark'?'#ffffff':'#000000',backgroundColor:a.theme==='dark'?'#211b17':'#fbf5ec'});
      if(wx.setBackgroundColor)wx.setBackgroundColor({backgroundColor:a.theme==='dark'?'#211b17':'#fbf5ec'});
    },
    fail(error){const key=error.message;this.setData({error:this.data.t[key]||(error.status===401?this.data.t.signInFirst:error.status===409?this.data.t.version:error.status===422?this.data.t.required:this.data.t.unexpected_response)});},
    imageError(e){this.setData({['failedImages.'+e.currentTarget.dataset.id]:true});},
    shop(){wx.navigateTo({url:'/Pages/Shop/index'});},
    orders(){wx.navigateTo({url:'/Pages/Orders/index'});},
    login(){wx.navigateTo({url:'/Pages/Login/index'});},
    settings(){wx.navigateTo({url:'/Pages/Settings/index'});},
  };
}
module.exports={definePage,appearance,productView,orderView,money,languages,locales,strings};
