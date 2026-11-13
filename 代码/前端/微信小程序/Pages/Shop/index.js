// Created by Jobs. The selected category and horizontally swiped panel stay in sync.
const {definePage,productView,keepLive}=require('../../Utils/ui');
const {seeds,bannerSeeds,validLink}=require('../../Utils/shop');
const {playback}=require('../../Utils/carousel');
const categories=['graduation','journal','editing'];
function groups(products){return categories.map(id=>({id,products:products.filter(p=>p.category_id===id).map(productView)}));}
Page(definePage('home',{products:seeds.map(productView),groups:groups(seeds),category:'graduation',categoryIndex:0,source:'demo',categories,banners:bannerSeeds,bannerSource:'local',bannerIndex:0,carouselPlaying:false,carouselEnabled:true,reduceMotion:false,carouselInterval:5000,carouselDuration:300}, {
  onLoad(options){const index=categories.indexOf(options.category);if(index>=0)this.setData({category:categories[index],categoryIndex:index});},
  onShow(){this.carouselVisible=true;this.hostVisible=getApp().foreground!==false;this.gesturePaused=false;this.bannerInViewport=true;this.syncCarousel();if(wx.nextTick)wx.nextTick(()=>this.observeBanner());return this.reload();},
  onReady(){this.observeBanner();},
  onHide(){this.stopCarousel();},
  onUnload(){this.readId=(this.readId||0)+1;this.stopCarousel();},
  syncCarousel(){this.setData(playback(wx,{count:this.data.banners.length,visible:this.carouselVisible===true,foreground:getApp().foreground!==false&&this.hostVisible!==false,inViewport:this.bannerInViewport!==false,gesturePaused:this.gesturePaused===true}));},
  stopCarousel(){this.carouselVisible=false;this.resumeId=(this.resumeId||0)+1;if(this.bannerObserver){this.bannerObserver.disconnect();this.bannerObserver=null;}this.syncCarousel();},
  onHostVisibilityChange(visible){this.hostVisible=visible;if(visible)this.gesturePaused=false;this.syncCarousel();},
  observeBanner(){if(!this.carouselVisible||!this.data.banners.length||this.bannerObserver||!wx.createIntersectionObserver)return;const observer=this.bannerObserver=wx.createIntersectionObserver(this,{thresholds:[0]});observer.relativeToViewport().observe('.banner-visibility',result=>{if(!this.carouselVisible||this.bannerObserver!==observer)return;this.bannerInViewport=result.intersectionRatio>0;this.syncCarousel();});},
  pauseGesture(){this.gesturePaused=true;this.syncCarousel();},
  finishGesture(){this.gesturePaused=false;this.syncCarousel();},
  bannerChanged(e){const index=Number(e.detail.current);if(index>=0&&index<this.data.banners.length)this.setData({bannerIndex:index});},
  selectBanner(e){const index=Number(e.currentTarget.dataset.index);if(index>=0&&index<this.data.banners.length){this.gesturePaused=true;this.syncCarousel();this.setData({bannerIndex:index});const id=this.resumeId=(this.resumeId||0)+1;const resume=()=>{if(this.resumeId===id&&this.carouselVisible)this.finishGesture();};if(wx.nextTick)wx.nextTick(resume);else resume();}},
  async reload(){const id=this.readId=(this.readId||0)+1,api=getApp().api;try{const [r,banners]=await Promise.all([api.catalog(),api.banners?api.banners():Promise.resolve({banners:bannerSeeds,bannerSource:'local'})]);if(id===this.readId){if(keepLive(r.source,this.data.source,this.data.products.length>0))this.setData({...banners,source:'stale',error:''});else this.setData({...r,...banners,products:r.products.map(productView),groups:groups(r.products),failedImages:{},error:''});if(this.data.bannerIndex>=this.data.banners.length)this.setData({bannerIndex:0});if(!this.data.banners.length&&this.bannerObserver){this.bannerObserver.disconnect();this.bannerObserver=null;}this.syncCarousel();if(wx.nextTick)wx.nextTick(()=>this.observeBanner());}}catch(e){if(id===this.readId)this.fail(e);}},
  category(e){const index=categories.indexOf(e.currentTarget.dataset.id);if(index>=0)this.setData({category:categories[index],categoryIndex:index});},
  swipe(e){const index=Number(e.detail.current);if(categories[index])this.setData({category:categories[index],categoryIndex:index});},
  banner(e){const banner=this.data.banners.find(b=>b.id===e.currentTarget.dataset.id);if(!banner||!banner.target_url)return;if(!validLink(banner.target_url)){this.setData({error:this.data.t.invalidLink});return;}const url=banner.target_url;wx.showModal({title:this.data.t.openWebView,content:this.data.t.webViewHint,confirmText:this.data.t.openShort,cancelText:this.data.t.copyShort,success:r=>{if(r.confirm)wx.navigateTo({url:'/Pages/Web/index?url='+encodeURIComponent(url)});else if(r.cancel)wx.setClipboardData({data:url,success:()=>wx.showToast({title:this.data.t.copied,icon:'success'})});}});},
  product(e){wx.navigateTo({url:'/Pages/Product/index?id='+encodeURIComponent(e.currentTarget.dataset.id)});},
}));
