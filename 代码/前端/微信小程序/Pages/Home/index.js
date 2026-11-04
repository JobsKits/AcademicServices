Page({
  data: { services: [], source: "", error: "" },
  onShow() {
    this.reload();
  },
  async reload() {
    const requestId = this.reloadId = (this.reloadId || 0) + 1;
    try {
      const result = await getApp().api.listServices();
      if (requestId !== this.reloadId) return;
      this.setData({ ...result, error: "" });
    } catch (e) {
      if (requestId !== this.reloadId) return;
      this.setData({ error: e.message });
    }
  },
  create(e) {
    wx.navigateTo({
      url: "/Pages/Create/index?service=" + e.currentTarget.dataset.id,
    });
  },
  workspace() {
    wx.navigateTo({ url: "/Pages/Workspace/index" });
  },
  login() {
    wx.navigateTo({ url: "/Pages/Login/index" });
  },
});
