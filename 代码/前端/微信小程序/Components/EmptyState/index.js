Component({
  properties: {
    title: { type: String, value: "暂无内容" },
    description: { type: String, value: "可重新加载以取得最新状态。" },
    reloadLabel: { type: String, value: "重新加载" },
  },
  methods: {
    reload() {
      this.triggerEvent("reload");
    },
  },
});
