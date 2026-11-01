import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/models.dart';
import '../data/repository.dart';
import 'actions.dart';
import 'theme.dart';

String defaultApiUrl() {
  const configured = String.fromEnvironment('API_BASE_URL');
  if (configured.isNotEmpty) return configured;
  if (kIsWeb && Uri.base.host.isNotEmpty) return '${Uri.base.origin}/api/v1';
  return defaultTargetPlatform == TargetPlatform.android
      ? 'http://10.0.2.2:8080/api/v1'
      : 'http://127.0.0.1:8080/api/v1';
}

bool get harmonyHost =>
    const bool.fromEnvironment('HARMONY_HOST') ||
    (kIsWeb && Uri.base.queryParameters['host'] == 'harmony');

class ZhixuApp extends StatefulWidget {
  const ZhixuApp({super.key, this.adminMode = false, this.repository});
  final bool adminMode;
  final WorkspaceRepository? repository;
  @override
  State<ZhixuApp> createState() => _ZhixuAppState();
}

class _ZhixuAppState extends State<ZhixuApp> {
  late final WorkspaceRepository repo =
      widget.repository ?? WorkspaceRepository(baseUrl: defaultApiUrl());
  ThemeMode mode = ThemeMode.system;
  @override
  void initState() {
    super.initState();
    unawaited(_restore());
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString('theme');
      final api = prefs.getString('api');
      if (api != null) repo.setBaseUrl(api);
      if (mounted) {
        setState(
          () => mode = ThemeMode.values.firstWhere(
            (x) => x.name == stored,
            orElse: () => ThemeMode.system,
          ),
        );
      }
    } catch (_) {
      /* Preferences unavailable on an unregistered platform: use session defaults. */
    }
    if (!mounted) return;
    await repo.restorePending();
    try {
      await repo.loadServices();
    } catch (_) {}
  }

  Future<void> _theme(ThemeMode value) async {
    setState(() => mode = value);
    try {
      (await SharedPreferences.getInstance()).setString('theme', value.name);
    } catch (_) {}
  }

  @override
  void dispose() {
    if (widget.repository == null) repo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: widget.adminMode ? '知序 · 管理工作台' : '知序 · 学术服务',
    debugShowCheckedModeBanner: false,
    theme: appTheme(Brightness.light),
    darkTheme: appTheme(Brightness.dark),
    themeMode: mode,
    home: Workspace(
      repo: repo,
      adminMode: widget.adminMode,
      themeMode: mode,
      onTheme: _theme,
    ),
  );
}

class Workspace extends StatefulWidget {
  const Workspace({
    super.key,
    required this.repo,
    required this.adminMode,
    required this.themeMode,
    required this.onTheme,
  });
  final WorkspaceRepository repo;
  final bool adminMode;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onTheme;
  @override
  State<Workspace> createState() => _WorkspaceState();
}

class _WorkspaceState extends State<Workspace> {
  WorkspaceRepository get repo => widget.repo;
  int page = 0;
  String? selected;
  bool working = false;
  String search = '';
  @override
  void initState() {
    super.initState();
    repo.addListener(_changed);
  }

  void _changed() {
    if (mounted) {
      setState(() {
        if (repo.user == null) selected = null;
      });
    }
  }

  @override
  void dispose() {
    repo.removeListener(_changed);
    super.dispose();
  }

  void tell(Object message) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$message')));
    }
  }

  Future<void> run(Future<void> Function() operation) async {
    if (working) return;
    setState(() => working = true);
    try {
      await operation();
    } catch (e) {
      tell(e);
    } finally {
      if (mounted) setState(() => working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DisplayFeatureSubScreen(
      anchorPoint: Offset.zero,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 960;
          return Scaffold(
            appBar: AppBar(
              title: Text(widget.adminMode ? '知序 / 管理工作台' : '知序'),
              actions: [
                TextButton(
                  onPressed: () => _settings(),
                  child: const Text('设置'),
                ),
                TextButton(
                  onPressed: working ? null : () => run(() => repo.refresh()),
                  child: const Text('重新加载'),
                ),
                if (constraints.maxWidth >= 560)
                  TextButton(
                    onPressed: () => _login(),
                    child: Text(
                      repo.user == null ? '登录' : '${repo.user!['name']}',
                    ),
                  ),
              ],
            ),
            body: SafeArea(
              child: Column(
                children: [
                  _connection(),
                  if (working) const LinearProgressIndicator(minHeight: 2),
                  Expanded(
                    child: Row(
                      children: [
                        if (wide)
                          NavigationRail(
                            selectedIndex: page,
                            labelType: NavigationRailLabelType.all,
                            onDestinationSelected: (i) => setState(() {
                              page = i;
                              selected = null;
                            }),
                            destinations: const [
                              NavigationRailDestination(
                                icon: Text('01'),
                                label: Text('服务'),
                              ),
                              NavigationRailDestination(
                                icon: Text('02'),
                                label: Text('需求'),
                              ),
                              NavigationRailDestination(
                                icon: Text('03'),
                                label: Text('我的'),
                              ),
                            ],
                          ),
                        Expanded(child: _body(wide)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            bottomNavigationBar: wide
                ? null
                : NavigationBar(
                    selectedIndex: page,
                    onDestinationSelected: (i) => setState(() {
                      page = i;
                      selected = null;
                    }),
                    destinations: const [
                      NavigationDestination(icon: Text('01'), label: '服务'),
                      NavigationDestination(icon: Text('02'), label: '需求'),
                      NavigationDestination(icon: Text('03'), label: '我的'),
                    ],
                  ),
          );
        },
      ),
    );
  }

  Widget _connection() => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
    color: Theme.of(context).colorScheme.secondaryContainer,
    child: Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      children: [
        Text(
          repo.user == null
              ? repo.servicesOnline
                    ? '服务信息已连接 · 登录后办理需求'
                    : repo.notice
              : '${repo.demo ? '本地演示' : '服务端'} · ${repo.notice}',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSecondaryContainer,
          ),
        ),
        if (repo.pending != null)
          TextButton(
            onPressed: working
                ? null
                : () => run(() => repo.reconcilePending()),
            child: const Text('查询原操作'),
          ),
        if (repo.pending != null)
          TextButton(
            onPressed: working
                ? null
                : () => run(() async {
                    await repo.retryPending();
                  }),
            child: const Text('重试原请求'),
          ),
      ],
    ),
  );
  Widget _body(bool wide) {
    if (page == 0) return _services();
    if (page == 2) return _account();
    if (repo.user == null) {
      return _empty('登录后查看你的需求', '需求、报价与交付仅对本人和授权工作人员可见。', _login, '登录 / 体验演示');
    }
    final matches = repo.cases
        .where(
          (c) => '${c['title']} ${c['id']} ${caseStatus(c)}'.contains(search),
        )
        .toList();
    final current = repo.cases.where((c) => c['id'] == selected).firstOrNull;
    final list = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(20),
          child: TextField(
            decoration: const InputDecoration(labelText: '搜索需求标题、编号或状态'),
            onChanged: (v) => setState(() => search = v),
          ),
        ),
        Expanded(
          child: matches.isEmpty
              ? _empty(
                  '暂无需求',
                  '提交需求后，报价和进度会出现在这里。',
                  () => run(() => repo.refresh()),
                  '重新加载',
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  itemCount: matches.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, i) {
                    final c = matches[i];
                    return Card(
                      child: ListTile(
                        contentPadding: const EdgeInsets.all(16),
                        selected: c['id'] == selected,
                        title: Text('${c['title']}'),
                        subtitle: Text(
                          '${_serviceName(c['service_id'])} · ${caseStatus(c)}\n${c['id']}',
                        ),
                        isThreeLine: true,
                        onTap: () => setState(() => selected = c['id']),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
    if (wide && current != null) {
      return Row(
        children: [
          SizedBox(width: 340, child: list),
          const VerticalDivider(width: 1),
          Expanded(child: _detail(current)),
        ],
      );
    }
    return current == null ? list : _detail(current);
  }

  Widget _services() => LayoutBuilder(
    builder: (context, constraints) => SingleChildScrollView(
      padding: EdgeInsets.all(constraints.maxWidth < 600 ? 20 : 40),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1120),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'ACADEMIC SERVICES',
                style: TextStyle(
                  letterSpacing: 2,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                '把需求说清楚，\n让服务有进度。',
                style: Theme.of(context).textTheme.headlineLarge,
              ),
              const SizedBox(height: 16),
              Text(
                '只专注三项服务。先沟通需求，再确认范围与报价。',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 32),
              if (repo.services.where((s) => s['active'] == true).isEmpty)
                _empty(
                  '暂无上架服务',
                  '可稍后重新加载。',
                  () => run(() => repo.loadServices()),
                  '重新加载',
                )
              else
                Wrap(
                  spacing: 20,
                  runSpacing: 20,
                  children: repo.services
                      .where((s) => s['active'] == true)
                      .indexed
                      .map((entry) {
                        final s = entry.$2;
                        final width = constraints.maxWidth >= 1040
                            ? 312.0
                            : constraints.maxWidth >= 700
                            ? (constraints.maxWidth - 100) / 2
                            : constraints.maxWidth - 40;
                        return SizedBox(
                          width: width,
                          child: Card(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '0${entry.$1 + 1}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineMedium,
                                  ),
                                  const SizedBox(height: 24),
                                  Text(
                                    '${s['name']}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    '${s['summary'] ?? ''}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyLarge,
                                  ),
                                  const SizedBox(height: 16),
                                  Text('${s['description'] ?? ''}'),
                                  const SizedBox(height: 24),
                                  FilledButton(
                                    onPressed: () => _service(s),
                                    child: const Text('了解并提交需求'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      })
                      .toList(),
                ),
              const SizedBox(height: 32),
              const Text('提交需求 → 人工评估 → 确认报价 → 查看进度 → 交付与验收'),
              const SizedBox(height: 12),
              const Text('具体费用、周期与交付要求在报价中确认。'),
            ],
          ),
        ),
      ),
    ),
  );
  String _serviceName(dynamic id) =>
      repo.services.where((s) => s['id'] == id).firstOrNull?['name'] ?? '$id';
  Widget _account() => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      Text(
        repo.user == null ? '欢迎来到知序' : '${repo.user!['name']}',
        style: Theme.of(context).textTheme.headlineMedium,
      ),
      const SizedBox(height: 12),
      Text(
        repo.user == null
            ? '登录查看需求与交付。'
            : repo.admin
            ? '当前身份：管理员'
            : '当前身份：客户',
      ),
      const SizedBox(height: 24),
      Align(
        alignment: Alignment.centerLeft,
        child: FilledButton(
          onPressed: _login,
          child: Text(repo.user == null ? '登录 / 体验演示' : '切换账户'),
        ),
      ),
      if (repo.user != null)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () => repo.logout(),
            child: const Text('退出登录'),
          ),
        ),
      const SizedBox(height: 24),
      const Text('显示主题'),
      DropdownButton<ThemeMode>(
        value: widget.themeMode,
        onChanged: (v) => widget.onTheme(v!),
        items: const [
          DropdownMenuItem(value: ThemeMode.system, child: Text('跟随系统')),
          DropdownMenuItem(value: ThemeMode.light, child: Text('白天')),
          DropdownMenuItem(value: ThemeMode.dark, child: Text('黑夜')),
        ],
      ),
      const SizedBox(height: 20),
      Text('服务地址：${repo.baseUrl}'),
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton(
          onPressed: _settings,
          child: const Text('配置服务地址'),
        ),
      ),
      const SizedBox(height: 24),
      const Text('演示操作仅保存在本次会话；真实服务恢复后自动显示服务端数据。附件下载需要登录授权。'),
    ],
  );
  Widget _empty(String title, String body, VoidCallback action, String label) =>
      Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              Text(body, textAlign: TextAlign.center),
              const SizedBox(height: 20),
              OutlinedButton(onPressed: action, child: Text(label)),
            ],
          ),
        ),
      );
  Future<void> _settings() async {
    final controller = TextEditingController(text: repo.baseUrl);
    final result = await _dialog('连接服务', [
      const Text('正式使用填写 HTTPS 域名，结尾为 /api/v1。更换地址会退出当前账户。'),
      TextField(
        controller: controller,
        decoration: const InputDecoration(labelText: 'API 地址'),
      ),
    ], () => controller.text.trim());
    controller.dispose();
    if (result != null) {
      await run(() async {
        repo.setBaseUrl(result as String);
        try {
          await (await SharedPreferences.getInstance()).setString(
            'api',
            repo.baseUrl,
          );
        } catch (_) {}
        if (!mounted) return;
        await repo.restorePending();
        try {
          await repo.loadServices();
        } catch (_) {}
      });
    }
  }

  Future<void> _login() async {
    final account = TextEditingController(
      text: widget.adminMode ? 'admin' : 'customer',
    );
    final password = TextEditingController();
    final result = await _dialog(
      widget.adminMode ? '管理工作台登录' : '登录知序',
      [
        TextField(
          controller: account,
          autofillHints: const [AutofillHints.username],
          decoration: const InputDecoration(labelText: '账户'),
        ),
        TextField(
          controller: password,
          obscureText: true,
          autofillHints: const [AutofillHints.password],
          decoration: const InputDecoration(labelText: '密码'),
        ),
        const Text(
          '首次本机演示：客户 customer / demo-customer；管理员 admin / demo-admin-change-me。正式环境由部署者配置。',
        ),
      ],
      () => {'account': account.text.trim(), 'password': password.text},
      extra: TextButton(
        onPressed: () => Navigator.pop(context, {
          'account': widget.adminMode ? 'admin' : 'customer',
          'password': widget.adminMode
              ? 'demo-admin-change-me'
              : 'demo-customer',
          'demo': true,
        }),
        child: const Text('使用演示账户（离线时进入本地演示）'),
      ),
    );
    account.dispose();
    password.dispose();
    if (result != null) {
      await run(() async {
        final data = object(result);
        await repo.login(
          data['account'],
          data['password'],
          allowDemo: data['demo'] == true,
          asAdmin: widget.adminMode,
        );
        if (mounted) {
          setState(() {
            page = 1;
            selected = null;
          });
        }
      });
    }
  }

  Future<void> _service(Json service) async {
    if (repo.user == null) {
      await _login();
      if (repo.user == null) return;
    }
    if (repo.admin) {
      tell('当前为管理员，请使用客户账户提交需求');
      return;
    }
    final controllers = {
      for (final k in [
        'title',
        'description',
        'discipline',
        'level',
        'word_count',
        'language',
        'deadline',
        'contact',
      ])
        k: TextEditingController(),
    };
    controllers['level']!.text = service['id'] == 'graduation' ? '本科' : '';
    controllers['language']!.text = service['id'] == 'editing' ? '中译英' : '中文';
    bool consent = false;
    String? error;
    final labels = {
      'title': '需求标题 *',
      'description': '目标、现有材料与交付要求 *',
      'discipline': service['id'] == 'journal' ? '专业 / 期刊方向 *' : '专业 / 学科 *',
      'level': '学历 / 阶段 *',
      'word_count': '预计字数（选填）',
      'language': '语种 / 编译方向 *',
      'deadline': '期望日期（YYYY-MM-DD，选填）',
      'contact': '联系说明（选填）',
    };
    final visibleFields = {
      'title',
      'description',
      if (service['id'] != 'editing') 'discipline',
      if (service['id'] == 'graduation') 'level',
      if (service['id'] == 'editing') 'language',
      'word_count',
      'deadline',
      'contact',
    };
    if (!mounted) {
      return;
    }
    final result = await _showDialog<Json>(
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: Text('提交${service['name']}需求'),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('${service['description']}'),
                  const SizedBox(height: 16),
                  ...controllers.entries
                      .where((e) => visibleFields.contains(e.key))
                      .map(
                        (e) => Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: TextField(
                            controller: e.value,
                            decoration: InputDecoration(
                              labelText: labels[e.key],
                            ),
                            maxLines: e.key == 'description' ? 4 : 1,
                            keyboardType: e.key == 'word_count'
                                ? TextInputType.number
                                : TextInputType.text,
                          ),
                        ),
                      ),
                  CheckboxListTile(
                    value: consent,
                    onChanged: (v) => setDialog(() => consent = v ?? false),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('同意工作人员为评估和履约处理本次需求与附件。服务范围以确认的报价为准。'),
                  ),
                  if (error != null)
                    Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final body = <String, dynamic>{
                  for (final e in controllers.entries)
                    e.key: e.value.text.trim(),
                  'service_id': service['id'],
                  'consent': consent,
                };
                final words = body['word_count'].isEmpty
                    ? 0
                    : int.tryParse(body['word_count']);
                final deadline = body['deadline'] as String;
                final parsedDate = DateTime.tryParse(deadline);
                final validDate =
                    deadline.isEmpty ||
                    (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(deadline) &&
                        parsedDate != null &&
                        parsedDate.toIso8601String().startsWith(deadline));
                final missingServiceField =
                    (service['id'] != 'editing' &&
                        body['discipline'].isEmpty) ||
                    (service['id'] == 'graduation' && body['level'].isEmpty) ||
                    (service['id'] == 'editing' && body['language'].isEmpty);
                if (body['title'].toString().length < 2 ||
                    body['description'].toString().length < 5 ||
                    !consent ||
                    words == null ||
                    words < 0 ||
                    !validDate ||
                    missingServiceField) {
                  setDialog(
                    () => error = '请填写标 * 的必填项与至少 5 字说明，并勾选授权。字数和日期可留空；填写时须有效。',
                  );
                  return;
                }
                body['word_count'] = words;
                Navigator.pop(dialogContext, body);
              },
              child: const Text('提交需求'),
            ),
          ],
        ),
      ),
    );
    for (final c in controllers.values) {
      c.dispose();
    }
    if (result != null) {
      await run(() async {
        final c = await repo.create(result);
        if (mounted) {
          setState(() {
            page = 1;
            selected = c['id'];
          });
        }
      });
    }
  }

  Widget _section(String title, List<Widget> children) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    ),
  );
  Widget _detail(Json c) {
    final q = c['quote'] is Map ? object(c['quote']) : null;
    final o = c['order'] is Map ? object(c['order']) : null;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () => setState(() => selected = null),
            child: const Text('← 返回需求列表'),
          ),
        ),
        Text(
          '${c['title']}',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        Text('${c['id']} · 版本 ${c['version']}'),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            Chip(label: Text(caseStatus(c))),
            Chip(label: Text(_serviceName(c['service_id']))),
            if (o?['paused'] == true) const Chip(label: Text('履约已暂停')),
          ],
        ),
        const SizedBox(height: 18),
        _section('需求说明', [
          Text('${c['description']}'),
          const SizedBox(height: 8),
          Text(
            '${c['discipline'] ?? ''} · ${c['level'] ?? ''} · ${c['word_count'] ?? ''} 字 · ${c['language'] ?? ''}',
          ),
          Text('期望日期：${c['deadline'] ?? ''}\n联系说明：${c['contact'] ?? ''}'),
        ]),
        if (q != null)
          _section('当前报价', [
            Text(
              '${money(q['amount_minor'])} · ${statusName(q['status'])}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Text('${q['scope']}'),
            const SizedBox(height: 8),
            Text(
              '开工前须到账 ${money(q['prepay_minor'])} · 含 ${q['revision_limit'] ?? 0} 轮修改',
            ),
            Text('有效期：${q['expires_at']}'),
          ]),
        if (o != null)
          _section('服务与资金进度', [
            Text(
              '当前应付 ${money(o['amount_minor'])} · 原约定 ${money(o['original_amount_minor'])}',
            ),
            Text(
              '已核实收款 ${money(o['paid_minor'])} · 已退 ${money(o['refunded_minor'])} · 退款占用 ${money(o['refund_held_minor'])}',
            ),
            Text(
              '修改轮：${o['revision_used'] ?? 0} / ${o['revision_limit'] ?? 0}',
            ),
            ...objects(o['holds']).map(
              (h) => Text(
                '暂停 ${h['id'] ?? h['hold_id']}：${h['reason'] ?? h['text'] ?? ''}',
              ),
            ),
            if (o['cancellation'] != null) Text('待确认取消结算：${o['cancellation']}'),
            ...objects(o['deliveries']).map(
              (d) => ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('交付 ${d['version'] ?? d['id']}'),
                subtitle: Text(
                  '${d['text'] ?? d['summary'] ?? ''}\n编号 ${d['id']}',
                ),
              ),
            ),
            ...objects(o['feedback']).map(
              (f) => Text(
                '修改反馈 ${f['id']} · ${statusName(f['status'])}\n${f['text']}',
              ),
            ),
            ...objects(o['refunds']).map(
              (r) => Text(
                '退款 ${r['id']} · ${money(r['amount_minor'])} · ${statusName(r['status'])}',
              ),
            ),
            ...objects(o['changes']).map(
              (ch) => Text(
                '变更 ${ch['id']} · ${money(ch['amount_minor'])} · ${statusName(ch['status'])}\n${ch['scope']}',
              ),
            ),
            ...objects(o['payments']).map(
              (p) => Text(
                '收款 ${p['id']} · ${money(p['amount_minor'])} · ${p['reference']}',
              ),
            ),
          ]),
        _section('办理动作', [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: actionsFor(c, repo.admin)
                .map(
                  (spec) => OutlinedButton(
                    onPressed: working || repo.pending != null
                        ? null
                        : () => _action(c, spec),
                    child: Text(spec.label),
                  ),
                )
                .toList(),
          ),
        ]),
        _section('附件', [
          if (objects(c['attachments']).isEmpty)
            const Text('暂无附件，可上传需求材料或交付文件。'),
          ...objects(c['attachments']).map(
            (a) => ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('${a['name'] ?? a['filename'] ?? a['id']}'),
              subtitle: Text('编号 ${a['id']}'),
              trailing: TextButton(
                onPressed: () => run(() async {
                  if (harmonyHost) {
                    throw ApiFailure('当前鸿蒙宿主尚不支持原件保存，请在 iOS、Android 或桌面端授权下载');
                  }
                  final bytes = await repo.download(c, a);
                  await FilePicker.saveFile(
                    dialogTitle: '保存附件',
                    fileName: '${a['name'] ?? a['filename'] ?? '附件'}',
                    bytes: bytes,
                  );
                }),
                child: const Text('保存'),
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton(
              onPressed: () => run(() async {
                final file = await FilePicker.pickFile();
                if (file == null) return;
                final bytes = await file.readAsBytes();

                await repo.upload(c, file.name, bytes);
              }),
              child: const Text('上传附件（最大 8 MB）'),
            ),
          ),
        ]),
        _section('沟通记录', [
          if (objects(c['messages']).isEmpty) const Text('暂无消息'),
          ...objects(c['messages']).map(
            (m) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                '${m['author_name'] ?? m['author_id'] ?? ''} · ${m['created_at'] ?? ''}\n${m['text']}',
              ),
            ),
          ),
        ]),
        _section('售后记录', [
          if (objects(c['after_sales']).isEmpty) const Text('暂无售后'),
          ...objects(c['after_sales']).map(
            (s) => Text(
              '${s['id']} · ${statusName(s['status'])}\n${s['text'] ?? s['reason'] ?? ''}',
            ),
          ),
        ]),
        _section('进度记录', [
          if (objects(c['events']).isEmpty) const Text('暂无进度记录'),
          ...objects(c['events']).reversed.map(
            (e) => Text(
              '${e['created_at'] ?? ''} · ${e['type'] ?? e['action'] ?? ''}\n${e['text'] ?? ''}',
            ),
          ),
        ]),
      ],
    );
  }

  Widget _actionField(
    Json c,
    ActionSpec spec,
    String key,
    TextEditingController value,
  ) {
    final order = c['order'];
    if (key == 'quote_id') return const Text('将确认上方展示的当前报价。');
    if (key == 'hold_id' && spec.code == 'pause') {
      value.text = value.text.isEmpty ? repo.newKey() : value.text;
      return const Text('系统将为本次暂停单独记录原因，全部原因解除后才能恢复。');
    }
    if (key == 'attachment_ids') {
      final files = objects(c['attachments']);
      return StatefulBuilder(
        builder: (context, setField) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('选择此次交付的附件'),
            if (files.isEmpty) const Text('暂无附件，请先上传文件。'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: files.map((f) {
                final selected = value.text.split(',').contains(f['id']);
                return FilterChip(
                  label: Text('${f['name'] ?? f['id']}'),
                  selected: selected,
                  onSelected: (v) => setField(() {
                    final ids = value.text
                        .split(',')
                        .where((x) => x.isNotEmpty)
                        .toSet();
                    if (v) {
                      ids.add('${f['id']}');
                    } else {
                      ids.remove(f['id']);
                    }
                    value.text = ids.join(',');
                  }),
                );
              }).toList(),
            ),
          ],
        ),
      );
    }
    List<Json>? choices;
    switch (key) {
      case 'payment_id':
        choices = objects(order?['payments']);
        break;
      case 'refund_id':
        choices = objects(order?['refunds'])
            .where(
              (x) => refundStages[spec.code]?.contains(x['status']) ?? false,
            )
            .toList();
        break;
      case 'delivery_id':
        choices = availableDeliveries(c, spec.code);
        break;
      case 'feedback_id':
        choices = objects(order?['feedback'])
            .where((x) => x['status'] == 'requested')
            .toList();
        break;
      case 'change_id':
        choices = objects(order?['changes'])
            .where((x) => x['status'] == 'offered')
            .toList();
        break;
      case 'hold_id':
        choices = objects(order?['holds'])
            .where((x) => '${x['closed_at'] ?? ''}'.isEmpty)
            .toList();
        break;
      case 'after_sale_id':
        choices = objects(c['after_sales'])
            .where((x) => x['status'] == 'open')
            .toList();
        break;
    }
    if (choices != null) {
      final optional = key == 'after_sale_id' && spec.code == 'deliver';
      if (!optional &&
          choices.isNotEmpty &&
          !choices.any((x) => x['id'] == value.text)) {
        value.text = '${choices.first['id']}';
      }
      if (optional && value.text.isEmpty) value.text = '';
      if (choices.isEmpty && !optional) {
        return Text('暂无可选择的${fieldLabels[key] ?? key}，请返回核对进度。');
      }
      return DropdownButtonFormField<String>(
        initialValue: value.text.isEmpty
            ? optional
                  ? ''
                  : null
            : value.text,
        isExpanded: true,
        decoration: InputDecoration(labelText: fieldLabels[key]),
        items: [
          if (optional) const DropdownMenuItem(value: '', child: Text('主服务交付')),
          ...choices.map(
            (x) => DropdownMenuItem(
              value: '${x['id']}',
              child: Text(
                '${x['amount_minor'] != null ? money(x['amount_minor']) : x['text'] ?? x['reason'] ?? x['scope'] ?? '版本 ${x['version'] ?? ''}'} · ${statusName(x['status'] ?? 'open')}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
        onChanged: (v) => value.text = v ?? '',
      );
    }
    if (key == 'round_id' && value.text.isEmpty) value.text = repo.newKey();
    return TextField(
      controller: value,
      minLines: ['text', 'scope'].contains(key) ? 3 : 1,
      maxLines: ['text', 'scope'].contains(key) ? 6 : 1,
      decoration: InputDecoration(
        labelText: fieldLabels[key] ?? key,
        helperText: key == 'round_id' ? '新轮次已自动生成；同一受理轮的补充可填已有轮次标识' : null,
      ),
    );
  }

  Future<void> _action(Json c, ActionSpec spec) async {
    final values = <String, TextEditingController>{
      for (final f in spec.fields) f: TextEditingController(),
    };
    values['quote_id']?.text = '${c['quote']?['id'] ?? ''}';
    values['expires_at']?.text = DateTime.now()
        .toUtc()
        .add(const Duration(days: 7))
        .toIso8601String();
    values['revision_limit']?.text = '2';
    values['prepay_minor']?.text = '0';
    values['count_units']?.text = '1';
    final deliveries = objects(c['order']?['deliveries']);
    if (deliveries.isNotEmpty) {
      values['delivery_id']?.text = '${deliveries.last['id']}';
    }
    final result = await _dialog(
      spec.label,
      [
        if (spec.warning != null) Text(spec.warning!),
        if (spec.code == 'accept_quote')
          Text(
            '${money(c['quote']?['amount_minor'])}\n${c['quote']?['scope']}\n有效期 ${c['quote']?['expires_at']}',
          ),
        if (spec.code == 'confirm_cancel')
          Text('结算方案：${c['order']?['cancellation'] ?? '请核对最新方案'}'),
        ...values.entries.map((e) => _actionField(c, spec, e.key, e.value)),
      ],
      () {
        final body = <String, dynamic>{};
        for (final e in values.entries) {
          final v = e.value.text.trim();
          if (e.key.endsWith('_minor')) {
            if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(v)) {
              throw ApiFailure('金额须为非负数，最多两位小数');
            }
            final parts = v.split('.');
            body[e.key] =
                int.parse(parts[0]) * 100 +
                int.parse((parts.length == 2 ? parts[1] : '').padRight(2, '0'));
          } else if (['revision_limit', 'count_units'].contains(e.key)) {
            final n = int.tryParse(v);
            if (n == null || n < 0) throw ApiFailure('轮数须为非负整数');
            body[e.key] = n;
          } else if (e.key == 'attachment_ids') {
            body[e.key] = v
                .split(',')
                .map((s) => s.trim())
                .where((s) => s.isNotEmpty)
                .toList();
          } else if (e.key == 'after_sale_id' && v.isEmpty) {
            continue;
          } else if (e.key == 'deadline' && v.isEmpty) {
            continue;
          } else {
            if (v.isEmpty) {
              throw ApiFailure('请填写${fieldLabels[e.key] ?? e.key}');
            }
            body[e.key] = v;
          }
        }
        return body;
      },
    );
    for (final v in values.values) {
      v.dispose();
    }
    if (result != null) {
      await run(() async {
        await repo.action(c, spec.code, object(result));
      });
    }
  }

  // A popped dialog still owns its controllers until its reverse transition ends.
  Future<T?> _showDialog<T>({required WidgetBuilder builder}) async {
    final navigator = Navigator.of(context, rootNavigator: true);
    final route = DialogRoute<T>(
      context: context,
      themes: InheritedTheme.capture(from: context, to: navigator.context),
      builder: builder,
    );
    final result = await navigator.push(route);
    await route.completed;
    return result;
  }

  Future<dynamic> _dialog(
    String title,
    List<Widget> children,
    dynamic Function() submit, {
    Widget? extra,
  }) => _showDialog<dynamic>(
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children
                .map(
                  (w) => Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: w,
                  ),
                )
                .toList(),
          ),
        ),
      ),
      actions: [
        ?extra,
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            try {
              Navigator.pop(dialogContext, submit());
            } catch (e) {
              tell(e);
            }
          },
          child: const Text('确认'),
        ),
      ],
    ),
  );
}
