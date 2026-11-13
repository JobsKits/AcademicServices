import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zhixu/Data/models.dart';
import 'package:zhixu/Shop/repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  ShopRepository offline({bool demo = false}) => ShopRepository(
    baseUrl: 'https://example.test/api/v1',
    demoMode: demo,
    client: MockClient((_) async => throw Exception('offline')),
  );
  http.Response reply(Json value, [int status = 200]) => http.Response.bytes(
    utf8.encode(jsonEncode(value)),
    status,
    headers: {'content-type': 'application/json'},
  );

  test(
    'formal outage never grants a customer or administrator identity',
    () async {
      final repo = offline();
      await expectLater(
        repo.login('admin', '1234', asAdmin: true),
        throwsException,
      );
      expect(repo.user, isNull);
      await expectLater(
        repo.login('customer', 'demo-customer'),
        throwsException,
      );
      expect(repo.user, isNull);
      await repo.bootstrapAdmin();
      expect(repo.admin, isFalse);
    },
  );

  test(
    'explicit offline demo enters admin with the defined credentials',
    () async {
      final repo = offline(demo: true);
      await repo.bootstrapAdmin();
      expect(repo.admin, isTrue);
      expect(repo.user!['name'], 'admin');
      expect(repo.token, isNull);
      await expectLater(
        repo.login('admin', 'wrong', asAdmin: true),
        throwsException,
      );
      expect(repo.user, isNull);
    },
  );

  test(
    'formal server configuration overrides a demo build and denies auto entry',
    () async {
      var attemptedLogin = false;
      final repo = ShopRepository(
        baseUrl: 'https://example.test/api/v1',
        demoMode: true,
        client: MockClient((request) async {
          if (request.url.path.endsWith('/shop-config')) {
            return reply({'demo_mode': false});
          }
          attemptedLogin = true;
          throw Exception('offline');
        }),
      );
      await repo.bootstrapAdmin();
      expect(repo.demoMode, isFalse);
      expect(attemptedLogin, isFalse);
      expect(repo.user, isNull);
    },
  );

  test(
    'offline email demo registration profile login and reset remain isolated',
    () async {
      final repo = offline(demo: true);
      const email = 'demo@example.test';
      final challenge = await repo.requestEmailCode(email, purpose: 'register');
      expect(challenge['delivery'], 'demo');
      final code = challenge['demo_code'] as String;
      await expectLater(
        repo.register(
          email: email,
          code: code,
          username: '泉羽用户',
          password: 'password-original',
          confirmPassword: 'different',
        ),
        throwsException,
      );
      await repo.register(
        email: email,
        code: code,
        username: '泉羽用户',
        password: 'password-original',
        confirmPassword: 'password-original',
      );
      expect(repo.user!['email'], email);
      expect(repo.user!['role'], 'customer');
      expect(repo.token, isNull);
      await repo.updateProfile(username: '新用户名');
      repo.logout();
      await repo.login('新用户名', 'password-original');
      expect(repo.user!['name'], '新用户名');
      final reset = await repo.requestEmailCode(
        email,
        purpose: 'reset_password',
      );
      await repo.resetPassword(
        email: email,
        code: reset['demo_code'] as String,
        password: 'password-replaced',
        confirmPassword: 'password-replaced',
      );
      expect(repo.user, isNull);
      await expectLater(
        repo.login(email, 'password-original'),
        throwsException,
      );
      await repo.login(email, 'password-replaced');
      expect(repo.user!['name'], '新用户名');
    },
  );

  test('formal email service errors never masquerade as sent email', () async {
    final repo = ShopRepository(
      baseUrl: 'https://example.test/api/v1',
      client: MockClient(
        (_) async => reply({
          'error': {'message': 'email_unavailable'},
        }, 503),
      ),
    );
    await expectLater(
      repo.requestEmailCode('formal@example.test', purpose: 'register'),
      throwsException,
    );
  });
  test(
    'late auth responses cannot target a new server or log out its user',
    () async {
      for (final action in ['code', 'register', 'reset']) {
        final result = Completer<http.Response>();
        final targets = <String>[];
        final repo = ShopRepository(
          baseUrl: 'https://old.test/api/v1',
          demoMode: true,
          client: MockClient((request) {
            targets.add(request.url.host);
            return result.future;
          }),
        );
        final task = action == 'code'
            ? repo.requestEmailCode('old@example.test', purpose: 'register')
            : action == 'register'
            ? repo.register(
                email: 'old@example.test',
                code: '123456',
                username: 'old-user',
                password: 'password-original',
                confirmPassword: 'password-original',
              )
            : repo.resetPassword(
                email: 'old@example.test',
                code: '123456',
                password: 'password-replaced',
                confirmPassword: 'password-replaced',
              );
        await Future<void>.delayed(Duration.zero);
        repo.configure('https://new.test/api/v1', 2200);
        repo.user = {'id': 'new-user', 'name': 'new-user', 'role': 'customer'};
        final rejected = expectLater(task, throwsException);
        result.complete(reply({'ok': true, 'demo_code': '123456'}));
        await rejected;
        expect(repo.user!['id'], 'new-user');
        expect(targets, ['old.test']);
      }
    },
  );
}
