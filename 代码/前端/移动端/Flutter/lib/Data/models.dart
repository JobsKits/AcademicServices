import 'dart:convert';

typedef Json = Map<String, dynamic>;
Json object(dynamic value) => Map<String, dynamic>.from(value as Map);
List<Json> objects(dynamic value) =>
    (value as List? ?? []).map(object).toList();
Json copy(Json value) => object(jsonDecode(jsonEncode(value)));
String money(dynamic value) =>
    '¥${((value as num? ?? 0) / 100).toStringAsFixed(2)}';
String statusName(dynamic value) =>
    const {
      'pending_review': '待审核',
      'awaiting_material': '待补充材料',
      'awaiting_quote_accept': '待确认报价',
      'converted': '已生成订单',
      'closed': '已关闭',
      'pending_start': '待开始',
      'in_service': '服务中',
      'awaiting_acceptance': '待验收',
      'revising': '修改中',
      'completed': '已完成',
      'cancelled': '已取消',
      'offered': '待确认',
      'accepted': '已确认',
      'expired': '已过期',
      'superseded': '已被替代',
      'declined': '已拒绝',
      'succeeded': '已核实',
      'open': '处理中',
      'requested': '待审核',
      'approved': '已批准，尚未成功',
      'processing': '执行中',
      'unknown': '结果待核对',
      'failed': '已失败',
      'rejected': '已拒绝',
      'released': '已交付',
    }[value] ??
    '$value';
String caseStatus(Json c) => statusName(c['order']?['status'] ?? c['status']);

final demoServices = <Json>[
  {
    'id': 'graduation',
    'name': '毕业论文',
    'summary': '从选题到规范表达',
    'description': '选题梳理、结构建议、写作辅导与格式检查。具体范围和交付物以双方确认的报价为准。',
    'active': true,
  },
  {
    'id': 'journal',
    'name': '普刊',
    'summary': '让投稿路径更清楚',
    'description': '期刊信息咨询、稿件整理与投稿流程支持。费用、周期和服务边界在报价中逐项说明。',
    'active': true,
  },
  {
    'id': 'editing',
    'name': '编译',
    'summary': '准确、清楚地表达研究',
    'description': '学术翻译与语言润色。提交语种、字数和现有稿件后，由工作人员评估服务范围。',
    'active': true,
  },
];

List<Json> demoCases(String owner) => [
  {
    'id': 'demo-case',
    'owner_id': owner,
    'service_id': 'editing',
    'title': '英文摘要语言润色',
    'description': '这是一条本地演示需求，可体验报价、消息和进度。',
    'discipline': '教育学',
    'level': '硕士',
    'word_count': 800,
    'language': '中译英',
    'deadline': '2026-12-01',
    'contact': '演示资料',
    'status': 'awaiting_quote_accept',
    'version': 1,
    'created_at': '2026-10-30T00:00:00Z',
    'updated_at': '2026-10-30T00:00:00Z',
    'quote': {
      'id': 'demo-quote',
      'amount_minor': 30000,
      'prepay_minor': 0,
      'currency': 'CNY',
      'scope': '摘要语言润色一份；含两轮约定范围内修改。演示报价，不作为实际报价。',
      'expires_at': '2099-12-01T00:00:00Z',
      'revision_limit': 2,
      'status': 'offered',
    },
    'order': null,
    'attachments': [],
    'messages': [],
    'events': [],
    'after_sales': [],
  },
];
