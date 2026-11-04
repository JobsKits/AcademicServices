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
    wx.navigateTo({ url: "/Pages/Login/index" });
  },
  async submit() {
    if (this.data.busy) return;
    this.setData({ busy: true, error: "" });
    try {
      const api = getApp().api;
      if (!api.user) throw Error("请先在账户页面登录");
      const form = this.data.form;
      if (!String(form.title || "").trim()) throw Error("请填写需求标题");
      if (!String(form.description || "").trim()) throw Error("请填写目标与材料说明");
      if (this.data.service_id !== "editing" && !String(form.discipline || "").trim())
        throw Error("请填写专业");
      if (this.data.service_id === "graduation" && !String(form.level || "").trim())
        throw Error("请填写学历层次");
      if (this.data.service_id === "editing" && !String(form.language || "").trim())
        throw Error("请填写源语言与目标语言");
      if (!this.data.consent) throw Error("请先同意本次材料处理授权");
      const wordCount = Number(form.word_count || 0);
      if (!Number.isInteger(wordCount) || wordCount < 0)
        throw Error("字数请填写非负整数");
      const body = {
        ...form,
        title: form.title.trim(),
        description: form.description.trim(),
        service_id: this.data.service_id,
        word_count: wordCount,
        consent: this.data.consent,
      };
      const c = await api.write("/cases", body);
      wx.redirectTo({ url: "/Pages/Detail/index?id=" + c.id });
    } catch (e) {
      this.setData({ error: e.message });
    } finally {
      this.setData({ busy: false });
    }
  },
});
