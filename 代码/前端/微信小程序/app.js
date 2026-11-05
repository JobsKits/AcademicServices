// Created by Jobs. Native storefront entry.
const {ShopClient}=require('./Utils/shop');
App({onLaunch(){this.api=new ShopClient(wx); const info=wx.getAppBaseInfo?wx.getAppBaseInfo():{};this.systemTheme=info.theme||'light';
if(wx.onThemeChange)wx.onThemeChange(({theme})=>{this.systemTheme=theme;const pages=getCurrentPages();const page=pages[pages.length-1];if(page&&page.applyAppearance)page.applyAppearance();});
}});
