Page({
  data: { base: "", account: "customer", password: "", error: "" },
  onLoad() {
    this.setData({ base: getApp().api.base });
  },
  input(e) {
    this.setData({ [e.currentTarget.dataset.field]: e.detail.value });
  },
  async submit(e) {
    try {
      const api = getApp().api;
      if (this.data.base !== api.base) api.configure(this.data.base);
      await api.login(
        this.data.account,
        this.data.password,
        e.currentTarget.dataset.demo === true,
      );
      wx.showToast({
        title: api.mode === "demo" ? "已进入本地演示" : "已登录",
      });
      wx.navigateBack();
    } catch (err) {
      this.setData({ error: err.message });
    }
  },
  async demo() {
    try {
      const api = getApp().api;
      if (this.data.base !== api.base) api.configure(this.data.base);
      await api.login("customer", "demo-customer", true);
      wx.navigateBack();
    } catch (e) {
      this.setData({ error: e.message });
    }
  },
  logout() {
    getApp().api.logout();
    this.setData({ password: "" });
    wx.showToast({ title: "已退出" });
  },
});
