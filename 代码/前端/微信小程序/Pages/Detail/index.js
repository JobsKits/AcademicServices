const f = require("../../Utils/format");
Page({
  data: {
    c: null,
    text: "",
    error: "",
    status: "",
    quoteMoney: "",
    source: "",
    busy: false,
    holds: [],
    changes: [],
    attachments: [],
    messages: [],
    deliveries: [],
  },
  onLoad(o) {
    this.id = o.id;
  },
  onShow() {
    this.reload();
  },
  async reload() {
    const requestId = this.reloadId = (this.reloadId || 0) + 1;
    try {
      const a = getApp().api;
      await a.workspace();
      if (requestId !== this.reloadId) return;
      const c = a.cases.find((c) => c.id === this.id);
      if (!c) throw Error("记录不存在或当前账户无权查看");
      this.setData({
        c,
        source: a.mode,
        status: f.status(c),
        quoteMoney: c.quote ? f.money(c.quote.amount_minor) : "",
        paid: c.order
          ? f.money(c.order.paid_minor - c.order.refunded_minor)
          : "",
        deliveries: this.deliveries(c),
        holds: (c.order && c.order.holds) || [],
        changes: ((c.order && c.order.changes) || []).filter((change) => change.status === "offered"),
        attachments: c.attachments || [],
        messages: c.messages || [],
        error: "",
      });
    } catch (e) {
      if (requestId !== this.reloadId) return;
      this.setData({ c: null, error: e.message });
    }
  },
  deliveries(c) {
    const o = c.order;
    if (!o) return [];
    const latest = {};
    for (const d of o.deliveries || [])
      if (d.status === "released") latest[d.after_sale_id || "main"] = d.id;
    return (o.deliveries || []).map((d) => ({
      ...d,
      actionable:
        latest[d.after_sale_id || "main"] === d.id &&
        (d.after_sale_id
          ? (c.after_sales || []).some(
              (a) => a.id === d.after_sale_id && a.status === "open",
            )
          : o.status === "awaiting_acceptance" && !o.paused),
    }));
  },
  input(e) {
    this.setData({ text: e.detail.value });
  },
  async action(e) {
    if (this.data.busy || !this.data.c) return;
    const action = e.currentTarget.dataset.action;
    const data = {
      action,
      expected_version: this.data.c.version,
      text: this.data.text,
      ...(e.currentTarget.dataset.quote
        ? { quote_id: e.currentTarget.dataset.quote }
        : {}),
      ...(e.currentTarget.dataset.delivery
        ? { delivery_id: e.currentTarget.dataset.delivery }
        : {}),
      ...(e.currentTarget.dataset.change
        ? { change_id: e.currentTarget.dataset.change }
        : {}),
    };
    if (
      [
        "accept_quote",
        "accept_delivery",
        "confirm_cancel",
        "confirm_change",
        "withdraw_request",
      ].includes(action)
    ) {
      const confirm = await wx.showModal({
        title: "确认操作",
        content: "请核对页面中的范围、金额及交付内容后确认。",
      });
      if (!confirm.confirm) return;
    }
    this.setData({ busy: true });
    try {
      await getApp().api.write("/cases/" + this.id + "/actions", data);
      await this.reload();
      this.setData({ text: "" });
    } catch (err) {
      this.setData({ error: err.message });
    } finally {
      this.setData({ busy: false });
    }
  },
  async upload() {
    try {
      await getApp().api.upload(this.data.c);
      await this.reload();
    } catch (e) {
      this.setData({ error: e.message });
    }
  },
  async download(e) {
    try {
      await getApp().api.download(this.data.c, e.currentTarget.dataset.id);
    } catch (err) {
      this.setData({ error: err.message });
    }
  },
});
