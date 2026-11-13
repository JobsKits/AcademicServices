import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../Data/models.dart';
import '../Data/repository.dart' show ApiFailure, WorkspaceRepository;

final shopSamples = <Json>[
  for (final entry in [
    ['graduation', 'outline', '论文提纲', 'course', '从选题到结构的论文提纲辅导', '49800'],
    ['graduation', 'proposal', '开题指导报告课', 'course', '开题思路与研究方案课程', '1'],
    ['graduation', 'mentoring', '毕业论文一对一', 'service', '针对现有写作材料的一对一辅导', '5000'],
    ['journal', 'submission', '审测投稿', 'service', '期刊咨询与投稿流程服务', '9900'],
    ['journal', 'mentoring', '普刊论文一对一', 'service', '稿件结构与表达的一对一辅导', '20000'],
    ['journal', 'assessment', '论文专业测评', 'service', '稿件问题梳理与专业测评', '60000'],
    ['journal', 'training', '普刊训练营', 'course', '普刊写作与投稿知识课程', '219900'],
    ['editing', 'translation', '学术翻译', 'service', '基于本人稿件的学术语言翻译', '19900'],
    ['editing', 'polish', '学术润色', 'service', '学术语言表达与格式润色', '15900'],
  ])
    {
      'id': 'demo-${entry[0]}-${entry[1]}',
      'category_id': entry[0],
      'name': entry[2],
      'kind': entry[3],
      'summary': entry[4],
      'description': entry[4],
      'price_minor': int.parse(entry[5]),
      'currency': 'CNY',
      'image': '',
      'active': true,
      'in_stock': true,
      'version': 1,
      'is_demo': true,
      'sections': [
        {'title': '服务内容', 'body': entry[4]},
        {'title': '交付说明', 'body': '课程及服务均为虚拟商品，无需物流。此为本地演示内容与价格，实际服务以经营方配置为准。'},
      ],
    },
];

List<Json> defaultShopBanners() => [
  for (final entry in [
    ['graduation', 'bannerGuide'],
    ['journal', 'bannerService'],
    ['editing', 'bannerProgress'],
  ])
    {
      'id': 'seed-${entry[0]}',
      'title_key': entry[1],
      'title': '',
      'image': 'Assets/Banners/${entry[0]}.png',
      'target_url': '',
      'active': true,
      'sort_order': entry[0] == 'graduation'
          ? 0
          : entry[0] == 'journal'
          ? 1
          : 2,
      'version': 1,
    },
];

bool shopOrderEditable(Json order) => order['editable'] is bool
    ? order['editable'] == true
    : ['pending_payment', 'pending_completion'].contains(order['status']) &&
          order['fulfillment_status'] == 'pending' &&
          '${order['accepted_at'] ?? ''}'.isEmpty;

class ShopPending {
  ShopPending(this.path, this.method, this.body, this.key);
  final String path, method, key;
  final Json body;
}

class ShopRepository extends ChangeNotifier {
  ShopRepository({
    required String baseUrl,
    http.Client? client,
    this.timeoutMs = 2200,
    bool? demoMode,
  }) : baseUrl = WorkspaceRepository.normalizeUrl(baseUrl),
       _demoBuild = demoMode ?? const bool.fromEnvironment('DEMO_MODE'),
       _client = client ?? http.Client();
  final bool _demoBuild;
  bool? _serverDemo;
  bool get demoMode => _serverDemo ?? _demoBuild;
  final Map<String, Json> _demoAccounts = {};
  final Map<String, Json> _demoCodes = {};
  String baseUrl;
  int timeoutMs;
  final http.Client _client;
  String? token;
  String? refreshError;
  Json? user;
  bool demo = true, adminCatalogue = false;
  List<Json> products = shopSamples.map(copy).toList(), orders = [];
  List<Json> banners = defaultShopBanners();
  Json shopConfig = {'demo_mode': false};
  int _bannerSequence = 0, _configSequence = 0;
  bool _bannersKnown = false;
  List<Json> get demoCredentials =>
      shopConfig['demo_mode'] == true && shopConfig['demo_credentials'] is List
      ? objects(shopConfig['demo_credentials'])
      : [];
  List<Json> get visibleBanners {
    final list = banners.where((b) => b['active'] == true).toList()
      ..sort(
        (a, b) => (a['sort_order'] as int).compareTo(b['sort_order'] as int),
      );
    return list.isEmpty && !_bannersKnown ? defaultShopBanners() : list;
  }

  final List<Json> _demoOrders = [];
  ShopPending? pending;
  int _generation = 0, _sequence = 0;
  bool _writing = false;
  bool get admin => user?['role'] == 'admin';
  String _key() => List.generate(
    20,
    (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();

  Future<Json> _request(
    String method,
    String path, [
    Json? body,
    String? key,
  ]) async {
    final request = http.Request(method, Uri.parse('$baseUrl$path'))
      ..followRedirects = false;
    request.headers.addAll({
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
      'Idempotency-Key': ?key,
    });
    if (body != null) request.body = jsonEncode(body);
    final duration = Duration(
      milliseconds: path == '/auth/email-code'
          ? max(timeoutMs, 15000)
          : timeoutMs,
    );
    final response = await http.Response.fromStream(
      await _client.send(request).timeout(duration),
    ).timeout(duration);
    if (response.statusCode >= 300 && response.statusCode < 400) {
      throw ApiFailure('unexpected_response', status: 502);
    }
    Json decoded;
    try {
      decoded = object(jsonDecode(utf8.decode(response.bodyBytes)));
    } catch (_) {
      if (response.statusCode >= 400 && response.statusCode < 500) {
        throw ApiFailure(
          'HTTP ${response.statusCode}',
          status: response.statusCode,
        );
      }
      throw const FormatException('Invalid response');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (response.statusCode == 401) {
        logout();
      }
      throw ApiFailure(
        '${decoded['error']?['message'] ?? response.statusCode}',
        status: response.statusCode,
      );
    }
    return decoded;
  }

  bool _fallback(Object error) =>
      error is! ApiFailure || (error.status ?? 0) >= 500;
  List<Json> _products(dynamic value) {
    if (value is! List) throw const FormatException('Missing products');
    final result = objects(value);
    for (final p in result) {
      if (p['id'] is! String ||
          p['name'] is! String ||
          p['price_minor'] is! int ||
          p['version'] is! int ||
          p['active'] is! bool ||
          p['in_stock'] is! bool ||
          p['sections'] is! List) {
        throw const FormatException('Invalid product');
      }
    }
    return result;
  }

  List<Json> _orders(dynamic value) {
    if (value is! List) throw const FormatException('Missing orders');
    final result = objects(value);
    for (final order in result) {
      if (order['id'] is! String ||
          order['owner_id'] is! String ||
          order['version'] is! int ||
          order['amount_minor'] is! int ||
          order['product_snapshot'] is! Map ||
          ![
            'pending_payment',
            'pending_completion',
            'pending_review',
            'completed',
            'cancelled',
          ].contains(order['status'])) {
        throw const FormatException('Invalid order');
      }
      if (!admin && user != null && order['owner_id'] != user!['id']) {
        throw const FormatException('Order ownership mismatch');
      }
    }
    return result;
  }

  Future<void> refresh() async {
    final generation = _generation, sequence = ++_sequence;
    try {
      final result = await _request(
        'GET',
        admin && adminCatalogue ? '/admin/products' : '/products',
      );
      final nextProducts = _products(result['products']);
      final nextOrders = user == null
          ? <Json>[]
          : _orders((await _request('GET', '/shop-orders'))['orders']);
      if (generation != _generation || sequence != _sequence) return;
      products = nextProducts;
      orders = nextOrders;
      demo = false;
      refreshError = null;
    } catch (e) {
      if (generation != _generation || sequence != _sequence) return;
      if (!_fallback(e)) rethrow;
      refreshError = demo ? null : 'updateFailed';
    }
    notifyListeners();
    await Future.wait([loadConfiguration(), loadBanners()]);
  }

  Future<void> loadConfiguration() async {
    final generation = _generation, sequence = ++_configSequence;
    try {
      final result = await _request('GET', '/shop-config');
      if (result['demo_mode'] is! bool) {
        throw const FormatException('Invalid shop configuration');
      }
      if (generation != _generation || sequence != _configSequence) return;
      shopConfig = result['demo_mode'] == true
          ? result
          : {'demo_mode': false, 'payment_mode': result['payment_mode']};
      _serverDemo = result['demo_mode'] == true;
      if (!demoMode && token == null && user != null) logout();
    } catch (_) {
      if (generation != _generation || sequence != _configSequence) return;
    }
    notifyListeners();
  }

  Future<void> loadBanners() async {
    final generation = _generation, sequence = ++_bannerSequence;
    try {
      final result = await _request(
        'GET',
        admin ? '/admin/banners' : '/banners',
      );
      final next = _banners(result['banners']);
      if (generation != _generation || sequence != _bannerSequence) return;
      banners = next;
      _bannersKnown = true;
    } catch (_) {
      if (generation != _generation || sequence != _bannerSequence) return;
    }
    notifyListeners();
  }

  List<Json> _banners(dynamic value) {
    if (value is! List) throw const FormatException('Invalid banners');
    final rows = objects(value);
    if (rows.any(
      (b) =>
          b['id'] is! String ||
          b['title'] is! String ||
          b['image'] is! String ||
          b['active'] is! bool ||
          b['sort_order'] is! int ||
          b['version'] is! int,
    )) {
      throw const FormatException('Invalid banner');
    }
    return rows;
  }

  Future<void> login(
    String account,
    String password, {
    bool asAdmin = false,
  }) async {
    logout();
    final generation = _generation;
    try {
      final result = await _request('POST', '/auth/login', {
        'account': account,
        'password': password,
      });
      if (generation != _generation) return;
      final next = object(result['user']);
      if (result['token'] is! String ||
          next['id'] is! String ||
          !['admin', 'customer'].contains(next['role'])) {
        throw const FormatException('Invalid login');
      }
      user = next;
      if (asAdmin && next['role'] != 'admin') {
        user = null;
        throw ApiFailure('admin', status: 403);
      }
      user!['account'] = account;
      token = result['token'];
      demo = false;
    } catch (e) {
      if (generation != _generation) rethrow;
      if (!_fallback(e) || !demoMode) rethrow;
      final saved = _demoAccounts.values
          .where(
            (row) =>
                '${row['username']}'.toLowerCase() == account.toLowerCase() ||
                '${row['email']}'.toLowerCase() == account.toLowerCase(),
          )
          .firstOrNull;
      final credentials = demoCredentials
          .where(
            (row) => row['account'] == account && row['password'] == password,
          )
          .firstOrNull;
      if (saved != null && saved['password'] == password && !asAdmin) {
        user = {...saved}..remove('password');
      } else if ((account == 'admin' && password == '1234') ||
          (!asAdmin &&
              (credentials != null ||
                  account == 'customer' && password == 'demo-customer'))) {
        final role = account == 'admin' ? 'admin' : 'customer';
        user = {
          'id': 'demo-$role',
          'role': role,
          'name': account,
          'username': account,
          'avatar_url': '',
          'avatar_color': Random.secure().nextInt(0xffffff),
        };
      } else {
        throw ApiFailure('unauthorized', status: 401);
      }
      demo = true;
      orders = _demoOrders
          .where((o) => asAdmin || o['owner_id'] == user!['id'])
          .toList();
    }
    adminCatalogue = admin;
    await restorePending();
    await refresh();
  }

  Future<void> bootstrapAdmin() async {
    await loadConfiguration();
    if (demoMode && !admin) await login('admin', '1234', asAdmin: true);
  }

  Future<Json> requestEmailCode(String email, {required String purpose}) async {
    final generation = _generation, target = baseUrl;
    email = email.trim().toLowerCase();
    try {
      final result = await _request('POST', '/auth/email-code', {
        'email': email,
        'purpose': purpose,
      });
      _checkAuthContext(generation, target);
      if (result['demo_code'] is String && demoMode) {
        _rememberDemoCode(email, purpose, result['demo_code']);
      }
      return result;
    } catch (e) {
      _checkAuthContext(generation, target);
      if (!demoMode || !_fallback(e)) rethrow;
      if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email) ||
          !['register', 'reset_password'].contains(purpose)) {
        throw ApiFailure('invalidEmail');
      }
      final prior = _demoCodes['$email:$purpose'];
      if (prior != null &&
          DateTime.now().difference(prior['sent'] as DateTime).inSeconds < 60) {
        throw ApiFailure('rate_limit', status: 429);
      }
      final code = Random.secure().nextInt(1000000).toString().padLeft(6, '0');
      _rememberDemoCode(email, purpose, code);
      return {
        'ok': true,
        'delivery': 'demo',
        'demo_code': code,
        'retry_after': 60,
        'expires_in': 600,
      };
    }
  }

  void _checkAuthContext(int generation, String target) {
    if (generation != _generation || target != baseUrl) {
      throw ApiFailure('account', status: 409);
    }
  }

  void _rememberDemoCode(String email, String purpose, String code) {
    _demoCodes['$email:$purpose'] = {
      'code': code,
      'sent': DateTime.now(),
      'attempts': 0,
    };
  }

  void _verifyDemoCode(String email, String purpose, String code) {
    final entry = _demoCodes['$email:$purpose'];
    if (entry == null ||
        DateTime.now().difference(entry['sent'] as DateTime).inMinutes >= 10 ||
        entry['attempts'] >= 5 ||
        entry['code'] != code) {
      if (entry != null) entry['attempts'] = (entry['attempts'] as int) + 1;
      throw ApiFailure('invalidCode');
    }
  }

  void _validateAccountInput(
    String username,
    String password,
    String confirmPassword,
  ) {
    if (password != confirmPassword) throw ApiFailure('passwordMismatch');
    if (password.runes.length < 8 || utf8.encode(password).length > 512) {
      throw ApiFailure('passwordTooShort');
    }
    if (username.isNotEmpty &&
        (username.runes.length < 3 ||
            username.runes.length > 32 ||
            !RegExp(r'^[\p{L}\p{N}_-]+$', unicode: true).hasMatch(username))) {
      throw ApiFailure('invalidUsername');
    }
  }

  Future<void> register({
    required String email,
    required String code,
    required String username,
    required String password,
    required String confirmPassword,
  }) async {
    final generation = _generation, target = baseUrl;
    email = email.trim().toLowerCase();
    username = username.trim();
    _validateAccountInput(username, password, confirmPassword);
    if (username.isEmpty) throw ApiFailure('invalidUsername');
    try {
      await _request('POST', '/auth/register', {
        'email': email,
        'code': code,
        'username': username,
        'password': password,
        'confirm_password': confirmPassword,
      });
      _checkAuthContext(generation, target);
    } catch (e) {
      _checkAuthContext(generation, target);
      if (!demoMode || !_fallback(e)) rethrow;
      _verifyDemoCode(email, 'register', code);
      if (_demoAccounts.values.any(
            (row) =>
                row['email'] == email ||
                '${row['username']}'.toLowerCase() == username.toLowerCase(),
          ) ||
          ['admin', 'customer'].contains(username.toLowerCase())) {
        throw ApiFailure('account_exists', status: 409);
      }
      _demoAccounts[email] = {
        'id': 'demo-${_key()}',
        'role': 'customer',
        'name': username,
        'username': username,
        'email': email,
        'password': password,
        'avatar_url': '',
        'avatar_color': Random.secure().nextInt(0xffffff),
      };
      _demoCodes.remove('$email:register');
    }
    await login(email, password);
  }

  Future<void> resetPassword({
    required String email,
    required String code,
    required String password,
    required String confirmPassword,
  }) async {
    final generation = _generation, target = baseUrl;
    email = email.trim().toLowerCase();
    _validateAccountInput('', password, confirmPassword);
    try {
      await _request('POST', '/auth/reset-password', {
        'email': email,
        'code': code,
        'password': password,
        'confirm_password': confirmPassword,
      });
      _checkAuthContext(generation, target);
    } catch (e) {
      _checkAuthContext(generation, target);
      if (!demoMode || !_fallback(e)) rethrow;
      _verifyDemoCode(email, 'reset_password', code);
      final account = _demoAccounts[email];
      if (account == null) throw ApiFailure('invalidCode');
      account['password'] = password;
      _demoCodes.remove('$email:reset_password');
    }
    logout();
  }

  Future<void> updateProfile({required String username, String? avatar}) async {
    if (user == null) throw ApiFailure('signInFirst', status: 401);
    final generation = _generation;
    _validateAccountInput(username.trim(), 'unused-pass', 'unused-pass');
    if (username.trim().isEmpty) throw ApiFailure('invalidUsername');
    try {
      final result = await _request('PUT', '/auth/profile', {
        'username': username.trim(),
        'avatar': ?avatar,
      });
      if (generation != _generation) {
        throw ApiFailure('signInFirst', status: 401);
      }
      user = object(result['user']);
    } catch (e) {
      if (generation != _generation) rethrow;
      if (!demoMode || token != null || !_fallback(e)) rethrow;
      if (_demoAccounts.values.any(
        (row) =>
            row['id'] != user!['id'] &&
            '${row['username']}'.toLowerCase() == username.trim().toLowerCase(),
      )) {
        throw ApiFailure('username_taken', status: 409);
      }
      user = {
        ...user!,
        'username': username.trim(),
        'name': username.trim(),
        'avatar_url': ?avatar,
      };
      final saved = _demoAccounts['${user!['email']}'];
      if (saved != null) saved.addAll(user!);
    }
    notifyListeners();
  }

  void logout() {
    _generation++;
    _sequence++;
    token = null;
    user = null;
    orders = [];
    pending = null;
    refreshError = null;
    adminCatalogue = false;
    if (!demo) products = shopSamples.map(copy).toList();
    demo = true;
    notifyListeners();
  }

  void configure(String url, int timeout) {
    final next = WorkspaceRepository.normalizeUrl(url);
    if (timeout < 500 || timeout > 10000) throw ApiFailure('500–10000 ms');
    logout();
    baseUrl = next;
    timeoutMs = timeout;
    products = shopSamples.map(copy).toList();
    demo = true;
    shopConfig = {'demo_mode': false};
    _serverDemo = null;
    _demoAccounts.clear();
    _demoCodes.clear();
    banners = defaultShopBanners();
    _bannersKnown = false;
  }

  String get _pendingKey => 'shop-pending:$baseUrl:${user?['id']}';
  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (pending == null) {
        await prefs.remove(_pendingKey);
      } else {
        await prefs.setString(
          _pendingKey,
          jsonEncode({
            'path': pending!.path,
            'method': pending!.method,
            'body': pending!.body,
            'key': pending!.key,
          }),
        );
      }
    } catch (_) {
      /* Memory protection remains when platform preferences are unavailable. */
    }
  }

  Future<void> restorePending() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(
        _pendingKey,
      );
      if (raw != null) {
        final row = object(jsonDecode(raw));
        pending = ShopPending(
          row['path'],
          row['method'],
          object(row['body']),
          row['key'],
        );
      }
    } catch (_) {}
  }

  Future<Json> buy(Json product, [Json requirements = const {}]) =>
      _write('POST', '/shop-orders', {
        'product_id': product['id'],
        'product_version': product['version'],
        ...requirements,
      });
  Future<Json> action(Json order, String action, [Json fields = const {}]) =>
      _write('POST', '/shop-orders/${order['id']}/actions', {
        'action': action,
        'expected_version': order['version'],
        ...fields,
      });
  Future<Json> saveProduct(Json product, {String? id, int? version}) => _write(
    id == null ? 'POST' : 'PUT',
    '/admin/products${id == null ? '' : '/$id'}',
    {
      for (final key in [
        'category_id',
        'kind',
        'name',
        'summary',
        'description',
        'price_minor',
        'currency',
        'image',
        'sections',
        'active',
        'in_stock',
        'is_demo',
        'reference_price',
      ])
        if (product.containsKey(key)) key: product[key],
      'expected_version': ?version,
    },
  );
  Future<Json> saveBanner(Json banner, {String? id, int? version}) => _write(
    id == null ? 'POST' : 'PUT',
    '/admin/banners${id == null ? '' : '/$id'}',
    {
      for (final key in [
        'title',
        'image',
        'target_url',
        'active',
        'sort_order',
      ])
        key: banner[key],
      'expected_version': ?version,
    },
  );
  Future<Json> _write(String method, String path, Json body) async {
    if (user == null) throw ApiFailure('signInFirst');
    if (pending != null) throw ApiFailure('pendingWrite');
    final operation = ShopPending(path, method, copy(body), _key());
    return _send(operation, mayDemo: demo);
  }

  Future<Json> retryPending() async {
    if (pending == null) throw ApiFailure('pendingWrite');
    return _send(pending!, mayDemo: false);
  }

  Future<Json> reconcilePending() async {
    if (pending == null) throw ApiFailure('pendingWrite');
    final generation = _generation;
    final result = await _request('GET', '/shop-operations/${pending!.key}');
    if (generation != _generation) throw ApiFailure('account');
    _apply(result);
    pending = null;
    await _persist();
    notifyListeners();
    return result;
  }

  Future<Json> _send(ShopPending operation, {required bool mayDemo}) async {
    if (_writing) throw ApiFailure('pendingWrite');
    _writing = true;
    final generation = _generation;
    try {
      // Demo IDs and session tokens never become real orders when the server returns.
      if (mayDemo && token == null) {
        await _request(
          operation.method,
          operation.path,
          operation.body,
          operation.key,
        );
        throw ApiFailure('signInFirst', status: 401);
      }
      if (mayDemo) {
        await refresh();
        if (!demo) throw ApiFailure('reselect');
      }
      final result = await _request(
        operation.method,
        operation.path,
        operation.body,
        operation.key,
      );
      if (generation != _generation) throw ApiFailure('account');
      _apply(result);
      pending = null;
      await _persist();
      demo = false;
      notifyListeners();
      return result;
    } catch (e) {
      if (generation != _generation) rethrow;
      if (!_fallback(e)) {
        if (pending == operation) {
          pending = null;
          await _persist();
        }
        rethrow;
      }
      if (mayDemo) {
        final result = _local(operation);
        notifyListeners();
        return result;
      }
      pending = operation;
      await _persist();
      notifyListeners();
      throw ApiFailure('pendingWrite');
    } finally {
      _writing = false;
    }
  }

  void _apply(Json result) {
    _sequence++;
    if (result['order'] is Map) {
      final order = _orders([result['order']]).single;
      orders = [order, ...orders.where((o) => o['id'] != order['id'])];
    } else if (result['banner'] is Map) {
      final banner = _banners([result['banner']]).single;
      _bannersKnown = true;
      banners = [banner, ...banners.where((b) => b['id'] != banner['id'])];
      _bannerSequence++;
    } else if (result['product'] is Map) {
      final product = _products([result['product']]).single;
      products = [product, ...products.where((p) => p['id'] != product['id'])];
    } else {
      throw const FormatException('Invalid write response');
    }
  }

  Json _local(ShopPending operation) {
    _sequence++;
    final body = operation.body;
    if (operation.path.startsWith('/admin/banners')) {
      if (!admin) throw ApiFailure('admin', status: 403);
      final id = operation.method == 'POST'
          ? 'demo-${_key()}'
          : operation.path.split('/').last;
      final previous = banners.where((b) => b['id'] == id).firstOrNull;
      if (previous != null && previous['version'] != body['expected_version']) {
        throw ApiFailure('version', status: 409);
      }
      final banner = {
        ...body,
        'id': id,
        'version': (previous?['version'] ?? 0) + 1,
      };
      banners = [banner, ...banners.where((b) => b['id'] != id)];
      _bannersKnown = true;
      return {'banner': banner};
    }
    if (operation.path.startsWith('/admin/products')) {
      if (!admin) throw ApiFailure('admin', status: 403);
      final id = operation.method == 'POST'
          ? 'demo-${_key()}'
          : operation.path.split('/').last;
      final previous = products.where((p) => p['id'] == id).firstOrNull;
      if (previous != null && previous['version'] != body['expected_version']) {
        throw ApiFailure('version', status: 409);
      }
      final product = {
        ...body,
        'id': id,
        'version': (previous?['version'] ?? 0) + 1,
        'is_demo': true,
      };
      products = [product, ...products.where((p) => p['id'] != id)];
      return {'product': product};
    }
    if (operation.path == '/shop-orders') {
      if (admin) throw ApiFailure('customer', status: 403);
      final product = products
          .where((p) => p['id'] == body['product_id'])
          .firstOrNull;
      if (product == null ||
          product['active'] != true ||
          product['in_stock'] != true ||
          product['version'] != body['product_version']) {
        throw ApiFailure('outOfStock', status: 409);
      }
      final order = {
        'id': 'demo-${_key()}',
        'owner_id': user!['id'],
        'product_snapshot': copy(product),
        'quantity': 1,
        'amount_minor': product['price_minor'],
        'currency': 'CNY',
        'status': 'pending_payment',
        'fulfillment_status': 'pending',
        'version': 1,
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'requirements': body['requirements'] ?? '',
        'contact': body['contact'] ?? '',
        'delivery_requirements': body['delivery_requirements'] ?? '',
        'accepted_at': '',
        'editable': true,
      };
      orders.insert(0, order);
      _demoOrders.add(order);
      return {'order': order};
    }
    final id = operation.path.split('/')[2];
    final order = orders.where((o) => o['id'] == id).firstOrNull;
    if (order == null || order['version'] != body['expected_version']) {
      throw ApiFailure('version', status: 409);
    }
    final action = body['action'];
    if (admin) {
      if (order['status'] != 'pending_completion' ||
          order['fulfillment_status'] == 'delivered') {
        throw ApiFailure('state', status: 409);
      }
      if (action == 'start' && order['fulfillment_status'] == 'pending') {
        order['fulfillment_status'] = 'in_progress';
      } else if (action == 'deliver' &&
          '${body['text'] ?? ''}'.trim().isNotEmpty) {
        order['fulfillment_status'] = 'delivered';
        order['delivery_text'] = body['text'];
        order['delivered_at'] = DateTime.now().toUtc().toIso8601String();
      } else {
        throw ApiFailure('state', status: 409);
      }
      if ('${order['accepted_at'] ?? ''}'.isEmpty) {
        order['accepted_at'] = DateTime.now().toUtc().toIso8601String();
      }
      order['editable'] = false;
      order['version'] = (order['version'] as int) + 1;
      return {'order': order};
    }
    if (order['owner_id'] != user!['id']) {
      throw ApiFailure('account', status: 403);
    }
    if (action == 'edit') {
      if (!shopOrderEditable(order)) {
        throw ApiFailure('orderLocked', status: 409);
      }
      for (final key in ['requirements', 'contact', 'delivery_requirements']) {
        order[key] = body[key] ?? '';
      }
    } else if (action == 'pay' && order['status'] == 'pending_payment') {
      if (!['alipay', 'wechat'].contains(body['channel'])) {
        throw ApiFailure('state', status: 422);
      }
      order['status'] = 'pending_completion';
      order['paid_at'] = DateTime.now().toUtc().toIso8601String();
      order['payment'] = {
        'channel': body['channel'],
        'mode': 'mock',
        'status': 'succeeded',
        'amount_minor': order['amount_minor'],
      };
    } else if (action == 'cancel' && order['status'] == 'pending_payment') {
      order['status'] = 'cancelled';
      order['editable'] = false;
    } else if (action == 'accept' &&
        order['status'] == 'pending_completion' &&
        order['fulfillment_status'] == 'delivered') {
      order['status'] = 'pending_review';
      order['completed_at'] = DateTime.now().toUtc().toIso8601String();
    } else if (action == 'review' &&
        order['status'] == 'pending_review' &&
        body['text'].toString().trim().isNotEmpty &&
        (body['rating'] as int) >= 1 &&
        (body['rating'] as int) <= 5) {
      order['status'] = 'completed';
      order['review'] = {'rating': body['rating'], 'text': body['text']};
    } else {
      throw ApiFailure('state', status: 409);
    }
    order['version'] = (order['version'] as int) + 1;
    return {'order': order};
  }

  @override
  void dispose() {
    _generation++;
    _client.close();
    super.dispose();
  }
}
