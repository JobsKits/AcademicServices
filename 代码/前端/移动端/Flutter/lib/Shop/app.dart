import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../Data/models.dart';
import '../Data/repository.dart' show ApiFailure;
import '../Ui/app.dart' show defaultApiUrl;
import 'repository.dart';
import 'strings.dart';
import 'media.dart';
import 'carousel.dart';
import 'navigation.dart';
import 'browser_link.dart';
import 'auth.dart';

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
        surface: Color(dark ? 0xff191612 : 0xfffbf7f0),
        surfaceContainerLowest: Color(dark ? 0xff24201b : 0xfffffcf7),
        surfaceContainerLow: Color(dark ? 0xff2c261f : 0xfff2ebe0),
        surfaceContainer: Color(dark ? 0xff332b23 : 0xffebe1d3),
        onSurface: Color(dark ? 0xfff5eadc : 0xff352a24),
        onSurfaceVariant: Color(dark ? 0xffcdbba8 : 0xff6f5b4e),
        primary: Color(dark ? 0xffe2b58c : 0xff865338),
        onPrimary: Color(dark ? 0xff2d1f14 : 0xffffffff),
        primaryContainer: Color(dark ? 0xff473527 : 0xfff0e2d0),
        onPrimaryContainer: Color(dark ? 0xfff3e2ce : 0xff633e2b),
        secondaryContainer: Color(dark ? 0xff312a21 : 0xffece4d8),
        onSecondaryContainer: Color(dark ? 0xffddcbb6 : 0xff5d493b),
        outline: Color(dark ? 0xff8b7765 : 0xff9d8875),
        outlineVariant: Color(dark ? 0xff514438 : 0xffded3c5),
      );
  final text = ThemeData(brightness: brightness).textTheme.apply(
    fontFamily: packaged ? 'packages/zhixu/NotoSansCJKsc' : 'NotoSansCJKsc',
    fontFamilyFallback: [
      packaged ? 'packages/zhixu/NotoSerifTibetan' : 'NotoSerifTibetan',
    ],
    bodyColor: colors.onSurface,
    displayColor: colors.onSurface,
  );
  final fieldBorder = OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: BorderSide(color: colors.outlineVariant),
  );
  return ThemeData(
    useMaterial3: true,
    fontFamily: packaged ? 'packages/zhixu/NotoSansCJKsc' : 'NotoSansCJKsc',
    fontFamilyFallback: [
      packaged ? 'packages/zhixu/NotoSerifTibetan' : 'NotoSerifTibetan',
      packaged ? 'packages/zhixu/NotoSansCJKsc' : 'NotoSansCJKsc',
    ],
    colorScheme: colors,
    textTheme: text.copyWith(
      headlineMedium: text.headlineMedium?.copyWith(
        fontSize: 30,
        fontWeight: FontWeight.w700,
        height: 1.3,
      ),
      headlineSmall: text.headlineSmall?.copyWith(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        height: 1.35,
      ),
      titleLarge: text.titleLarge?.copyWith(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        height: 1.4,
      ),
      titleMedium: text.titleMedium?.copyWith(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        height: 1.45,
      ),
      bodyLarge: text.bodyLarge?.copyWith(fontSize: 17, height: 1.65),
      bodyMedium: text.bodyMedium?.copyWith(fontSize: 16, height: 1.6),
      bodySmall: text.bodySmall?.copyWith(
        fontSize: 13,
        height: 1.5,
        color: colors.onSurfaceVariant,
      ),
      labelLarge: text.labelLarge?.copyWith(
        fontSize: 15,
        fontWeight: FontWeight.w600,
      ),
    ),
    scaffoldBackgroundColor: colors.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: colors.surfaceContainerLowest,
      foregroundColor: colors.onSurface,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      elevation: 0,
      centerTitle: false,
      titleSpacing: 24,
      titleTextStyle: text.titleLarge?.copyWith(
        fontSize: 20,
        fontWeight: FontWeight.w700,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colors.surfaceContainerLowest,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      border: fieldBorder,
      enabledBorder: fieldBorder,
      focusedBorder: fieldBorder.copyWith(
        borderSide: BorderSide(color: colors.primary, width: 2),
      ),
      labelStyle: TextStyle(color: colors.onSurfaceVariant),
      hintStyle: TextStyle(color: colors.onSurfaceVariant),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: colors.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colors.outlineVariant),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: colors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titleTextStyle: text.headlineSmall?.copyWith(
        fontSize: 24,
        fontWeight: FontWeight.w700,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: colors.surfaceContainerLowest,
      surfaceTintColor: Colors.transparent,
      indicatorColor: colors.primaryContainer,
      labelTextStyle: WidgetStatePropertyAll(
        text.labelMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: colors.primary,
      unselectedLabelColor: colors.onSurfaceVariant,
      labelStyle: text.titleMedium,
      unselectedLabelStyle: text.titleMedium?.copyWith(
        fontWeight: FontWeight.w400,
      ),
      dividerColor: colors.outlineVariant,
      indicatorSize: TabBarIndicatorSize.label,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(44, 48),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(44, 48),
        side: BorderSide(color: colors.outline),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
  );
}

class ShopApp extends StatefulWidget {
  const ShopApp({
    super.key,
    this.adminMode = false,
    this.repository,
    this.initialLocation,
  });
  final bool adminMode;
  final ShopRepository? repository;
  final String? initialLocation;
  @override
  State<ShopApp> createState() => _ShopAppState();
}

class _ShopAppState extends State<ShopApp> {
  late final ShopRepository repo =
      widget.repository ?? ShopRepository(baseUrl: defaultApiUrl());
  final navigation = ShopNavigation();
  late final router = ShopRouterDelegate(
    navigation,
    (_) => ShopWorkspace(
      repo: repo,
      adminMode: widget.adminMode,
      language: language,
      mode: mode,
      onPreferences: _preferences,
      navigation: navigation,
    ),
  );
  late final routeProvider = PlatformRouteInformationProvider(
    initialRouteInformation: RouteInformation(
      uri: Uri.parse(
        widget.initialLocation ??
            WidgetsBinding.instance.platformDispatcher.defaultRouteName,
      ),
    ),
  );
  late final routeParser = ShopRouteParser(admin: widget.adminMode);
  String language = 'zh';
  ThemeMode mode = ThemeMode.system;
  @override
  void initState() {
    super.initState();
    navigation.go(ShopLocation.parse(routeProvider.value.uri));
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
      // Connection overrides belong to an explicitly configured Demo only.
      await repo.loadConfiguration();
      final url = prefs.getString('shop-api');
      if (widget.repository == null && repo.demoMode && url != null) {
        repo.configure(url, prefs.getInt('shop-timeout') ?? 2200);
      }
    } catch (_) {}
    try {
      await repo.refresh();
      // Preference restoration can supersede the workspace's first config request.
      if (widget.adminMode && !repo.admin) await repo.bootstrapAdmin();
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
    router.dispose();
    routeProvider.dispose();
    navigation.dispose();
    if (widget.repository == null) repo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    title: shopText(language, widget.adminMode ? 'admin' : 'shop'),
    debugShowCheckedModeBanner: false,
    theme: shopTheme(Brightness.light, packaged: widget.adminMode),
    darkTheme: shopTheme(Brightness.dark, packaged: widget.adminMode),
    themeMode: mode,
    routerDelegate: router,
    routeInformationProvider: routeProvider,
    routeInformationParser: routeParser,
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
    required this.navigation,
  });
  final ShopRepository repo;
  final ShopNavigation navigation;
  final bool adminMode;
  final String language;
  final ThemeMode mode;
  final Future<void> Function(String, ThemeMode) onPreferences;
  @override
  State<ShopWorkspace> createState() => _ShopWorkspaceState();
}

class _ShopWorkspaceState extends State<ShopWorkspace>
    with SingleTickerProviderStateMixin {
  ShopRepository get repo => widget.repo;
  String t(String key) => shopText(widget.language, key);
  String get displayName {
    for (final key in ['username', 'name', 'account']) {
      final value = '${repo.user?[key] ?? ''}'.trim();
      if (value.isNotEmpty) return value;
    }
    return t('mine');
  }

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

  ShopLocation get location => widget.navigation.location;
  int get page => location.page;
  String get category => location.category;
  String get filter => location.status;
  String? get productId => location.productId;
  late final TabController categoryTabs = TabController(
    length: 3,
    vsync: this,
    initialIndex: shopCategories.indexOf(category),
  );
  late final PageController categoryPages = PageController(
    initialPage: shopCategories.indexOf(category),
  );
  String? operationError;
  String savedCategory = 'graduation', savedOrderFilter = 'all';
  void _selectDestination(int destination) => _navigate(
    ShopLocation(
      page: destination,
      category: savedCategory,
      status: destination == 1 ? savedOrderFilter : 'all',
    ),
  );
  void _navigate(ShopLocation next) async {
    if (!widget.adminMode && next.page != 0 && repo.user == null) {
      await _login();
      if (!mounted || repo.user == null) return;
    }
    widget.navigation.go(next);
  }

  void _routeChanged() {
    if (!widget.adminMode && page != 0 && repo.user == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_loginForPrivateRoute());
      });
    }
    if (page == 0) savedCategory = category;
    if (page == 1) savedOrderFilter = filter;
    final index = shopCategories.indexOf(category);
    if (categoryTabs.index != index) categoryTabs.index = index;
    if (categoryPages.hasClients && categoryPages.page?.round() != index) {
      categoryPages.jumpToPage(index);
    }
    if (mounted) setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          categoryPages.hasClients &&
          categoryPages.page?.round() != index) {
        categoryPages.jumpToPage(index);
      }
    });
  }

  Widget _routeLink(
    ShopLocation target,
    Widget Function(VoidCallback) builder,
  ) {
    void go() {
      final keyboard = HardwareKeyboard.instance;
      if (kIsWeb &&
          (keyboard.isMetaPressed ||
              keyboard.isControlPressed ||
              keyboard.isShiftPressed ||
              keyboard.isAltPressed)) {
        return;
      }
      _navigate(target);
    }

    final label = target.productId != null || target.orderId != null
        ? t('details')
        : target.page == 1
        ? t(widget.adminMode ? 'orders' : 'myOrders')
        : target.page == 2
        ? widget.adminMode
              ? t('banners')
              : repo.user == null
              ? t('mine')
              : displayName
        : t(widget.adminMode ? 'products' : 'home');
    return browserShopLink(
      route: target.uri(admin: widget.adminMode),
      label: label,
      child: builder(go),
      onNavigate: go,
      focusColor: Theme.of(context).colorScheme.primary,
    );
  }

  bool busy = false;
  bool adminChecking = false;
  @override
  void initState() {
    super.initState();
    repo.addListener(_changed);
    savedCategory = category;
    savedOrderFilter = filter;
    widget.navigation.addListener(_routeChanged);
    if (widget.adminMode) unawaited(_enterAdmin());
    if (!widget.adminMode && page != 0 && repo.user == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_loginForPrivateRoute());
      });
    }
  }

  bool privateRoutePrompt = false;
  Future<void> _loginForPrivateRoute() async {
    if (privateRoutePrompt || loginOpen) return;
    privateRoutePrompt = true;
    try {
      await _login();
      if (mounted && repo.user == null) {
        widget.navigation.go(const ShopLocation());
      }
    } finally {
      privateRoutePrompt = false;
    }
  }

  Future<void> _enterAdmin() async {
    if (adminChecking || repo.admin) return;
    setState(() => adminChecking = true);
    try {
      await repo.bootstrapAdmin();
    } catch (e) {
      _tell(e);
    } finally {
      if (mounted) setState(() => adminChecking = false);
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    repo.removeListener(_changed);
    widget.navigation.removeListener(_routeChanged);
    categoryTabs.dispose();
    categoryPages.dispose();
    super.dispose();
  }

  void _tell(Object e) {
    if (!mounted) return;
    setState(() => operationError = t(e.toString()));
  }

  Widget _error(
    String text, {
    VoidCallback? onDismiss,
    VoidCallback? onRetry,
  }) => Padding(
    key: const ValueKey('shop-persistent-error'),
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Material(
      color: Theme.of(context).colorScheme.errorContainer,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.error_outline,
              color: Theme.of(context).colorScheme.onErrorContainer,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Semantics(
                liveRegion: true,
                child: Text(
                  text,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
                ),
              ),
            ),
            if (onRetry != null)
              TextButton(onPressed: onRetry, child: Text(t('retry'))),
            if (onDismiss != null)
              IconButton(
                onPressed: onDismiss,
                tooltip: t('dismiss'),
                icon: const Icon(Icons.close),
              ),
          ],
        ),
      ),
    ),
  );

  Future<void> _run(Future<void> Function() task) async {
    if (busy) return;
    setState(() {
      busy = true;
      operationError = null;
    });
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
        final webWide = kIsWeb && c.maxWidth >= 1100;
        return Scaffold(
          appBar: AppBar(
            toolbarHeight: webWide ? 80 : 64,
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (webWide) ...[
                  SizedBox(
                    width: 38,
                    height: 38,
                    child: ShopMedia(
                      path: '',
                      baseUrl: repo.baseUrl,
                      packaged: widget.adminMode,
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Flexible(
                  child: Semantics(
                    label: t(widget.adminMode ? 'admin' : 'shop'),
                    child: Text(
                      webWide ? t(widget.adminMode ? 'admin' : 'shop') : '知序',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              if (webWide && !widget.adminMode) ...[
                _routeLink(
                  const ShopLocation(),
                  (go) => TextButton.icon(
                    onPressed: go,
                    icon: const Icon(Icons.storefront_outlined),
                    label: Text(t('home')),
                  ),
                ),
                if (repo.user != null)
                  _routeLink(
                    const ShopLocation(page: 1),
                    (go) => TextButton.icon(
                      onPressed: go,
                      icon: const Icon(Icons.receipt_long_outlined),
                      label: Text(t('myOrders')),
                    ),
                  ),
                if (repo.user != null)
                  _routeLink(
                    const ShopLocation(page: 2),
                    (go) => TextButton(
                      onPressed: go,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _avatar(26),
                          const SizedBox(width: 8),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 140),
                            child: Text(
                              repo.user == null ? t('mine') : displayName,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
              if (repo.user == null || widget.adminMode)
                IconButton(
                  onPressed: () => _settings(),
                  tooltip: t('settings'),
                  icon: const Icon(Icons.settings_outlined),
                ),
              if (repo.user != null && (!webWide || widget.adminMode))
                TextButton(
                  onPressed: widget.adminMode
                      ? null
                      : () => _selectDestination(2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _avatar(26),
                      const SizedBox(width: 8),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 110),
                        child: Text(
                          displayName,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              if (repo.user == null)
                FilledButton(
                  key: const ValueKey('shop-login-entry'),
                  onPressed: () => _login(),
                  child: Text(t('loginRegister')),
                ),
              const SizedBox(width: 12),
            ],
          ),
          body: SafeArea(
            child: Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 10,
                  ),
                  color: Theme.of(context).colorScheme.secondaryContainer,
                  child: Text(
                    repo.demo
                        ? t('offline')
                        : '${repo.shopConfig['demo_mode'] == true ? 'Demo · ' : ''}${t('online')}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSecondaryContainer,
                    ),
                  ),
                ),
                if (busy) const LinearProgressIndicator(minHeight: 2),
                if (operationError != null || repo.refreshError != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _error(
                      operationError ?? t('updateFailed'),
                      onRetry: () => _run(repo.refresh),
                      onDismiss: () => setState(() {
                        operationError = null;
                        repo.refreshError = null;
                      }),
                    ),
                  ),
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
                  child: Row(
                    children: [
                      if (webWide && widget.adminMode && repo.admin)
                        _merchantNavigation(),
                      Expanded(
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 1200),
                            child: widget.adminMode && !repo.admin
                                ? _adminGate()
                                : page == 0
                                ? _catalogue()
                                : page == 1
                                ? _orders()
                                : widget.adminMode
                                ? _banners()
                                : repo.user == null
                                ? _privateGate()
                                : _profile(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          bottomNavigationBar: webWide || (widget.adminMode && !repo.admin)
              ? null
              : NavigationBar(
                  selectedIndex: page,
                  onDestinationSelected: _selectDestination,
                  destinations: [
                    NavigationDestination(
                      icon: const Icon(Icons.storefront_outlined),
                      selectedIcon: const Icon(Icons.storefront),
                      label: t(widget.adminMode ? 'products' : 'home'),
                    ),
                    NavigationDestination(
                      icon: const Icon(Icons.receipt_long_outlined),
                      selectedIcon: const Icon(Icons.receipt_long),
                      label: t(widget.adminMode ? 'orders' : 'myOrders'),
                    ),
                    if (widget.adminMode)
                      NavigationDestination(
                        icon: const Icon(Icons.view_carousel_outlined),
                        selectedIcon: const Icon(Icons.view_carousel),
                        label: t('banners'),
                      )
                    else
                      NavigationDestination(
                        icon: _avatar(26),
                        selectedIcon: _avatar(28),
                        label: repo.user == null ? t('mine') : displayName,
                      ),
                  ],
                ),
        );
      },
    ),
  );
  Widget _adminGate() => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.lock_outline, size: 52),
          const SizedBox(height: 20),
          Text(t('adminSignIn'), style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 20),
          if (adminChecking)
            const CircularProgressIndicator()
          else
            FilledButton(onPressed: _login, child: Text(t('loginRegister'))),
        ],
      ),
    ),
  );
  Widget _privateGate() => Center(
    child: FilledButton(
      onPressed: _loginForPrivateRoute,
      child: Text(t('loginRegister')),
    ),
  );
  Widget _merchantNavigation() => Container(
    width: 224,
    decoration: BoxDecoration(
      border: Border(
        right: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
    ),
    child: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SizedBox(height: 12),
        Text(t('merchant'), style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 20),
        for (final entry in [
          (0, 'products', Icons.inventory_2_outlined),
          (1, 'orders', Icons.receipt_long_outlined),
          (2, 'banners', Icons.view_carousel_outlined),
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _routeLink(
              ShopLocation(page: entry.$1),
              (go) => ListTile(
                selected: page == entry.$1,
                selectedTileColor: Theme.of(context)
                    .colorScheme
                    .secondaryContainer,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                leading: Icon(entry.$3),
                title: Text(t(entry.$2)),
                onTap: go,
              ),
            ),
          ),
      ],
    ),
  );
  Widget _empty(String key) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.inbox_outlined,
            size: 48,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text(t(key), style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          Text(t('emptyHint'), textAlign: TextAlign.center),
          const SizedBox(height: 20),
          OutlinedButton(
            onPressed: busy ? null : () => _run(repo.refresh),
            child: Text(t('retry')),
          ),
        ],
      ),
    ),
  );
  Widget _avatar(double size) {
    if (repo.user?['avatar_color'] is int &&
        '${repo.user?['avatar_url'] ?? ''}'.isEmpty) {
      return CircleAvatar(
        radius: size / 2,
        backgroundColor: Color(
          0xff000000 | (repo.user!['avatar_color'] as int),
        ),
        child: Text(
          String.fromCharCode(displayName.runes.first),
          style: TextStyle(color: Colors.white, fontSize: size * .45),
        ),
      );
    }
    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: ShopMedia(
          path: '${repo.user?['avatar_url'] ?? ''}',
          baseUrl: repo.baseUrl,
          packaged: widget.adminMode,
          brandSize: size,
          fit: BoxFit.cover,
        ),
      ),
    );
  }

  Widget _image(Json p, {double height = 160}) => Container(
    height: height,
    width: double.infinity,
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(12),
    ),
    child: ShopMedia(
      path: '${p['image'] ?? ''}',
      baseUrl: repo.baseUrl,
      packaged: widget.adminMode,
      brandSize: height < 120 ? 48 : 76,
    ),
  );
  Future<void> _openLink(String target) async {
    final uri = Uri.tryParse(target);
    if (uri == null ||
        !['https', 'http'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        RegExp(r'[\x00-\x20]').hasMatch(target)) {
      _tell(t('invalidLink'));
      return;
    }
    try {
      if (!await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
        webOnlyWindowName: '_blank',
      )) {
        _tell(t('launchFailed'));
      }
    } catch (_) {
      _tell(t('launchFailed'));
    }
  }

  Widget _catalogue() {
    final selected = repo.products
        .where((p) => p['id'] == productId)
        .firstOrNull;
    if (selected != null) return _detail(selected);
    if (productId != null) {
      return Column(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => _navigate(ShopLocation(category: category)),
              child: Text(t('back')),
            ),
          ),
          Expanded(child: _empty('resourceUnavailable')),
        ],
      );
    }
    return NestedScrollView(
      key: const PageStorageKey('shop-catalogue'),
      headerSliverBuilder: (context, inner) => [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!widget.adminMode && repo.visibleBanners.isNotEmpty)
                  ShopCarousel(
                    banners: repo.visibleBanners,
                    t: t,
                    baseUrl: repo.baseUrl,
                    onOpen: _openLink,
                  ),
                const SizedBox(height: 24),
                Text(
                  t(widget.adminMode ? 'products' : 'hero'),
                  style: Theme.of(context).textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                if (!widget.adminMode) ...[
                  const SizedBox(height: 8),
                  Text(
                    t('intro'),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                if (widget.adminMode)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: FilledButton.icon(
                      onPressed: busy
                          ? null
                          : () async {
                              if (!repo.admin) await _login();
                              if (repo.admin) await _edit();
                            },
                      icon: const Icon(Icons.add),
                      label: Text(t('newProduct')),
                    ),
                  ),
              ],
            ),
          ),
        ),
        SliverPersistentHeader(
          pinned: true,
          delegate: _CategoryHeader(
            TabBar(
              controller: categoryTabs,
              isScrollable: true,
              tabAlignment: TabAlignment.center,
              onTap: (i) =>
                  _navigate(ShopLocation(category: shopCategories[i])),
              tabs: [
                for (final key in ['graduation', 'journal', 'editing'])
                  Tab(text: t(key)),
              ],
            ),
          ),
        ),
      ],
      body: PageView(
        controller: categoryPages,
        key: const PageStorageKey('shop-category-pages'),
        onPageChanged: (i) {
          if (page != 0 || productId != null) return;
          categoryTabs.animateTo(i);
          _navigate(ShopLocation(category: shopCategories[i]));
        },
        children: [
          for (final key in ['graduation', 'journal', 'editing'])
            _categoryList(key),
        ],
      ),
    );
  }

  Widget _categoryList(String key) {
    final list = repo.products
        .where(
          (p) =>
              (widget.adminMode || p['active'] == true) &&
              p['category_id'] == key,
        )
        .toList();
    return ListView(
      key: PageStorageKey('category-$key'),
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
      children: [
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
              final width = (c.maxWidth - (columns - 1) * 20) / columns;
              return Wrap(
                spacing: 20,
                runSpacing: 16,
                children: [
                  for (final p in list)
                    SizedBox(
                      width: width,
                      child: _productCard(p, key, columns == 1),
                    ),
                ],
              );
            },
          ),
      ],
    );
  }

  Widget _productCard(Json p, String categoryKey, bool compact) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${t('${p['category_id']}')} · ${t('${p['kind']}')}',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        Text('${p['name']}', style: theme.textTheme.titleMedium),
        const SizedBox(height: 6),
        Text(
          '${p['summary'] ?? ''}',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          money(p['price_minor']),
          style: theme.textTheme.titleLarge?.copyWith(
            color: colors.primary,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (p['is_demo'] == true)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(t('demoGoods'), style: theme.textTheme.bodySmall),
          ),
        if (p['in_stock'] != true || p['active'] != true)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              t(p['active'] != true ? 'inactive' : 'outOfStock'),
              style: TextStyle(color: colors.error),
            ),
          ),
        const SizedBox(height: 8),
        _routeLink(
          ShopLocation(productId: p['id'], category: categoryKey),
          (go) => TextButton.icon(
            onPressed: go,
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(48, 48),
              alignment: Alignment.centerLeft,
            ),
            iconAlignment: IconAlignment.end,
            icon: const Icon(Icons.arrow_forward_rounded, size: 18),
            label: Text(t('details')),
          ),
        ),
      ],
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: compact
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 76, child: _image(p, height: 96)),
                  const SizedBox(width: 18),
                  Expanded(child: content),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _image(p, height: 112),
                  const SizedBox(height: 20),
                  content,
                ],
              ),
      ),
    );
  }

  Widget _detail(Json p) => ListView(
    key: PageStorageKey('shop-product-${p['id']}'),
    padding: const EdgeInsets.all(24),
    children: [
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          onPressed: () => _navigate(ShopLocation(category: category)),
          child: Text(t('back')),
        ),
      ),
      const SizedBox(height: 12),
      LayoutBuilder(
        builder: (context, constraints) {
          final description = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${p['name']}',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
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
              _productAction(p),
              const SizedBox(height: 20),
            ],
          );
          if (constraints.maxWidth < 800) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _image(p, height: 220),
                const SizedBox(height: 24),
                description,
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 4, child: _image(p, height: 280)),
              const SizedBox(width: 36),
              Expanded(flex: 6, child: description),
            ],
          );
        },
      ),
      Text('${p['description'] ?? ''}'),
      for (final section in objects(p['sections']))
        Container(
          margin: const EdgeInsets.only(top: 28),
          padding: const EdgeInsets.only(top: 24),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${section['title']}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              Text(
                '${section['body']}',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ],
          ),
        ),
      const SizedBox(height: 24),
    ],
  );
  Widget _productAction(Json p) => widget.adminMode
      ? FilledButton(
          onPressed: repo.admin && !busy ? () => _edit(p) : null,
          child: Text(t('edit')),
        )
      : FilledButton(
          onPressed: busy || p['active'] != true || p['in_stock'] != true
              ? null
              : () async {
                  if (repo.user == null) await _login();
                  if (!mounted || repo.user == null) return;
                  Json? result;
                  final fields = await _requirements(
                    onSave: (fields) async {
                      result = await repo.buy(p, fields);
                    },
                  );
                  if (!mounted || fields == null || result == null) return;
                  final order = object(result!['order']);
                  _navigate(ShopLocation(page: 1, orderId: order['id']));
                  await _checkout(order);
                },
          child: Text(t(p['in_stock'] == true ? 'buy' : 'outOfStock')),
        );

  Widget _profile() {
    final colors = Theme.of(context).colorScheme;
    return ListView(
      key: const PageStorageKey('shop-profile'),
      padding: const EdgeInsets.all(24),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Row(
              children: [
                _avatar(72),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        repo.user == null ? t('signInFirst') : displayName,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        t('profileHint'),
                        style: TextStyle(color: colors.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text(t('myOrders'), style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, c) => Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final entry in [
                ('pending_payment', Icons.account_balance_wallet_outlined),
                ('pending_completion', Icons.hourglass_empty_rounded),
                ('completed', Icons.task_alt_rounded),
                ('pending_review', Icons.rate_review_outlined),
              ])
                SizedBox(
                  width:
                      (c.maxWidth - (c.maxWidth < 600 ? 12 : 36)) /
                      (c.maxWidth < 600 ? 2 : 4),
                  child: Card(
                    child: InkWell(
                      key: ValueKey('profile-${entry.$1}'),
                      borderRadius: BorderRadius.circular(22),
                      onTap: () =>
                          _navigate(ShopLocation(page: 1, status: entry.$1)),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: 22,
                          horizontal: 12,
                        ),
                        child: Column(
                          children: [
                            Icon(entry.$2, color: colors.primary),
                            const SizedBox(height: 10),
                            Text(
                              '${repo.orders.where((o) => o['status'] == entry.$1).length}',
                              style: Theme.of(context).textTheme.headlineSmall,
                            ),
                            Text(t(entry.$1), textAlign: TextAlign.center),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        if (repo.user == null)
          FilledButton.icon(
            onPressed: () => _login(),
            icon: const Icon(Icons.account_circle_outlined),
            label: Text(t('login')),
          ),
        const SizedBox(height: 12),
        if (repo.user != null)
          IconButton(
            onPressed: () => _settings(),
            tooltip: t('settings'),
            icon: const Icon(Icons.settings_outlined),
          ),
      ],
    );
  }

  Widget _banners() {
    if (!repo.admin) {
      return Center(
        child: FilledButton(onPressed: _login, child: Text(t('signInFirst'))),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 16,
          runSpacing: 16,
          children: [
            Text(
              t('banners'),
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            FilledButton.icon(
              onPressed: busy ? null : () => _editBanner(),
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: Text(t('newBanner')),
            ),
          ],
        ),
        const SizedBox(height: 20),
        if (repo.banners.isEmpty) _empty('emptyBanners'),
        for (final banner in repo.banners)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _image(banner, height: 140),
                    const SizedBox(height: 12),
                    Text(
                      banner['title_key'] is String
                          ? t(banner['title_key'])
                          : '${banner['title']}',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Text(
                      '${t('sortOrder')}: ${banner['sort_order']} · ${t(banner['active'] == true ? 'active' : 'inactive')}',
                    ),
                    if ('${banner['target_url'] ?? ''}'.isNotEmpty)
                      Text('${banner['target_url']}'),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: busy ? null : () => _editBanner(banner),
                      icon: const Icon(Icons.edit_outlined),
                      label: Text(t('editBanner')),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _editBanner([Json? original]) async {
    String? error;
    var title = original?['title_key'] is String
            ? t(original!['title_key'])
            : '${original?['title'] ?? ''}',
        image = '${original?['image'] ?? ''}',
        target = '${original?['target_url'] ?? ''}',
        sort = '${original?['sort_order'] ?? repo.banners.length}',
        active = original?['active'] ?? true,
        sending = false;
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: Text(t(original == null ? 'newBanner' : 'editBanner')),
          content: SizedBox(
            width: 620,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (error != null) _error(error!),
                  if (error != null && repo.user == null)
                    TextButton(
                      onPressed: () async {
                        await _login();
                        if (context.mounted) setDialog(() {});
                      },
                      child: Text(t('login')),
                    ),
                  _image({'image': image}, height: 140),
                  const SizedBox(height: 16),
                  TextFormField(
                    initialValue: title,
                    decoration: InputDecoration(labelText: t('bannerTitle')),
                    onChanged: (v) => title = v,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    key: ValueKey(
                      image.startsWith('data:') ? 'embedded' : 'url',
                    ),
                    initialValue: image.startsWith('data:') ? '' : image,
                    decoration: InputDecoration(labelText: t('image')),
                    onChanged: (v) => image = v,
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: sending
                        ? null
                        : () async {
                            try {
                              final file = await FilePicker.pickFile(
                                type: FileType.custom,
                                allowedExtensions: [
                                  'png',
                                  'jpg',
                                  'jpeg',
                                  'webp',
                                ],
                              );
                              if (file == null) return;
                              final bytes = await file.readAsBytes();
                              final extension = (file.extension ?? '')
                                  .toLowerCase();
                              if (bytes.isEmpty ||
                                  bytes.length > 2 * 1024 * 1024 ||
                                  ![
                                    'png',
                                    'jpg',
                                    'jpeg',
                                    'webp',
                                  ].contains(extension)) {
                                setDialog(() => error = t('imageLimit'));
                                return;
                              }
                              if (context.mounted) {
                                setDialog(
                                  () => image =
                                      'data:image/${extension == 'jpg' ? 'jpeg' : extension};base64,${base64Encode(bytes)}',
                                );
                              }
                            } catch (e) {
                              if (context.mounted) {
                                setDialog(() => error = t(e.toString()));
                              }
                            }
                          },
                    icon: const Icon(Icons.upload_outlined),
                    label: Text(t('uploadImage')),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    initialValue: target,
                    decoration: InputDecoration(labelText: t('targetUrl')),
                    onChanged: (v) => target = v,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    initialValue: sort,
                    keyboardType: const TextInputType.numberWithOptions(
                      signed: true,
                    ),
                    decoration: InputDecoration(labelText: t('sortOrder')),
                    onChanged: (v) => sort = v,
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(t('active')),
                    value: active,
                    onChanged: (v) => setDialog(() => active = v),
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
                      final uri = Uri.tryParse(target);
                      if (title.trim().isEmpty ||
                          image.trim().isEmpty ||
                          int.tryParse(sort) == null) {
                        setDialog(() => error = t('required'));
                        return;
                      }
                      if (target.isNotEmpty &&
                          (uri == null ||
                              !['http', 'https'].contains(uri.scheme) ||
                              uri.host.isEmpty ||
                              uri.userInfo.isNotEmpty ||
                              RegExp(r'[\x00-\x20]').hasMatch(target))) {
                        setDialog(() => error = t('invalidLink'));
                        return;
                      }
                      setDialog(() {
                        sending = true;
                        error = null;
                      });
                      try {
                        await repo.saveBanner(
                          {
                            'title': title.trim(),
                            'image': image.trim(),
                            'target_url': target.trim(),
                            'active': active,
                            'sort_order': int.parse(sort),
                          },
                          id: original?['id'],
                          version: original?['version'],
                        );
                        if (context.mounted) Navigator.pop(context);
                      } catch (e) {
                        if (context.mounted) {
                          setDialog(() => error = t(e.toString()));
                        }
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

  Future<Json?> _requirements({
    Json? order,
    required Future<void> Function(Json) onSave,
  }) async {
    var sending = false;
    String? error;
    final fields = {
      for (final key in ['requirements', 'contact', 'delivery_requirements'])
        key: '${order?[key] ?? ''}',
    };
    return showDialog<Json>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: Text(t(order == null ? 'requirements' : 'editRequirements')),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (error != null) _error(error!),
                  Text(t('beforeAccepted')),
                  const SizedBox(height: 18),
                  for (final key in fields.keys)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: TextFormField(
                        initialValue: fields[key],
                        decoration: InputDecoration(
                          labelText: t(
                            key == 'delivery_requirements'
                                ? 'deliveryRequirements'
                                : key,
                          ),
                        ),
                        minLines: key == 'contact' ? 1 : 3,
                        maxLines: key == 'contact' ? 2 : 7,
                        onChanged: (v) => fields[key] = v,
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
                      setDialog(() {
                        sending = true;
                        error = null;
                      });
                      try {
                        await onSave(fields);
                        if (context.mounted) Navigator.pop(context, fields);
                      } catch (e) {
                        if (context.mounted) {
                          setDialog(() {
                            sending = false;
                            error = t(e.toString());
                          });
                        }
                      }
                    },
              child: Text(t('save')),
            ),
          ],
        ),
      ),
    );
  }

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
        .where(
          (o) => location.orderId != null
              ? o['id'] == location.orderId
              : filter == 'all' || o['status'] == filter,
        )
        .toList();
    return ListView(
      key: PageStorageKey('shop-orders-$filter-${location.orderId ?? 'list'}'),
      padding: const EdgeInsets.all(24),
      children: [
        if (location.orderId != null)
          Align(
            alignment: Alignment.centerLeft,
            child: _routeLink(
              ShopLocation(page: 1, status: filter),
              (go) => TextButton(onPressed: go, child: Text(t('back'))),
            ),
          ),
        Text(t('orders'), style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 20),
        if (location.orderId == null)
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
                  onSelected: (_) =>
                      _navigate(ShopLocation(page: 1, status: key)),
                ),
            ],
          ),
        const SizedBox(height: 20),
        if (list.isEmpty)
          _empty(
            location.orderId == null ? 'emptyOrders' : 'resourceUnavailable',
          ),
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
              for (final key in [
                'requirements',
                'contact',
                'delivery_requirements',
              ])
                if ('${order[key] ?? ''}'.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                      '${t(key == 'delivery_requirements' ? 'deliveryRequirements' : key)}: ${order[key]}',
                    ),
                  ),
              if (!repo.admin &&
                  !shopOrderEditable(order) &&
                  '${order['accepted_at'] ?? ''}'.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(t('orderLocked')),
                ),
              if (order['review'] is Map)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    '${t('rating')}: ${order['review']['rating']}/5\n${order['review']['text']}',
                  ),
                ),
              const SizedBox(height: 12),
              if (location.orderId == null)
                _routeLink(
                  ShopLocation(page: 1, orderId: order['id'], status: filter),
                  (go) => TextButton(onPressed: go, child: Text(t('details'))),
                ),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  if (!repo.admin && shopOrderEditable(order))
                    OutlinedButton.icon(
                      onPressed: busy
                          ? null
                          : () async {
                              await _requirements(
                                order: order,
                                onSave: (fields) async {
                                  await repo.action(order, 'edit', fields);
                                },
                              );
                            },
                      icon: const Icon(Icons.edit_note),
                      label: Text(t('editRequirements')),
                    ),
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
                      child: Text(t('acceptOrder')),
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
    String? error;
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
                  if (error != null) _error(error!),
                  if (error != null && repo.user == null)
                    TextButton(
                      onPressed: () async {
                        await _login();
                        if (context.mounted) setDialog(() {});
                      },
                      child: Text(t('login')),
                    ),
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
                      setDialog(() {
                        sending = true;
                        error = null;
                      });
                      try {
                        await repo.action(order, 'pay', {'channel': channel});
                        if (context.mounted) Navigator.pop(context);
                      } catch (e) {
                        if (context.mounted) {
                          setDialog(() => error = t(e.toString()));
                        }
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

  bool loginOpen = false;
  Future<void> _login() async {
    if (loginOpen) return;
    loginOpen = true;
    try {
      await repo.loadConfiguration();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) =>
            ShopAuthDialog(repo: repo, t: t, admin: widget.adminMode),
      );
      if (repo.user != null) await repo.refresh();
    } finally {
      loginOpen = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _textAction(Json order, String action) async {
    String? error;
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
                  if (error != null) _error(error!),
                  if (error != null && repo.user == null)
                    TextButton(
                      onPressed: () async {
                        await _login();
                        if (context.mounted) setDialog(() {});
                      },
                      child: Text(t('login')),
                    ),
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
                        setDialog(() => error = t('required'));
                        return;
                      }
                      setDialog(() {
                        sending = true;
                        error = null;
                      });
                      try {
                        await repo.action(order, action, {
                          'text': text.trim(),
                          if (action == 'review') 'rating': rating,
                        });
                        if (context.mounted) Navigator.pop(context);
                      } catch (e) {
                        if (context.mounted) {
                          setDialog(() => error = t(e.toString()));
                        }
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
    String? error;
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
                  if (error != null) _error(error!),
                  if (error != null && repo.user == null)
                    TextButton(
                      onPressed: () async {
                        await _login();
                        if (context.mounted) setDialog(() {});
                      },
                      child: Text(t('login')),
                    ),
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
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: t('productCategory'),
                    ),
                    items: [
                      for (final key in ['graduation', 'journal', 'editing'])
                        DropdownMenuItem(value: key, child: Text(t(key))),
                    ],
                    onChanged: (v) => product['category_id'] = v,
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: product['kind'],
                    isExpanded: true,
                    decoration: InputDecoration(labelText: t('productKind')),
                    items: [
                      for (final key in ['course', 'service'])
                        DropdownMenuItem(value: key, child: Text(t(key))),
                    ],
                    onChanged: (v) => product['kind'] = v,
                  ),
                  const SizedBox(height: 28),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      t('sections'),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
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
                        setDialog(() => error = t('required'));
                        return;
                      }
                      product['price_minor'] = parseShopPrice(price);
                      product['sections'] = sections;
                      product.remove('id');
                      product.remove('version');
                      setDialog(() {
                        sending = true;
                        error = null;
                      });
                      try {
                        await repo.saveProduct(
                          product,
                          id: original?['id'],
                          version: original?['version'],
                        );
                        if (context.mounted) Navigator.pop(context);
                      } catch (e) {
                        if (context.mounted) {
                          setDialog(() => error = t(e.toString()));
                        }
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
    String? error;
    var saving = false;
    var username = displayName;
    String? avatar;
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
                  if (error != null) _error(error!),
                  if (repo.user != null) ...[
                    Center(
                      child: SizedBox(
                        width: 72,
                        height: 72,
                        child: ClipOval(
                          child: ShopMedia(
                            path: avatar ?? '${repo.user?['avatar_url'] ?? ''}',
                            baseUrl: repo.baseUrl,
                            packaged: widget.adminMode,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      key: const ValueKey('profile-username'),
                      initialValue: username,
                      decoration: InputDecoration(labelText: t('username')),
                      onChanged: (value) => username = value,
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.upload_outlined),
                      label: Text(t('uploadAvatar')),
                      onPressed: saving
                          ? null
                          : () async {
                              try {
                                final file = await FilePicker.pickFile(
                                  type: FileType.custom,
                                  allowedExtensions: [
                                    'png',
                                    'jpg',
                                    'jpeg',
                                    'webp',
                                  ],
                                );
                                if (file == null) return;
                                final bytes = await file.readAsBytes();
                                final extension = (file.extension ?? '')
                                    .toLowerCase();
                                if (bytes.isEmpty ||
                                    bytes.length > 2 * 1024 * 1024 ||
                                    ![
                                      'png',
                                      'jpg',
                                      'jpeg',
                                      'webp',
                                    ].contains(extension)) {
                                  throw ApiFailure('imageLimit');
                                }
                                final uploaded =
                                    'data:image/${extension == 'jpg' ? 'jpeg' : extension};base64,${base64Encode(bytes)}';
                                if (!context.mounted) return;
                                setDialog(() => saving = true);
                                await repo.updateProfile(
                                  username: username,
                                  avatar: uploaded,
                                );
                                if (context.mounted) {
                                  setDialog(() {
                                    avatar = uploaded;
                                    error = null;
                                  });
                                }
                              } catch (e) {
                                if (context.mounted) {
                                  setDialog(() => error = t(e.toString()));
                                }
                              } finally {
                                if (context.mounted) {
                                  setDialog(() => saving = false);
                                }
                              }
                            },
                    ),
                    Text(t('avatarHint')),
                    const SizedBox(height: 16),
                  ],
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
                  if (repo.demoMode) ...[
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
                  ],
                  const SizedBox(height: 16),
                  if (repo.user != null)
                    TextButton(
                      onPressed: () {
                        Navigator.pop(context);
                        _login();
                      },
                      child: Text(t('switchAccount')),
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
              onPressed: saving ? null : () => Navigator.pop(context),
              child: Text(t('cancel')),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      setDialog(() => saving = true);
                      try {
                        final parsed = int.tryParse(timeout);
                        if (parsed == null) throw ApiFailure('required');
                        if (repo.user != null && username != displayName) {
                          await repo.updateProfile(username: username);
                        }
                        if (repo.demoMode &&
                            (url != repo.baseUrl || parsed != repo.timeoutMs)) {
                          repo.configure(url, parsed);
                          final prefs = await SharedPreferences.getInstance();
                          await prefs.setString('shop-api', url);
                          await prefs.setInt('shop-timeout', parsed);
                        }
                        await widget.onPreferences(language, mode);
                        if (context.mounted) Navigator.pop(context);
                        await repo.refresh();
                      } catch (e) {
                        if (context.mounted) {
                          setDialog(() => error = t(e.toString()));
                        }
                      } finally {
                        if (context.mounted) setDialog(() => saving = false);
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

class _CategoryHeader extends SliverPersistentHeaderDelegate {
  _CategoryHeader(this.bar);
  final TabBar bar;
  @override
  double get minExtent => 52;
  @override
  double get maxExtent => 52;
  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) => Material(
    color: Theme.of(context).colorScheme.surface,
    child: SizedBox(height: 52, child: bar),
  );
  @override
  bool shouldRebuild(covariant _CategoryHeader old) => true;
}
