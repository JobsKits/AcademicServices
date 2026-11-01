const names = {
  pending_review: "待审核",
  awaiting_material: "待补材料",
  awaiting_quote_accept: "待确认报价",
  converted: "已转订单",
  closed: "已关闭",
  pending_start: "待启动",
  in_service: "服务中",
  awaiting_acceptance: "待验收",
  revising: "修改中",
  completed: "已完成",
  cancelled: "已取消",
  requested: "待审核",
  approved: "已批准待退款",
  processing: "处理中",
  unknown: "结果待核对",
  succeeded: "已核实成功",
};
function status(c) {
  return c.order
    ? (c.order.paused ? "已暂停 · " : "") +
        (names[c.order.status] || c.order.status)
    : names[c.status] || c.status;
}
function money(n) {
  return "¥" + ((n || 0) / 100).toFixed(2);
}
module.exports = { status, money };
