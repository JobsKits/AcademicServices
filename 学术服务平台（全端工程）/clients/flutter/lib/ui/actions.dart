import '../data/models.dart';

class ActionSpec {
  const ActionSpec(this.code, this.label, this.fields, {this.warning});
  final String code, label;
  final List<String> fields;
  final String? warning;
}

const specs = <String, ActionSpec>{
  'withdraw_request': ActionSpec('withdraw_request', '撤回未成交需求', ['text']),
  'approve_refund': ActionSpec('approve_refund', '批准退款', ['refund_id']),
  'confirm_refund': ActionSpec('confirm_refund', '核实退款成功', [
    'refund_id',
    'reference',
  ], warning: '仅在核对原流水实际退款成功后登记；系统不会代转账。'),
  'mark_refund_unknown': ActionSpec('mark_refund_unknown', '退款结果待核对', [
    'refund_id',
  ]),
  'fail_refund': ActionSpec('fail_refund', '退款已失败', ['refund_id', 'text']),
  'resolve_refund_failed': ActionSpec('resolve_refund_failed', '核对原退款未成功', [
    'refund_id',
    'reference',
    'text',
  ], warning: '仅在核对原退款流水确认未成功后解除占用；超时本身不能作为失败结论。'),
  'reject_refund': ActionSpec('reject_refund', '拒绝退款申请', ['refund_id', 'text']),
  'reject_cancel': ActionSpec('reject_cancel', '拒绝取消结算', []),
  'propose_change': ActionSpec('propose_change', '提出条款变更', [
    'amount_minor',
    'scope',
    'deadline',
  ]),
  'confirm_change': ActionSpec('confirm_change', '接受条款变更', ['change_id']),
  'reject_change': ActionSpec('reject_change', '拒绝条款变更', ['change_id']),
  'need_material': ActionSpec('need_material', '请求补充材料', ['text']),
  'supplement': ActionSpec('supplement', '补充需求说明', ['text']),
  'quote': ActionSpec('quote', '发布报价', [
    'amount_minor',
    'prepay_minor',
    'scope',
    'expires_at',
    'revision_limit',
  ]),
  'withdraw_quote': ActionSpec('withdraw_quote', '撤回当前报价', ['text']),
  'accept_quote': ActionSpec('accept_quote', '确认报价', ['quote_id']),
  'decline_quote': ActionSpec('decline_quote', '暂不接受报价', ['text']),
  'record_payment': ActionSpec('record_payment', '核实收款', [
    'amount_minor',
    'reference',
  ], warning: '仅登记已实际核实的到账，不发起扣款。请准确填写真实流水号。'),
  'start': ActionSpec('start', '开始服务', []),
  'pause': ActionSpec('pause', '暂停履约', ['text', 'hold_id']),
  'resume': ActionSpec('resume', '解除暂停原因', ['hold_id']),
  'deliver': ActionSpec('deliver', '发布正式交付', [
    'text',
    'attachment_ids',
    'after_sale_id',
  ]),
  'revision': ActionSpec('revision', '提出修改反馈', ['text', 'delivery_id']),
  'accept_revision': ActionSpec('accept_revision', '受理修改轮次', [
    'feedback_id',
    'round_id',
    'count_units',
  ]),
  'accept_delivery': ActionSpec('accept_delivery', '验收当前交付', ['delivery_id']),
  'cancel': ActionSpec('cancel', '提出取消与结算', [
    'text',
    'settlement_minor',
  ], warning: '客户确认后生效。最终应付额保留原报价历史，退款需另行核实。'),
  'confirm_cancel': ActionSpec(
    'confirm_cancel',
    '确认取消与结算',
    [],
    warning: '确认将终止主服务；请先核对最终结算金额和退款安排。',
  ),
  'refund': ActionSpec('refund', '申请退款', [
    'amount_minor',
    'payment_id',
  ], warning: '创建退款申请，随后需管理员批准与核实到账；此动作不代表退款成功。'),
  'after_sale': ActionSpec('after_sale', '申请售后', ['text']),
  'close_after_sale': ActionSpec('close_after_sale', '关闭售后', [
    'after_sale_id',
    'text',
  ]),
  'message': ActionSpec('message', '发送消息', ['text']),
};
const fieldLabels = <String, String>{
  'refund_id': '退款申请编号',
  'change_id': '变更编号',
  'deadline': '新期望日期（YYYY-MM-DD，留空保留原日期）',
  'text': '说明 / 内容',
  'amount_minor': '金额（元）',
  'prepay_minor': '开工前须到账（元）',
  'scope': '服务范围、交付、周期、修改与取消约定',
  'expires_at': '报价有效期（UTC，如 2026-12-01T12:00:00Z）',
  'revision_limit': '含修改轮数',
  'quote_id': '当前报价',
  'reference': '已核实的收款 / 退款流水号',
  'hold_id': '暂停原因编号',
  'attachment_ids': '选择本次交付附件',
  'after_sale_id': '售后编号（主服务留空）',
  'delivery_id': '当前交付编号',
  'feedback_id': '待受理反馈编号',
  'round_id': '本次修改轮编号',
  'count_units': '扣除轮数（0 或 1）',
  'settlement_minor': '最终结算应付（元）',
  'payment_id': '原始收款编号',
};
List<ActionSpec> actionsFor(Json c, bool admin) {
  final order = c['order'];
  final status = order?['status'] ?? c['status'];
  final codes = <String>['message'];
  if (order == null && !['closed'].contains(status)) {
    if (admin) {
      codes.addAll(['need_material', 'quote']);
      if (c['quote']?['status'] == 'offered') codes.add('withdraw_quote');
    } else {
      codes.addAll(['supplement', 'withdraw_request']);
      if (c['quote']?['status'] == 'offered') {
        codes.addAll(['accept_quote', 'decline_quote']);
      }
    }
  }
  if (order != null) {
    final terminal = ['completed', 'cancelled'].contains(status);
    if (admin) {
      codes.add('record_payment');
      if (objects(order['payments']).any((x) => x['status'] == 'succeeded')) {
        codes.add('refund');
      }
      for (final code in refundStages.keys) {
        if (objects(order['refunds'])
            .any((x) => refundStages[code]!.contains(x['status']))) {
          codes.add(code);
        }
      }
      if (status == 'pending_start') codes.add('start');
      if (!terminal) {
        codes.addAll(['pause', 'resume', 'cancel', 'propose_change']);
      }
      if (['in_service', 'revising', 'awaiting_acceptance'].contains(status) ||
          objects(c['after_sales']).any((x) => x['status'] != 'closed')) {
        codes.add('deliver');
      }
      if (objects(order['feedback']).any((x) => x['status'] == 'requested')) {
        codes.add('accept_revision');
      }
      if (objects(c['after_sales']).isNotEmpty) codes.add('close_after_sale');
    } else {
      if (status == 'awaiting_acceptance' ||
          objects(c['after_sales']).any((x) => x['status'] == 'open')) {
        codes.addAll(['revision', 'accept_delivery']);
      }
      if (order['cancellation']?['status'] == 'offered') {
        codes.addAll(['confirm_cancel', 'reject_cancel']);
      }
      if (objects(order['changes']).any((x) => x['status'] == 'offered')) {
        codes.addAll(['confirm_change', 'reject_change']);
      }
      if (terminal) codes.add('after_sale');
    }
  }
  return codes.map((x) => specs[x]!).toList();
}

const refundStages = <String, Set<String>>{
  'approve_refund': {'requested'},
  'confirm_refund': {'approved', 'processing', 'unknown'},
  'mark_refund_unknown': {'approved', 'processing'},
  'fail_refund': {'requested', 'approved', 'processing'},
  'reject_refund': {'requested'},
  'resolve_refund_failed': {'unknown'},
};

List<Json> availableDeliveries(Json c, String action) {
  final order = c['order'];
  if (order == null) return [];
  final latest = <String, Json>{};
  for (final d in objects(order['deliveries'])) {
    if (d['status'] == 'released') latest['${d['after_sale_id'] ?? ''}'] = d;
  }
  return latest.entries
      .where((entry) {
        final group = entry.key;
        final d = entry.value;
        if (action == 'accept_delivery' &&
            '${d['accepted_at'] ?? ''}'.isNotEmpty) {
          return false;
        }
        if (group.isNotEmpty) {
          return objects(c['after_sales'])
              .any((x) => x['id'] == group && x['status'] == 'open');
        }
        return action == 'accept_delivery'
            ? order['status'] == 'awaiting_acceptance' &&
                  order['paused'] != true
            : ['awaiting_acceptance', 'revising'].contains(order['status']);
      })
      .map((x) => x.value)
      .toList()
      .reversed
      .toList();
}
