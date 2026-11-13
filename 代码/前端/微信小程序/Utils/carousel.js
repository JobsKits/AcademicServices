// Created by Jobs. One native swiper owns timing; lifecycle only changes its autoplay property.
const intervals=[3000,5000,8000,10000,15000];
function preferences(wx){
  const saved=Number(wx.getStorageSync('shopCarouselInterval'));
  return {carouselEnabled:wx.getStorageSync('shopCarouselEnabled')!==false,
    reduceMotion:wx.getStorageSync('shopReduceMotion')===true,
    carouselInterval:intervals.includes(saved)?saved:5000};
}
function playback(wx,state){
  const prefs=preferences(wx),multiple=state.count>1;
  return {...prefs,carouselPlaying:multiple&&state.visible&&state.foreground&&state.inViewport&&
    prefs.carouselEnabled&&!prefs.reduceMotion&&!state.userPaused&&!state.gesturePaused,
    carouselDuration:prefs.reduceMotion?0:300};
}
module.exports={preferences,playback,intervals};
