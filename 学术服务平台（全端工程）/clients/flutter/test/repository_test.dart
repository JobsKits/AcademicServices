import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zhixu/data/models.dart';
import 'package:zhixu/data/repository.dart';

http.Response ok(Json value) => http.Response(
  jsonEncode(value),
  200,
  headers: {'content-type': 'application/json'},
);
Json fixture(String id) => {...demoCases(id).first, 'id': 'real-case'};
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  WorkspaceRepository setup(
    Future<http.Response> Function(http.Request) handler,
  ) => WorkspaceRepository(
    baseUrl: 'https://example.test/api/v1',
    client: MockClient(handler),
  );
  Json login(String name) => {
    'token': 'token-$name',
    'user': {'id': name, 'name': name, 'role': 'customer'},
  };
  test('real empty list stays empty and does not become sample data', () async {
    final repo = setup(
      (r) async => r.url.path.endsWith('login')
          ? ok(login('a'))
          : ok({
              'user': login('a')['user'],
              'services': demoServices,
              'cases': [],
            }),
    );
    await repo.login('a', 'x');
    expect(repo.demo, false);
    expect(repo.cases, isEmpty);
    repo.dispose();
  });
  test('network read failure uses isolated data then auto-recovers', () async {
    var fail = false;
    final repo = setup((r) async {
      if (r.url.path.endsWith('login')) return ok(login('a'));
      if (fail) throw Exception('offline');
      return ok({
        'user': login('a')['user'],
        'services': demoServices,
        'cases': [fixture('a')],
      });
    });
    await repo.login('a', 'x');
    expect(repo.cases.single['id'], 'real-case');
    fail = true;
    await repo.refresh();
    expect(repo.demo, true);
    expect(repo.cases.single['id'], 'demo-case');
    fail = false;
    await repo.refresh();
    expect(repo.demo, false);
    expect(repo.cases.single['id'], 'real-case');
    repo.dispose();
  });
  test('401 login never becomes a demo success', () async {
    final repo = setup(
      (r) async =>
          http.Response.bytes(utf8.encode('{"error":{"message":"密码无效"}}'), 401),
    );
    await expectLater(
      repo.login('a', 'bad', allowDemo: true),
      throwsA(isA<ApiFailure>()),
    );
    expect(repo.user, isNull);
    repo.dispose();
  });
  test('protected 401 revokes user and private cache', () async {
    var revoked = false;
    final repo = setup((r) async {
      if (r.url.path.endsWith('login')) return ok(login('a'));
      if (revoked) {
        return http.Response.bytes(
          utf8.encode('{"error":{"message":"过期"}}'),
          401,
        );
      }
      return ok({
        'user': login('a')['user'],
        'services': demoServices,
        'cases': [fixture('a')],
      });
    });
    await repo.login('a', 'x');
    revoked = true;
    await expectLater(repo.refresh(), throwsA(isA<ApiFailure>()));
    expect(repo.user, isNull);
    expect(repo.cases, isEmpty);
    repo.dispose();
  });
  test(
    'unknown real write retains original key and never fakes success',
    () async {
      var mutation = 0;
      final keys = <String>[];
      final repo = setup((r) async {
        if (r.url.path.endsWith('login')) return ok(login('a'));
        if (r.method == 'POST') {
          keys.add(r.headers['Idempotency-Key']!);
          mutation++;
          if (mutation == 1) throw Exception('lost response');
          return ok({'case': fixture('a')});
        }
        return ok({
          'user': login('a')['user'],
          'services': demoServices,
          'cases': [],
        });
      });
      await repo.login('a', 'x');
      await expectLater(
        repo.create({'title': 'hello'}),
        throwsA(isA<UnknownWrite>()),
      );
      expect(repo.cases, isEmpty);
      expect(repo.demo, false);
      expect(repo.pending, isNotNull);
      await repo.retryPending();
      expect(keys[0], keys[1]);
      expect(repo.cases.single['id'], 'real-case');
      expect(repo.pending, isNull);
      repo.dispose();
    },
  );
  test('422 does not create a fake case or leave an unknown write', () async {
    final repo = setup((r) async {
      if (r.url.path.endsWith('login')) return ok(login('a'));
      if (r.method == 'POST') {
        return http.Response.bytes(
          utf8.encode('{"error":{"message":"字段无效"}}'),
          422,
        );
      }
      return ok({
        'user': login('a')['user'],
        'services': demoServices,
        'cases': [],
      });
    });
    await repo.login('a', 'x');
    await expectLater(repo.create({'title': ''}), throwsA(isA<ApiFailure>()));
    expect(repo.pending, isNull);
    expect(repo.cases, isEmpty);
    repo.dispose();
  });
  test('late private response cannot overwrite new account', () async {
    final late = Completer<http.Response>();
    var reads = 0;
    String current = 'a';
    final repo = setup((r) async {
      if (r.url.path.endsWith('login')) {
        current = object(jsonDecode(r.body))['account'];
        return ok(login(current));
      }
      reads++;
      if (reads == 2) return late.future;
      return ok({
        'user': login(current)['user'],
        'services': demoServices,
        'cases': [fixture(current)],
      });
    });
    await repo.login('a', 'x');
    final old = repo.refresh();
    await repo.login('b', 'x');
    late.complete(
      ok({
        'user': login('a')['user'],
        'services': demoServices,
        'cases': [fixture('a')],
      }),
    );
    await old;
    expect(repo.user!['id'], 'b');
    expect(repo.cases.single['owner_id'], 'b');
    repo.dispose();
  });
  test('nested malformed payload falls back before rendering', () async {
    final bad = fixture('a');
    bad['order'] = {
      'id': 'o',
      'status': 'in_service',
      'amount_minor': 1,
      'deliveries': {},
    };
    final repo = setup(
      (r) async => r.url.path.endsWith('login')
          ? ok(login('a'))
          : ok({
              'user': login('a')['user'],
              'services': demoServices,
              'cases': [bad],
            }),
    );
    await repo.login('a', 'x');
    expect(repo.demo, true);
    expect(repo.cases.single['id'], 'demo-case');
    repo.dispose();
  });
  test(
    'read response started before write cannot replace new version',
    () async {
      final late = Completer<http.Response>();
      var reads = 0;
      final repo = setup((r) async {
        if (r.url.path.endsWith('login')) return ok(login('a'));
        if (r.method == 'POST') {
          final c = fixture('a');
          c['version'] = 2;
          return ok({'case': c});
        }
        reads++;
        if (reads == 2) return late.future;
        return ok({
          'user': login('a')['user'],
          'services': demoServices,
          'cases': [fixture('a')],
        });
      });
      await repo.login('a', 'x');
      final old = repo.refresh();
      await repo.action(repo.cases.single, 'message', {'text': 'new'});
      late.complete(
        ok({
          'user': login('a')['user'],
          'services': demoServices,
          'cases': [fixture('a')],
        }),
      );
      await old;
      expect(repo.cases.single['version'], 2);
      repo.dispose();
    },
  );
  test('URL changes require secure hosts and clear session', () async {
    final repo = setup(
      (r) async => r.url.path.endsWith('login')
          ? ok(login('a'))
          : ok({
              'user': login('a')['user'],
              'services': demoServices,
              'cases': [],
            }),
    );
    await repo.login('a', 'x');
    expect(
      () => repo.setBaseUrl('http://192.168.1.1/api/v1'),
      throwsA(isA<ApiFailure>()),
    );
    repo.setBaseUrl('https://other.example/api/v1');
    expect(repo.user, isNull);
    expect(repo.cases, isEmpty);
    repo.dispose();
  });
  test('original write can be reconciled by GET without re-post', () async {
    int posts = 0;
    final repo = setup((r) async {
      if (r.url.path.endsWith('login')) return ok(login('a'));
      if (r.url.path.contains('/operations/')) {
        return ok({
          'operation': {'status': 'succeeded'},
          'case': fixture('a'),
        });
      }
      if (r.method == 'POST') {
        posts++;
        throw Exception('unknown');
      }
      return ok({
        'user': login('a')['user'],
        'services': demoServices,
        'cases': [],
      });
    });
    await repo.login('a', 'x');
    await expectLater(
      repo.create({'title': 'hello'}),
      throwsA(isA<UnknownWrite>()),
    );
    await repo.reconcilePending();
    expect(posts, 1);
    expect(repo.pending, isNull);
    expect(repo.cases.single['id'], 'real-case');
    repo.dispose();
  });
  test('pending key survives a new repository session and keeps the original payload', () async {
    final sent = <String>[];
    bool offline = true;
    Future<http.Response> handler(http.Request r) async {
      if (r.url.path.endsWith('login')) return ok(login('a'));
      if (r.method == 'POST') {
        sent.add(r.headers['Idempotency-Key']!);
        if (offline) throw Exception('lost response');
        return ok({'case': fixture('a')});
      }
      return ok({
        'user': login('a')['user'],
        'services': demoServices,
        'cases': [],
      });
    }

    final first = setup(handler);
    await first.login('a', 'x');
    await expectLater(
      first.create({'title': 'same original'}),
      throwsA(isA<UnknownWrite>()),
    );
    final key = first.pending!.key;
    first.dispose();
    offline = false;
    final second = setup(handler);
    await second.restorePending();
    await second.login('a', 'x');
    expect(second.pending!.key, key);
    expect(second.pending!.body['title'], 'same original');
    await second.retryPending();
    expect(sent, [key, key]);
    second.dispose();
  });
  test('pending result remains scoped to its original account', () async {
    String current = 'a';
    final repo = setup((r) async {
      if (r.url.path.endsWith('login')) {
        current = object(jsonDecode(r.body))['account'];
        return ok(login(current));
      }
      if (r.method == 'POST') throw Exception('unknown');
      return ok({
        'user': login(current)['user'],
        'services': demoServices,
        'cases': [],
      });
    });
    await repo.login('a', 'x');
    await expectLater(
      repo.create({'title': 'private'}),
      throwsA(isA<UnknownWrite>()),
    );
    final oldKey = repo.pending!.key;
    await repo.login('b', 'x');
    expect(repo.pending, isNull);
    expect(repo.cases, isEmpty);
    await repo.login('a', 'x');
    expect(repo.pending!.key, oldKey);
    repo.dispose();
  });
  test('foreign customer data in a malformed 2xx is never cached', () async {
    final repo = setup(
      (r) async => r.url.path.endsWith('login')
          ? ok(login('a'))
          : ok({
              'user': login('a')['user'],
              'services': demoServices,
              'cases': [fixture('someone-else')],
            }),
    );
    await repo.login('a', 'x');
    expect(repo.demo, true);
    expect(repo.cases.every((c) => c['owner_id'] == 'a'), true);
    repo.dispose();
  });
  test('403 action is a denial and never a simulated success', () async {
    final repo = setup((r) async {
      if (r.url.path.endsWith('login')) return ok(login('a'));
      if (r.method == 'POST') {
        return http.Response('{"error":{"message":"denied"}}', 403);
      }
      return ok({
        'user': login('a')['user'],
        'services': demoServices,
        'cases': [fixture('a')],
      });
    });
    await repo.login('a', 'x');
    await expectLater(
      repo.action(repo.cases.single, 'quote', {}),
      throwsA(isA<ApiFailure>()),
    );
    expect(repo.demo, false);
    expect(repo.pending, isNull);
    expect(repo.cases.single['version'], 1);
    repo.dispose();
  });
  test(
    'JSON redirects do not become write success or forward credentials',
    () async {
      bool? followed;
      final repo = setup((r) async {
        if (r.url.path.endsWith('login')) return ok(login('a'));
        if (r.method == 'POST') {
          followed = r.followRedirects;
          return http.Response(
            jsonEncode({'case': fixture('a')}),
            302,
            headers: {'location': 'https://elsewhere.example/collect'},
          );
        }
        return ok({
          'user': login('a')['user'],
          'services': demoServices,
          'cases': [],
        });
      });
      await repo.login('a', 'x');
      await expectLater(
        repo.create({'title': 'hello'}),
        throwsA(isA<UnknownWrite>()),
      );
      expect(followed, false);
      expect(repo.pending, isNotNull);
      expect(repo.cases, isEmpty);
      repo.dispose();
    },
  );
  test('201 creation is accepted as a final success', () async {
    final repo = setup((r) async {
      if (r.url.path.endsWith('login')) return ok(login('a'));
      if (r.method == 'POST') {
        return http.Response(
          jsonEncode({'case': fixture('a')}),
          201,
          headers: {'content-type': 'application/json;charset=utf-8'},
        );
      }
      return ok({
        'user': login('a')['user'],
        'services': demoServices,
        'cases': [],
      });
    });
    await repo.login('a', 'x');
    await repo.create({'title': 'hello'});
    expect(repo.pending, isNull);
    expect(repo.cases.single['id'], 'real-case');
    repo.dispose();
  });
  test(
    'late old-account attachment denial cannot revoke the new session',
    () async {
      final late = Completer<http.Response>();
      String current = 'a';
      final repo = setup((r) async {
        if (r.url.path.endsWith('login')) {
          current = object(jsonDecode(r.body))['account'];
          return ok(login(current));
        }
        if (r.url.path.contains('/attachments/')) return late.future;
        return ok({
          'user': login(current)['user'],
          'services': demoServices,
          'cases': [fixture(current)],
        });
      });
      await repo.login('a', 'x');
      final download = repo.download(repo.cases.single, {'id': 'file'});
      await repo.login('b', 'x');
      late.complete(http.Response('{"error":{"message":"old session"}}', 401));
      await expectLater(download, throwsA(isA<ApiFailure>()));
      expect(repo.user!['id'], 'b');
      expect(repo.cases.single['owner_id'], 'b');
      repo.dispose();
    },
  );
}
