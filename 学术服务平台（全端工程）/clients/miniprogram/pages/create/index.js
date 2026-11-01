Page({
  data: {
    service_id: "graduation",
    service_name: "毕业论文",
    form: {
      title: "",
      description: "",
      discipline: "",
      level: "本科",
      word_count: 0,
      language: "中文",
      deadline: "",
      contact: "",
    },
    consent: false,
    error: "",
    busy: false,
  },
  onLoad(o) {
    const names = { graduation: "毕业论文", journal: "普刊", editing: "编译" };
    this.setData({
      service_id: names[o.service] ? o.service : "graduation",
      service_name: names[o.service] || "毕业论文",
    });
  },
  input(e) {
    const field = e.currentTarget.dataset.field;
    this.setData({ ["form." + field]: e.detail.value });
  },
  consent(e) {
    this.setData({ consent: e.detail.value.length > 0 });
  },
  login() {
    wx.navigateTo({ url: "/pages/login/index" });
  },
  async submit() {
    if (this.data.busy) return;
    this.setData({ busy: true, error: "" });
    try {
      const api = getApp().api;
      if (!api.user) throw Error("请先在账户页面登录");
      const body = {
        ...this.data.form,
        service_id: this.data.service_id,
        word_count: Number(this.data.form.word_count || 0),
        consent: this.data.consent,
      };
      const c = await api.write("/cases", body);
      wx.redirectTo({ url: "/pages/detail/index?id=" + c.id });
    } catch (e) {
      this.setData({ error: e.message });
    } finally {
      this.setData({ busy: false });
    }
  },
});
