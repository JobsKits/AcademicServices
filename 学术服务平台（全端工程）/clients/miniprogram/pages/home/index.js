Page({
  data: { services: [], source: "", error: "" },
  onShow() {
    this.reload();
  },
  async reload() {
    try {
      this.setData({ ...(await getApp().api.listServices()), error: "" });
    } catch (e) {
      this.setData({ error: e.message });
    }
  },
  create(e) {
    wx.navigateTo({
      url: "/pages/create/index?service=" + e.currentTarget.dataset.id,
    });
  },
  workspace() {
    wx.navigateTo({ url: "/pages/workspace/index" });
  },
  login() {
    wx.navigateTo({ url: "/pages/login/index" });
  },
});
