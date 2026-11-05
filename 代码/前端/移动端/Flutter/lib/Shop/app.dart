import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../Data/models.dart';
import '../Data/repository.dart' show ApiFailure;
import '../Ui/app.dart' show defaultApiUrl;
import 'repository.dart';
import 'strings.dart';

int? parseShopPrice(String value) {
  if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(value)) return null;
  final parts = value.split('.');
  final whole = int.tryParse(parts.first);
  if (whole == null) return null;
  final minor =
      whole * 100 +
      int.parse(parts.length == 1 ? '0' : parts.last.padRight(2, '0'));
  return minor >= 0 && minor <= 100000000000 ? minor : null;
}

ThemeData shopTheme(Brightness brightness, {bool packaged = false}) {
  final dark = brightness == Brightness.dark;
  final colors =
      ColorScheme.fromSeed(
        seedColor: const Color(0xff85533b),
        brightness: brightness,
      ).copyWith(
        surface: Color(dark ? 0xff211b18 : 0xfffff9f0),
        onSurface: Color(dark ? 0xfffff3e6 : 0xff30221b),
        onSurfaceVariant: Color(dark ? 0xffd5c2b3 : 0xff6b5547),
        primary: Color(dark ? 0xffefbc9c : 0xff85533b),
        onPrimary: Color(dark ? 0xff382419 : 0xffffffff),
      );
  return ThemeData(
    useMaterial3: true,
    fontFamilyFallback: [
      packaged ? 'packages/zhixu/NotoSerifTibetan' : 'NotoSerifTibetan',
      packaged ? 'packages/zhixu/NotoSansCJKsc' : 'NotoSansCJKsc',
    ],
    colorScheme: colors,
    scaffoldBackgroundColor: colors.surface,
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: Color(dark ? 0xff2d2520 : 0xffffffff),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: colors.outlineVariant),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(44, 48),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(minimumSize: const Size(44, 48)),
    ),
  );
}

class ShopApp extends StatefulWidget {
  const ShopApp({super.key, this.adminMode = false, this.repository});
  final bool adminMode;
  final ShopRepository? repository;
  @override
  State<ShopApp> createState() => _ShopAppState();
}

class _ShopAppState extends State<ShopApp> {
  late final ShopRepository repo =
      widget.repository ?? ShopRepository(baseUrl: defaultApiUrl());
  String language = 'zh';
  ThemeMode mode = ThemeMode.system;
  @override
  void initState() {
    super.initState();
    unawaited(_restore());
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        final saved = prefs.getString('shop-language');
        if (shopLanguages.containsKey(saved)) language = saved!;
        mode = ThemeMode.values.firstWhere(
          (v) => v.name == prefs.getString('shop-theme'),
          orElse: () => ThemeMode.system,
        );
      });
      final url = prefs.getString('shop-api');
      if (widget.repository == null && url != null) {
        repo.configure(url, prefs.getInt('shop-timeout') ?? 2200);
      }
    } catch (_) {}
    try {
      await repo.refresh();
    } catch (_) {}
  }

  Future<void> _preferences(String lang, ThemeMode theme) async {
    setState(() {
      language = lang;
      mode = theme;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('shop-language', lang);
      await prefs.setString('shop-theme', theme.name);
    } catch (_) {}
  }

  @override
  void dispose() {
    if (widget.repository == null) repo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: shopText(language, widget.adminMode ? 'admin' : 'shop'),
    debugShowCheckedModeBanner: false,
    theme: shopTheme(Brightness.light, packaged: widget.adminMode),
    darkTheme: shopTheme(Brightness.dark, packaged: widget.adminMode),
    themeMode: mode,
    home: ShopWorkspace(
      repo: repo,
      adminMode: widget.adminMode,
      language: language,
      mode: mode,
      onPreferences: _preferences,
    ),
  );
}

class ShopWorkspace extends StatefulWidget {
  const ShopWorkspace({
    super.key,
    required this.repo,
    required this.adminMode,
    required this.language,
    required this.mode,
    required this.onPreferences,
  });
  final ShopRepository repo;
  final bool adminMode;
  final String language;
  final ThemeMode mode;
  final Future<void> Function(String, ThemeMode) onPreferences;
  @override
  State<ShopWorkspace> createState() => _ShopWorkspaceState();
}

class _ShopWorkspaceState extends State<ShopWorkspace> {
  ShopRepository get repo => widget.repo;
  String t(String key) => shopText(widget.language, key);
  String _sellerState(Json order) {
    if (order['seller_status'] is String) return order['seller_status'];
    switch (order['status']) {
      case 'pending_payment':
        return 'awaiting_payment';
      case 'pending_completion':
        return order['fulfillment_status'] == 'delivered'
            ? 'awaiting_confirmation'
            : order['fulfillment_status'] == 'in_progress'
            ? 'in_progress'
            : 'pending_delivery';
      case 'pending_review':
        return 'awaiting_review';
      default:
        return '${order['status']}';
    }
  }

  int page = 0;
  String category = 'all', filter = 'all';
  String? productId;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    repo.addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    repo.removeListener(_changed);
    super.dispose();
  }

  void _tell(Object e) {
    if (!mounted) return;
    final message = e.toString();
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(t(message))));
  }

  Future<void> _run(Future<void> Function() task) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await task();
    } catch (e) {
      _tell(e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => DisplayFeatureSubScreen(
    anchorPoint: Offset.zero,
    child: LayoutBuilder(
      builder: (context, c) {
        final compact = c.maxWidth < 650;
        return Scaffold(
          appBar: AppBar(
            title: Text(t(widget.adminMode ? 'admin' : 'shop')),
            actions: [
              if (!compact)
                TextButton(
                  onPressed: busy ? null : () => _run(repo.refresh),
                  child: Text(t('reload')),
                ),
              TextButton(
                onPressed: () => _settings(),
                child: Text(t('settings')),
              ),
              if (!compact)
                TextButton(
                  onPressed: () => _login(),
                  child: Text(
                    repo.user == null ? t('login') : '${repo.user!['name']}',
                  ),
                ),
            ],
          ),
          body: SafeArea(
            child: Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 8,
                  ),
                  color: Theme.of(context).colorScheme.secondaryContainer,
                  child: Text(
                    t(repo.demo ? 'offline' : 'online'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSecondaryContainer,
                    ),
                  ),
                ),
                if (busy) const LinearProgressIndicator(minHeight: 2),
                if (repo.pending != null)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        Text(t('pendingWrite')),
                        OutlinedButton(
                          onPressed: busy
                              ? null
                              : () => _run(() async {
                                  await repo.reconcilePending();
                                }),
                          child: Text(t('reconcile')),
                        ),
                        OutlinedButton(
                          onPressed: busy
                              ? null
                              : () => _run(() async {
                                  await repo.retryPending();
                                }),
                          child: Text(t('retry')),
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1320),
                      child: page == 0 ? _catalogue() : _orders(),
                    ),
                  ),
                ),
              ],
            ),
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: page,
            onDestinationSelected: (i) => setState(() {
              page = i;
              productId = null;
            }),
            destinations: [
              NavigationDestination(
                icon: const Text('01'),
                label: t('products'),
              ),
              NavigationDestination(icon: const Text('02'), label: t('orders')),
            ],
          ),
        );
      },
    ),
  );
  Widget _empty(String key) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(t(key), style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          Text(t('emptyHint'), textAlign: TextAlign.center),
          const SizedBox(height: 20),
          OutlinedButton(
            onPressed: busy ? null : () => _run(repo.refresh),
            child: Text(t('reload')),
          ),
        ],
      ),
    ),
  );
  Widget _brand() => Image.asset(
    'Assets/shop-brand.png',
    package: widget.adminMode ? 'zhixu' : null,
    fit: BoxFit.contain,
    errorBuilder: (_, _, _) => Text(
      t('shop'),
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.titleLarge,
    ),
  );
  Widget _image(Json p, {double height = 160}) {
    final path = '${p['image'] ?? ''}';
    Uri? uri = Uri.tryParse(path);
    if (path.startsWith('/') && !path.startsWith('//')) {
      uri = Uri.parse(repo.baseUrl).resolve(path);
    }
    final fallback = Center(
      child: SizedBox(width: 96, height: 96, child: _brand()),
    );
    Widget image = fallback;
    if (path.startsWith('data:image/')) {
      try {
        image = Image.memory(
          base64Decode(path.split(',').last),
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) => fallback,
        );
      } catch (_) {
        image = fallback;
      }
    } else if (path.isNotEmpty &&
        uri != null &&
        (uri.scheme == 'https' ||
            (uri.hasAuthority &&
                uri.origin == Uri.parse(repo.baseUrl).origin &&
                uri.scheme == 'http'))) {
      image = Image.network(
        uri.toString(),
        fit: BoxFit.contain,
        loadingBuilder: (_, child, progress) =>
            progress == null ? child : fallback,
        errorBuilder: (_, _, _) => fallback,
      );
    } else if (path.isNotEmpty &&
        uri != null &&
        !uri.hasScheme &&
        !path.startsWith('/')) {
      image = Image.asset(
        path,
        package: widget.adminMode ? 'zhixu' : null,
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => fallback,
      );
    }
    return Container(
      height: height,
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: image,
    );
  }

  Widget _catalogue() {
    final selected = repo.products
        .where((p) => p['id'] == productId)
        .firstOrNull;
    if (selected != null) return _detail(selected);
    final list = repo.products
        .where(
          (p) =>
              (widget.adminMode || p['active'] == true) &&
              (category == 'all' || p['category_id'] == category),
        )
        .toList();
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          t('hero'),
          style: Theme.of(context).textTheme.headlineLarge
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        Text(t('intro'), style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 24),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final key in ['all', 'graduation', 'journal', 'editing'])
              ChoiceChip(
                label: Text(t(key)),
                selected: category == key,
                onSelected: (_) => setState(() => category = key),
              ),
          ],
        ),
        if (widget.adminMode)
          Padding(
            padding: const EdgeInsets.only(top: 20),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton(
                  onPressed: busy
                      ? null
                      : () => repo.admin ? _edit() : _login(),
                  child: Text(t('newProduct')),
                ),
                Text(t('sellerWaiting')),
              ],
            ),
          ),
        const SizedBox(height: 24),
        if (list.isEmpty)
          _empty('emptyProducts')
        else
          LayoutBuilder(
            builder: (context, c) {
              final columns = c.maxWidth >= 1000
                  ? 3
                  : c.maxWidth >= 620
                  ? 2
                  : 1;
              final width = (c.maxWidth - (columns - 1) * 18) / columns;
              return Wrap(
                spacing: 18,
                runSpacing: 18,
                children: [
                  for (final p in list)
                    SizedBox(
                      width: width,
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _image(p),
                              const SizedBox(height: 16),
                              Text(
                                '${t('${p['category_id']}')} · ${t('${p['kind']}')}',
                                style: TextStyle(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '${p['name']}',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              const SizedBox(height: 8),
                              Text('${p['summary'] ?? ''}'),
                              const SizedBox(height: 16),
                              Wrap(
                                spacing: 8,
                                runSpacing: 6,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Text(
                                    money(p['price_minor']),
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge
                                        ?.copyWith(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .primary,
                                        ),
                                  ),
                                  if (p['is_demo'] == true)
                                    Text(t('demoGoods')),
                                  if (p['in_stock'] != true)
                                    Text(t('outOfStock')),
                                  if (p['active'] != true) Text(t('inactive')),
                                ],
                              ),
                              const SizedBox(height: 16),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton(
                                  onPressed: () =>
                                      setState(() => productId = p['id']),
                                  child: Text(t('details')),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
      ],
    );
  }

  Widget _detail(Json p) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          onPressed: () => setState(() => productId = null),
          child: Text(t('back')),
        ),
      ),
      const SizedBox(height: 12),
      _image(p, height: 220),
      const SizedBox(height: 24),
      Text('${p['name']}', style: Theme.of(context).textTheme.headlineMedium),
      const SizedBox(height: 12),
      Text('${p['summary'] ?? ''}'),
      const SizedBox(height: 16),
      Text(
        money(p['price_minor']),
        style: Theme.of(context).textTheme.headlineMedium
            ?.copyWith(color: Theme.of(context).colorScheme.primary),
      ),
      if (p['is_demo'] == true) Text(t('demoGoods')),
      const SizedBox(height: 20),
      Text('${p['description'] ?? ''}'),
      for (final section in objects(p['sections']))
        Padding(
          padding: const EdgeInsets.only(top: 24),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${section['title']}',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  Text('${section['body']}'),
                ],
              ),
            ),
          ),
        ),
      const SizedBox(height: 24),
      if (widget.adminMode)
        FilledButton(
          onPressed: repo.admin && !busy ? () => _edit(p) : null,
          child: Text(t('edit')),
        )
      else
        FilledButton(
          onPressed: busy || p['active'] != true || p['in_stock'] != true
              ? null
              : () async {
                  if (repo.user == null) {
                    await _login();
                    return;
                  }
                  Json? result;
                  await _run(() async {
                    result = await repo.buy(p);
                  });
                  if (!mounted || result == null) return;
                  setState(() {
                    page = 1;
                    productId = null;
                    filter = 'all';
                  });
                  await _checkout(object(result!['order']));
                },
          child: Text(t(p['in_stock'] == true ? 'buy' : 'outOfStock')),
        ),
    ],
  );
  Widget _orders() {
    if (repo.user == null) {
      return Center(
        child: FilledButton(
          onPressed: () => _login(),
          child: Text(t('signInFirst')),
        ),
      );
    }
    final list = repo.orders
        .where((o) => filter == 'all' || o['status'] == filter)
        .toList();
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(t('orders'), style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 20),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final key in [
              'all',
              'pending_payment',
              'pending_completion',
              'pending_review',
              'completed',
              'cancelled',
            ])
              ChoiceChip(
                label: Text(t(key)),
                selected: filter == key,
                onSelected: (_) => setState(() => filter = key),
              ),
          ],
        ),
        const SizedBox(height: 20),
        if (list.isEmpty) _empty('emptyOrders'),
        for (final order in list) _order(order),
      ],
    );
  }

  Widget _order(Json order) {
    final p = object(order['product_snapshot']);
    final status = '${order['status']}';
    final fulfill = '${order['fulfillment_status']}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${p['name']}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                '${order['id']}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 6,
                children: [
                  Chip(
                    label: Text(t(repo.admin ? _sellerState(order) : status)),
                  ),
                  if (status == 'pending_completion')
                    Chip(label: Text(t(fulfill))),
                  Text(
                    money(order['amount_minor']),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ],
              ),
              if (order['payment'] is Map)
                Text(
                  '${t('mockRecord')} · ${t('${order['payment']['channel']}')} · ${money(order['payment']['amount_minor'])}',
                ),
              if ('${order['delivery_text'] ?? ''}'.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text('${order['delivery_text']}'),
                ),
              if (order['review'] is Map)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    '${t('rating')}: ${order['review']['rating']}/5\n${order['review']['text']}',
                  ),
                ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  if (!repo.admin && status == 'pending_payment') ...[
                    FilledButton(
                      onPressed: busy ? null : () => _checkout(order),
                      child: Text(t('checkout')),
                    ),
                    OutlinedButton(
                      onPressed: busy
                          ? null
                          : () => _run(() async {
                              await repo.action(order, 'cancel');
                            }),
                      child: Text(t('cancel')),
                    ),
                  ],
                  if (repo.admin &&
                      status == 'pending_completion' &&
                      fulfill == 'pending')
                    FilledButton(
                      onPressed: busy
                          ? null
                          : () => _run(() async {
                              await repo.action(order, 'start');
                            }),
                      child: Text(t('start')),
                    ),
                  if (repo.admin &&
                      status == 'pending_completion' &&
                      fulfill != 'delivered')
                    FilledButton(
                      onPressed: busy
                          ? null
                          : () => _textAction(order, 'deliver'),
                      child: Text(t('deliver')),
                    ),
                  if (!repo.admin &&
                      status == 'pending_completion' &&
                      fulfill == 'delivered')
                    FilledButton(
                      onPressed: busy
                          ? null
                          : () => _run(() async {
                              await repo.action(order, 'accept');
                            }),
                      child: Text(t('accept')),
                    ),
                  if (!repo.admin && status == 'pending_review')
                    FilledButton(
                      onPressed: busy
                          ? null
                          : () => _textAction(order, 'review'),
                      child: Text(t('review')),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _checkout(Json order) async {
    var channel = 'alipay', sending = false;
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: Text(t('checkout')),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${order['product_snapshot']['name']}',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  Text(money(order['amount_minor'])),
                  const SizedBox(height: 18),
                  Text(t('mockHint')),
                  const SizedBox(height: 18),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      for (final key in ['alipay', 'wechat'])
                        ChoiceChip(
                          label: Text(t(key)),
                          selected: channel == key,
                          onSelected: sending
                              ? null
                              : (_) => setDialog(() => channel = key),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: sending ? null : () => Navigator.pop(context),
              child: Text(t('cancel')),
            ),
            FilledButton(
              onPressed: sending
                  ? null
                  : () async {
                      setDialog(() => sending = true);
                      try {
                        await repo.action(order, 'pay', {'channel': channel});
                        if (context.mounted) Navigator.pop(context);
                      } catch (e) {
                        _tell(e);
                        if (context.mounted) setDialog(() => sending = false);
                      }
                    },
              child: Text(t('confirmPay')),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _login() async {
    var account = widget.adminMode ? 'admin' : 'customer',
        password = '',
        sending = false;
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: Text(t('login')),
          content: SizedBox(
            width: 430,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    initialValue: account,
                    decoration: InputDecoration(labelText: t('account')),
                    onChanged: (v) => account = v,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    obscureText: true,
                    decoration: InputDecoration(labelText: t('password')),
                    onChanged: (v) => password = v,
                  ),
                  const SizedBox(height: 16),
                  Text(t('loginHint')),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: sending ? null : () => Navigator.pop(context),
              child: Text(t('cancel')),
            ),
            FilledButton(
              onPressed: sending
                  ? null
                  : () async {
                      setDialog(() => sending = true);
                      try {
                        await repo.login(
                          account,
                          password,
                          asAdmin: widget.adminMode,
                        );
                        if (context.mounted) Navigator.pop(context);
                      } catch (e) {
                        _tell(e);
                        if (context.mounted) setDialog(() => sending = false);
                      }
                    },
              child: Text(t('login')),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _textAction(Json order, String action) async {
    String text = '';
    var rating = 5, sending = false;
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: Text(t(action)),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    decoration: InputDecoration(labelText: t('text')),
                    minLines: 3,
                    maxLines: 7,
                    onChanged: (v) => text = v,
                  ),
                  if (action == 'review')
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: DropdownButtonFormField<int>(
                        initialValue: rating,
                        decoration: InputDecoration(labelText: t('rating')),
                        items: [
                          for (var i = 1; i <= 5; i++)
                            DropdownMenuItem(value: i, child: Text('$i / 5')),
                        ],
                        onChanged: (v) => rating = v ?? 5,
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: sending ? null : () => Navigator.pop(context),
              child: Text(t('cancel')),
            ),
            FilledButton(
              onPressed: sending
                  ? null
                  : () async {
                      if (text.trim().isEmpty) {
                        _tell(t('required'));
                        return;
                      }
                      setDialog(() => sending = true);
                      try {
                        await repo.action(order, action, {
                          'text': text.trim(),
                          if (action == 'review') 'rating': rating,
                        });
                        if (context.mounted) Navigator.pop(context);
                      } catch (e) {
                        _tell(e);
                        if (context.mounted) setDialog(() => sending = false);
                      }
                    },
              child: Text(t('save')),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _edit([Json? original]) async {
    var product = original == null
        ? <String, dynamic>{
            'name': '',
            'summary': '',
            'description': '',
            'image': '',
            'category_id': 'graduation',
            'kind': 'service',
            'active': true,
            'in_stock': true,
            'currency': 'CNY',
            'sections': <Json>[],
            'is_demo': false,
          }
        : copy(original);
    String price = ((product['price_minor'] as num? ?? 0) / 100)
        .toStringAsFixed(2);
    final sections = objects(product['sections']);
    var sending = false;
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: Text(t(original == null ? 'newProduct' : 'edit')),
          content: SizedBox(
            width: 620,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final key in ['name', 'summary', 'description', 'image'])
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: TextFormField(
                        initialValue: '${product[key] ?? ''}',
                        decoration: InputDecoration(
                          labelText: t(key == 'description' ? 'text' : key),
                        ),
                        minLines: key == 'description' ? 3 : 1,
                        maxLines: key == 'description' ? 6 : 1,
                        onChanged: (v) => product[key] = v,
                      ),
                    ),
                  TextFormField(
                    initialValue: price,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(labelText: t('price')),
                    onChanged: (v) => price = v,
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: product['category_id'],
                    items: [
                      for (final key in ['graduation', 'journal', 'editing'])
                        DropdownMenuItem(value: key, child: Text(t(key))),
                    ],
                    onChanged: (v) => product['category_id'] = v,
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: product['kind'],
                    items: [
                      for (final key in ['course', 'service'])
                        DropdownMenuItem(value: key, child: Text(t(key))),
                    ],
                    onChanged: (v) => product['kind'] = v,
                  ),
                  const SizedBox(height: 16),
                  for (final row in sections)
                    Padding(
                      key: ValueKey(row),
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Column(
                        children: [
                          TextFormField(
                            initialValue: '${row['title'] ?? ''}',
                            decoration: InputDecoration(
                              labelText: t('sectionTitle'),
                            ),
                            onChanged: (v) => row['title'] = v,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            initialValue: '${row['body'] ?? ''}',
                            decoration: InputDecoration(labelText: t('text')),
                            minLines: 2,
                            maxLines: 8,
                            onChanged: (v) => row['body'] = v,
                          ),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: sending
                                  ? null
                                  : () => setDialog(() => sections.remove(row)),
                              child: Text(t('remove')),
                            ),
                          ),
                        ],
                      ),
                    ),
                  OutlinedButton(
                    onPressed: sending || sections.length >= 30
                        ? null
                        : () => setDialog(
                            () => sections.add({'title': '', 'body': ''}),
                          ),
                    child: Text(t('addSection')),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(t('active')),
                    value: product['active'] == true,
                    onChanged: (v) => setDialog(() => product['active'] = v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(t('inStock')),
                    value: product['in_stock'] == true,
                    onChanged: (v) => setDialog(() => product['in_stock'] = v),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: sending ? null : () => Navigator.pop(context),
              child: Text(t('cancel')),
            ),
            FilledButton(
              onPressed: sending
                  ? null
                  : () async {
                      if ('${product['name']}'.trim().isEmpty ||
                          '${product['description']}'.trim().isEmpty ||
                          parseShopPrice(price) == null ||
                          sections.any(
                            (row) => '${row['title'] ?? ''}'.trim().isEmpty,
                          )) {
                        _tell(t('required'));
                        return;
                      }
                      product['price_minor'] = parseShopPrice(price);
                      product['sections'] = sections;
                      product.remove('id');
                      product.remove('version');
                      setDialog(() => sending = true);
                      try {
                        await repo.saveProduct(
                          product,
                          id: original?['id'],
                          version: original?['version'],
                        );
                        if (context.mounted) Navigator.pop(context);
                      } catch (e) {
                        _tell(e);
                        if (context.mounted) setDialog(() => sending = false);
                      }
                    },
              child: Text(t('save')),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _settings() async {
    var language = widget.language,
        mode = widget.mode,
        url = repo.baseUrl,
        timeout = repo.timeoutMs.toString();
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: Text(t('settings')),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: language,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: t('language')),
                    items: shopLanguages.entries
                        .map(
                          (e) => DropdownMenuItem(
                            value: e.key,
                            child: Text(e.value),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setDialog(() => language = v);
                    },
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<ThemeMode>(
                    initialValue: mode,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: t('theme')),
                    items: ThemeMode.values
                        .map(
                          (v) => DropdownMenuItem(
                            value: v,
                            child: Text(t(v.name)),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setDialog(() => mode = v);
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    initialValue: url,
                    decoration: InputDecoration(labelText: t('api')),
                    onChanged: (v) => url = v,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    initialValue: timeout,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(labelText: t('timeout')),
                    onChanged: (v) => timeout = v,
                  ),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                      _login();
                    },
                    child: Text(t('login')),
                  ),
                  if (repo.user != null)
                    TextButton(
                      onPressed: () {
                        repo.logout();
                        Navigator.pop(context);
                      },
                      child: Text(t('logout')),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(t('cancel')),
            ),
            FilledButton(
              onPressed: () async {
                try {
                  final parsed = int.tryParse(timeout);
                  if (parsed == null) throw ApiFailure('required');
                  if (url != repo.baseUrl || parsed != repo.timeoutMs) {
                    repo.configure(url, parsed);
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setString('shop-api', url);
                    await prefs.setInt('shop-timeout', parsed);
                  }
                  await widget.onPreferences(language, mode);
                  if (context.mounted) Navigator.pop(context);
                  await repo.refresh();
                } catch (e) {
                  _tell(e);
                }
              },
              child: Text(t('save')),
            ),
          ],
        ),
      ),
    );
  }
}
