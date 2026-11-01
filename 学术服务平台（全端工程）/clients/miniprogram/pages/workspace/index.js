const f = require("../../utils/format");
Page({
  data: { cases: [], source: "", error: "", pending: false },
  onShow() {
    this.reload();
  },
  async reload() {
    try {
      const a = getApp().api,
        cases = await a.workspace();
      this.setData({
        cases: cases.map((c) => ({ ...c, status_label: f.status(c) })),
        source: a.mode,
        error: "",
        pending: !!a.pending,
      });
    } catch (e) {
      this.setData({
        cases: [],
        error: e.message,
        pending: !!getApp().api.pending,
      });
    }
  },
  detail(e) {
    wx.navigateTo({
      url: "/pages/detail/index?id=" + e.currentTarget.dataset.id,
    });
  },
  login() {
    wx.navigateTo({ url: "/pages/login/index" });
  },
  async retry() {
    try {
      await getApp().api.retryPending();
      await this.reload();
    } catch (e) {
      this.setData({ error: e.message });
    }
  },
  async reconcile() {
    try {
      await getApp().api.reconcile();
      await this.reload();
    } catch (e) {
      this.setData({
        error:
          e.status === 404
            ? "目前尚无已提交收据；请求可能仍在处理，请稍后再次核对。"
            : e.message,
      });
    }
  },
});
