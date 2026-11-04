import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

class ApiFailure implements Exception {
  ApiFailure(this.message, {this.status, this.code});
  final String message;
  final int? status;
  final String? code;
  @override
  String toString() => message;
}

class UnknownWrite implements Exception {
  const UnknownWrite();
  @override
  String toString() => '服务器结果暂未确认。请核对最新列表，或使用“重试原请求”；不会改为演示成功。';
}

class PendingWrite {
  PendingWrite(this.path, this.body, this.key, this.account);
  final String path, key, account;
  final Json body;
}

class WorkspaceRepository extends ChangeNotifier {
  WorkspaceRepository({
    required String baseUrl,
    http.Client? client,
    this.timeout = const Duration(milliseconds: 2200),
  }) : _baseUrl = normalizeUrl(baseUrl),
       _client = client ?? http.Client();
  final http.Client _client;
  final Duration timeout;
  String _baseUrl;
  String get baseUrl => _baseUrl;
  String? token;
  Json? user;
  List<Json> services = demoServices.map(copy).toList();
  List<Json> cases = [];
  bool demo = true, busy = false;
  bool servicesOnline = false;
  String notice = '连接中，先显示服务介绍';
  final Map<String, PendingWrite> _pendingByAccount = {};
  String get _accountKey => '$_baseUrl|${user?['id']}';
  PendingWrite? get pending => _pendingByAccount[_accountKey];
  set pending(PendingWrite? value) {
    if (value == null) {
      _pendingByAccount.remove(_accountKey);
    } else {
      _pendingByAccount[_accountKey] = value;
    }
  }

  int _generation = 0;
  int _readSequence = 0;
  bool get admin => user?['role'] == 'admin';
  String newKey() {
    final r = Random.secure();
    return List.generate(
      20,
      (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  static String normalizeUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw ApiFailure('请输入完整的 HTTP 或 HTTPS 服务地址，例如 https://服务域名/api/v1');
    }
    if (uri.scheme == 'http' &&
        !['localhost', '127.0.0.1', '10.0.2.2', '::1'].contains(uri.host)) {
      throw ApiFailure('正式及局域网服务地址必须使用 HTTPS；HTTP 仅用于本机开发');
    }
    return value.trim().replaceFirst(RegExp(r'/+$'), '');
  }

  void setBaseUrl(String value) {
    final next = normalizeUrl(value);
    if (next == _baseUrl) return;
    logout();
    _baseUrl = next;
    services = demoServices.map(copy).toList();
    servicesOnline = false;
    notice = '服务地址已切换，请重新登录';
    notifyListeners();
  }

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    if (token != null) 'Authorization': 'Bearer $token',
  };
  Future<Json> _request(
    String method,
    String path, {
    Json? body,
    String? key,
  }) async {
    final headers = {..._headers, 'Idempotency-Key': ?key};
    final uri = Uri.parse('$_baseUrl$path');
    final request = http.Request(method, uri)..followRedirects = false;
    request.headers.addAll(headers);
    if (body != null) request.body = jsonEncode(body);
    final streamed = await _client.send(request).timeout(timeout);
    final response = await http.Response.fromStream(streamed).timeout(timeout);
    return _decode(response);
  }

  Json _decode(http.Response response) {
    if (response.statusCode < 200 ||
        (response.statusCode >= 300 && response.statusCode < 400)) {
      throw ApiFailure(
        '服务返回重定向或非最终响应，请核对 API 地址；不会转发登录凭据',
        status: 502,
        code: 'unexpected_response',
      );
    }
    Json result;
    try {
      result = object(jsonDecode(utf8.decode(response.bodyBytes)));
    } catch (_) {
      if (response.statusCode >= 400 && response.statusCode < 500) {
        throw ApiFailure(
          '请求未被接受（${response.statusCode}）',
          status: response.statusCode,
        );
      }
      throw const FormatException('响应不是有效 JSON');
    }
    if (response.statusCode >= 400) {
      throw ApiFailure(
        '${result['error']?['message'] ?? '服务暂不可用'}',
        status: response.statusCode,
        code: '${result['error']?['code'] ?? ''}',
      );
    }
    return result;
  }

  bool _fallback(Object e) => e is! ApiFailure || (e.status ?? 0) >= 500;
  void _authFailure(Object e) {
    if (e is ApiFailure && e.status == 401) logout();
  }

  Future<void> loadServices() async {
    final generation = _generation;
    try {
      final result = await _request('GET', '/services');
      final list = validateServices(result['services']);
      if (generation != _generation) return;
      services = list;
      servicesOnline = true;
      notice = user == null ? '服务信息已连接' : notice;
    } catch (e) {
      if (generation != _generation) return;
      if (!_fallback(e)) rethrow;
      services = demoServices.map(copy).toList();
      servicesOnline = false;
      notice = '服务暂时离线，当前为本地服务介绍';
    }
    notifyListeners();
  }

  Future<void> login(
    String account,
    String password, {
    bool allowDemo = false,
    bool asAdmin = false,
  }) async {
    logout();
    final generation = _generation;
    busy = true;
    notifyListeners();
    try {
      final result = await _request(
        'POST',
        '/auth/login',
        body: {'account': account, 'password': password},
      );
      final nextUser = object(result['user']);
      if (result['token'] is! String ||
          nextUser['id'] is! String ||
          !['customer', 'admin'].contains(nextUser['role'])) {
        throw const FormatException('登录响应不完整');
      }
      if (generation != _generation) return;
      token = result['token'];
      user = nextUser;
      demo = false;
      await refresh();
    } catch (e) {
      if (generation != _generation) return;
      if (allowDemo && _fallback(e)) {
        user = {
          'id': 'demo-${asAdmin ? 'admin' : 'customer'}',
          'name': asAdmin ? '演示管理员' : '演示客户',
          'role': asAdmin ? 'admin' : 'customer',
        };
        token = null;
        demo = true;
        cases = demoCases(user!['id']);
        notice = '本地演示，操作仅保存在本次会话';
      } else {
        _authFailure(e);
        rethrow;
      }
    } finally {
      if (generation == _generation) {
        busy = false;
        notifyListeners();
      }
    }
  }

  Future<void> refresh() async {
    final generation = _generation;
    final sequence = ++_readSequence;
    if (token == null) {
      await loadServices();
      return;
    }
    try {
      final result = await _request('GET', '/workspace');
      final nextUser = object(result['user']);
      if (nextUser['id'] != user?['id'] || nextUser['role'] != user?['role']) {
        throw const FormatException('会话身份不匹配');
      }
      final list = validateCases(result['cases']);
      if (user?['role'] != 'admin' &&
          list.any((c) => c['owner_id'] != user?['id'])) {
        throw const FormatException('需求归属不匹配');
      }
      final nextServices = validateServices(result['services']);
      if (generation != _generation || sequence != _readSequence) return;
      cases = list;
      services = nextServices;
      demo = false;
      notice = pending == null ? '已连接 · 数据已保存到服务端' : '已重新连接，请核对未确认操作';
    } catch (e) {
      if (generation != _generation || sequence != _readSequence) return;
      _authFailure(e);
      if (!_fallback(e)) rethrow;
      demo = true;
      cases = demoCases('${user?['id'] ?? 'demo-customer'}');
      notice = '网络暂不可用 · 当前为隔离演示数据，可重新加载恢复';
    }
    notifyListeners();
  }

  static List<Json> validateServices(dynamic value) {
    if (value is! List) throw const FormatException('缺少服务列表');
    final list = objects(value);
    for (final s in list) {
      if (s['id'] is! String || s['name'] is! String || s['active'] is! bool) {
        throw const FormatException('服务字段无效');
      }
    }
    return list;
  }

  static List<Json> validateCases(dynamic value) {
    if (value is! List) throw const FormatException('缺少需求列表');
    final list = objects(value);
    for (final c in list) {
      if (c['id'] is! String ||
          c['title'] is! String ||
          c['version'] is! int ||
          c['status'] is! String ||
          c['service_id'] is! String ||
          c['owner_id'] is! String) {
        throw const FormatException('需求字段无效');
      }
      for (final field in [
        'attachments',
        'messages',
        'events',
        'after_sales',
      ]) {
        if (c[field] != null && c[field] is! List) {
          throw FormatException('$field 无效');
        }
      }
      for (final field in ['quote', 'order']) {
        if (c[field] != null && c[field] is! Map) {
          throw FormatException('$field 无效');
        }
      }
      final q = c['quote'];
      if (q != null &&
          (q['id'] is! String ||
              q['amount_minor'] is! int ||
              q['scope'] is! String)) {
        throw const FormatException('报价无效');
      }
      final o = c['order'];
      if (o is Map) {
        for (final key in [
          'holds',
          'deliveries',
          'feedback',
          'payments',
          'refunds',
          'changes',
        ]) {
          if (o[key] != null && o[key] is! List) {
            throw FormatException('$key 无效');
          }
          if (o[key] is List) objects(o[key]);
        }
      }
      if (o != null &&
          (o['id'] is! String ||
              o['status'] is! String ||
              o['amount_minor'] is! int)) {
        throw const FormatException('订单无效');
      }
    }
    return list;
  }

  Future<Json> create(Json body) => _mutate('/cases', body);
  Future<Json> action(Json c, String action, Json fields) => _mutate(
    '/cases/${c['id']}/actions',
    {'action': action, 'expected_version': c['version'], ...fields},
  );
  Future<Json> _mutate(String path, Json body) async {
    if (user == null) throw ApiFailure('请先登录');
    if (pending != null) throw const UnknownWrite();
    if (demo) {
      if (token != null) {
        await refresh();
        if (!demo) throw ApiFailure('连接已恢复，请在真实列表重新选择需求后操作');
      } else {
        await loadServices();
      }
      return _demoMutate(path, body);
    }
    final operation = PendingWrite(
      path,
      copy(body),
      newKey(),
      '${user!['id']}',
    );
    return _sendWrite(operation);
  }

  Future<void> reconcilePending() async {
    final operation = pending;
    if (operation == null) return;
    final generation = _generation;
    final result = await _request('GET', '/operations/${operation.key}');
    final c = object(result['case']);
    validateCases([c]);
    if (generation != _generation) return;
    pending = null;
    unawaited(_persistPending());
    _readSequence++;
    final index = cases.indexWhere((x) => x['id'] == c['id']);
    if (index < 0) {
      cases.insert(0, c);
    } else {
      cases[index] = c;
    }
    demo = false;
    notice = '已核对原操作结果';
    notifyListeners();
  }

  Future<Json> retryPending() async {
    final operation = pending;
    if (operation == null) throw ApiFailure('没有待核对操作');
    if (user?['id'] != operation.account) throw ApiFailure('请以原账户登录核对');
    return _sendWrite(operation);
  }

  Future<void> restorePending() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('pending-writes-v1');
      if (raw == null) return;
      for (final item in objects(jsonDecode(raw))) {
        final origin = item['base_url'];
        if (origin is! String ||
            item['account'] is! String ||
            item['key'] is! String ||
            item['path'] is! String ||
            item['body'] is! Map) {
          continue;
        }
        _pendingByAccount['$origin|${item['account']}'] = PendingWrite(
          item['path'],
          object(item['body']),
          item['key'],
          item['account'],
        );
      }
    } catch (_) {}
  }

  Future<void> _persistPending() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rows = _pendingByAccount.entries
          .map(
            (entry) => {
              'base_url': entry.key.substring(0, entry.key.lastIndexOf('|')),
              'account': entry.value.account,
              'path': entry.value.path,
              'key': entry.value.key,
              'body': entry.value.body,
            },
          )
          .toList();
      await prefs.setString('pending-writes-v1', jsonEncode(rows));
    } catch (_) {
      /* In-memory key still protects this session on unsupported preferences hosts. */
    }
  }

  Future<Json> _sendWrite(PendingWrite operation) async {
    final generation = _generation;
    pending = operation;
    await _persistPending();
    notifyListeners();
    try {
      if (generation != _generation) throw ApiFailure('账户已改变，请以原账户核对操作');
      final result = await _request(
        'POST',
        operation.path,
        body: operation.body,
        key: operation.key,
      );
      final c = object(result['case']);
      validateCases([c]);
      if (generation != _generation) throw ApiFailure('会话已改变，请在原账户查询操作结果');
      _readSequence++;
      pending = null;
      unawaited(_persistPending());
      demo = false;
      final i = cases.indexWhere((item) => item['id'] == c['id']);
      if (i < 0) {
        cases.insert(0, c);
      } else {
        cases[i] = c;
      }
      notice = '已保存到服务端';
      notifyListeners();
      return c;
    } catch (e) {
      if (generation != _generation) rethrow;
      if (!_fallback(e)) {
        _pendingByAccount.remove('$_baseUrl|${operation.account}');
        unawaited(_persistPending());
        _authFailure(e);
        notifyListeners();
        rethrow;
      }
      notice = '提交结果待确认 · 原请求键已保留';
      notifyListeners();
      throw const UnknownWrite();
    }
  }

  Future<void> upload(Json c, String name, Uint8List bytes) async {
    if (bytes.isEmpty || bytes.length > 8 * 1024 * 1024) {
      throw ApiFailure('文件须为 1 字节至 8 MB');
    }
    if (demo) throw ApiFailure('演示模式不保存原件，请连接服务后上传');
    if (pending != null) throw const UnknownWrite();
    final generation = _generation;
    final key = newKey();
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$_baseUrl/cases/${c['id']}/attachments'),
    );
    request.followRedirects = false;
    request.headers.addAll({
      'Authorization': 'Bearer $token',
      'Idempotency-Key': key,
    });
    request.fields['expected_version'] = '${c['version']}';
    request.files.add(
      http.MultipartFile.fromBytes('file', bytes, filename: name),
    );
    try {
      final response = await http.Response.fromStream(
        await _client.send(request).timeout(timeout * 4),
      ).timeout(timeout * 4);
      final result = _decode(response);
      validateCases([result['case']]);
      if (generation != _generation) return;
      _readSequence++;
      cases[cases.indexWhere((x) => x['id'] == c['id'])] = object(
        result['case'],
      );
      notice = '附件已保存';
      notifyListeners();
    } catch (e) {
      if (generation != _generation) throw ApiFailure('账户已改变，请以原账户查询上传结果');
      _authFailure(e);
      if (_fallback(e)) throw ApiFailure('上传结果待核对，请重新加载查看附件；勿立即重复上传。请求键：$key');
      rethrow;
    }
  }

  Future<Uint8List> download(Json c, Json attachment) async {
    if (demo) throw ApiFailure('演示文件不能下载');
    final generation = _generation;
    final request = http.Request(
      'GET',
      Uri.parse('$_baseUrl/cases/${c['id']}/attachments/${attachment['id']}'),
    )..followRedirects = false;
    request.headers.addAll(_headers);
    final response = await http.Response.fromStream(
      await _client.send(request).timeout(timeout * 4),
    ).timeout(timeout * 4);
    if (generation != _generation) throw ApiFailure('账户已改变，已取消文件保存');
    if (response.statusCode != 200) {
      try {
        _decode(response);
      } catch (e) {
        _authFailure(e);
        rethrow;
      }
    }
    return response.bodyBytes;
  }

  Json _demoMutate(String path, Json body) {
    if (path == '/cases') {
      final c = <String, dynamic>{
        ...copy(body),
        'id': 'demo-${newKey()}',
        'owner_id': user!['id'],
        'version': 1,
        'status': 'pending_review',
        'quote': null,
        'order': null,
        'attachments': [],
        'messages': [],
        'events': [],
        'after_sales': [],
        'created_at': DateTime.now().toUtc().toIso8601String(),
      };
      cases.insert(0, c);
      notifyListeners();
      return c;
    }
    final id = path.split('/')[2];
    final i = cases.indexWhere((x) => x['id'] == id);
    if (i < 0) throw ApiFailure('演示需求不存在');
    final c = copy(cases[i]);
    final a = body['action'];
    if (a == 'message') {
      (c['messages'] as List).add({
        'text': body['text'],
        'author': user!['name'],
      });
    } else if (a == 'quote' && admin) {
      c['quote'] = {
        'id': 'demo-${newKey()}',
        ...body,
        'status': 'offered',
        'currency': 'CNY',
      };
      c['status'] = 'awaiting_quote_accept';
    } else if (a == 'accept_quote' &&
        !admin &&
        c['quote']?['status'] == 'offered') {
      final q = c['quote'];
      q['status'] = 'accepted';
      c['status'] = 'converted';
      c['order'] = {
        'id': 'demo-order',
        'status': 'pending_start',
        'amount_minor': q['amount_minor'],
        'original_amount_minor': q['amount_minor'],
        'prepay_minor': q['prepay_minor'],
        'paid_minor': 0,
        'refunded_minor': 0,
        'refund_held_minor': 0,
        'revision_used': 0,
        'revision_limit': q['revision_limit'],
        'paused': false,
        'holds': [],
        'deliveries': [],
        'payments': [],
        'refunds': [],
      };
    } else if (a == 'start' &&
        admin &&
        c['order']?['status'] == 'pending_start') {
      c['order']['status'] = 'in_service';
    } else if (a == 'need_material' && admin) {
      c['status'] = 'awaiting_material';
    } else if (a == 'supplement' && !admin) {
      c['status'] = 'pending_review';
    } else {
      throw ApiFailure('此动作需要真实服务处理；本地演示支持提交、消息、报价、确认和开始服务');
    }
    c['version'] = (c['version'] as int) + 1;
    cases[i] = c;
    notifyListeners();
    return c;
  }

  void logout() {
    _generation++;
    _readSequence++;
    token = null;
    user = null;
    cases = [];
    demo = true;
    busy = false;
    notice = '请登录查看个人需求';
    notifyListeners();
  }

  @override
  void dispose() {
    _generation++;
    _client.close();
    super.dispose();
  }
}
