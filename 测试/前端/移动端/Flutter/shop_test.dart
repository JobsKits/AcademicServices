import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zhixu/Data/models.dart';
import 'package:zhixu/Data/repository.dart' show ApiFailure;
import 'package:zhixu/Shop/app.dart';
import 'package:zhixu/Shop/repository.dart';
import 'package:zhixu/Shop/strings.dart';

http.Response reply(Json body, [int status = 200]) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), status);
ShopRepository offline() => ShopRepository(
  baseUrl: 'https://example.test/api/v1',
  client: MockClient((_) async => throw Exception('offline')),
);
Json orderFixture([String status = 'pending_payment']) => {
  'id': 'order-1',
  'owner_id': 'customer',
  'product_snapshot': copy(shopSamples.first),
  'amount_minor': 49800,
  'currency': 'CNY',
  'status': status,
  'fulfillment_status': 'pending',
  'version': 1,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('ten locales cover every shop interaction', () {
    expect(shopLanguages.length, 10);
    expect(shopTranslationsComplete, isTrue);
  });
  test(
    'price parsing accepts free products and exact cents within API bounds',
    () {
      expect(parseShopPrice('0'), 0);
      expect(parseShopPrice('0.01'), 1);
      expect(parseShopPrice('498.5'), 49850);
      expect(parseShopPrice('1000000000'), 100000000000);
      for (final invalid in [
        '-1',
        '1.001',
        '1e2',
        'NaN',
        '1000000000.01',
        '99999999999999999999999999999999999999999999999',
      ]) {
        expect(parseShopPrice(invalid), isNull, reason: invalid);
      }
    },
  );
  test('real empty response stays empty; failure and recovery replace demo automatically', () async {
    var fail = false;
    final repo = ShopRepository(
      baseUrl: 'https://example.test/api/v1',
      client: MockClient((_) async {
        if (fail) throw Exception('offline');
        return reply({'products': []});
      }),
    );
    await repo.refresh();
    expect(repo.products, isEmpty);
    expect(repo.demo, isFalse);
    fail = true;
    await repo.refresh();
    expect(repo.products, hasLength(9));
    expect(repo.demo, isTrue);
    fail = false;
    await repo.refresh();
    expect(repo.products, isEmpty);
    expect(repo.demo, isFalse);
    repo.dispose();
  });
  test('401 never becomes a demo login or purchase', () async {
    final repo = ShopRepository(
      baseUrl: 'https://example.test/api/v1',
      client: MockClient(
        (_) async => reply({
          'error': {'message': 'denied'},
        }, 401),
      ),
    );
    await expectLater(
      repo.login('customer', 'wrong'),
      throwsA(isA<ApiFailure>()),
    );
    expect(repo.user, isNull);
    repo.dispose();
  });
  test('offline full order cycle separates buyer and seller and preserves snapshot', () async {
    var requests = 0;
    final repo = ShopRepository(
      baseUrl: 'https://example.test/api/v1',
      client: MockClient((_) async {
        requests++;
        throw Exception('offline');
      }),
    );
    await repo.login('customer', '');
    final p = repo.products.first;
    await repo.buy(p);
    final order = repo.orders.single;
    expect(order['status'], 'pending_payment');
    await repo.action(order, 'pay', {'channel': 'wechat'});
    expect(order['status'], 'pending_completion');
    expect(order['payment']['mode'], 'mock');
    await expectLater(repo.action(order, 'accept'), throwsA(isA<ApiFailure>()));
    await repo.login('admin', '', asAdmin: true);
    expect(repo.orders, hasLength(1));
    await repo.action(repo.orders.single, 'start');
    await repo.action(repo.orders.single, 'deliver', {'text': '课程访问及交付说明'});
    await expectLater(
      repo.action(repo.orders.single, 'review', {'text': 'bad', 'rating': 5}),
      throwsA(isA<ApiFailure>()),
    );
    final edit = {
      ...copy(p),
      'name': 'changed',
      'price_minor': 1,
      'active': false,
    };
    await repo.saveProduct(edit, id: p['id'], version: p['version']);
    expect(order['product_snapshot']['name'], isNot('changed'));
    expect(order['amount_minor'], 49800);
    await repo.login('customer', '');
    await repo.action(repo.orders.single, 'accept');
    expect(repo.orders.single['status'], 'pending_review');
    await repo.action(repo.orders.single, 'review', {
      'text': '服务已完成',
      'rating': 5,
    });
    expect(repo.orders.single['status'], 'completed');
    expect(requests, greaterThan(12));
    repo.dispose();
  });
  test('real write timeout keeps one key and retry body without creating a local success', () async {
    final sent = <http.Request>[];
    var retry = false;
    final repo = ShopRepository(
      baseUrl: 'https://example.test/api/v1',
      client: MockClient((r) async {
        if (r.url.path.endsWith('/auth/login'))
          return reply({
            'token': 'token',
            'user': {'id': 'customer', 'role': 'customer'},
          });
        if (r.url.path.endsWith('/products'))
          return reply({'products': shopSamples});
        if (r.method == 'GET') return reply({'orders': []});
        sent.add(r);
        if (!retry) throw Exception('lost result');
        return reply({'order': orderFixture()});
      }),
    );
    await repo.login('customer', 'x');
    await expectLater(
      repo.buy(repo.products.first),
      throwsA(isA<ApiFailure>()),
    );
    expect(repo.orders, isEmpty);
    expect(repo.pending, isNotNull);
    retry = true;
    await repo.retryPending();
    expect(sent, hasLength(2));
    expect(
      sent.first.headers['Idempotency-Key'],
      sent.last.headers['Idempotency-Key'],
    );
    expect(sent.first.body, sent.last.body);
    expect(repo.orders.single['id'], 'order-1');
    expect(repo.pending, isNull);
    repo.dispose();
  });
  test('product update sends only editable fields and version, preserving strict API decoding', () async {
    Json? sent;
    final repo = ShopRepository(
      baseUrl: 'https://example.test/api/v1',
      client: MockClient((r) async {
        if (r.method == 'PUT') {
          sent = object(jsonDecode(r.body));
          return reply({'product': shopSamples.first});
        }
        return reply({'products': shopSamples, 'orders': []});
      }),
    );
    repo.user = {'id': 'admin', 'role': 'admin'};
    repo.token = 'admin';
    repo.demo = false;
    await repo.saveProduct(
      {...copy(shopSamples.first), 'created_at': 'date', 'updated_at': 'date'},
      id: 'p',
      version: 1,
    );
    expect(sent!['expected_version'], 1);
    expect(sent!.containsKey('created_at'), isFalse);
    expect(sent!.containsKey('id'), isFalse);
    repo.dispose();
  });
  test(
    'concurrent checkout is blocked before two keys can be submitted',
    () async {
      final response = Completer<http.Response>();
      var writes = 0;
      final repo = ShopRepository(
        baseUrl: 'https://example.test/api/v1',
        client: MockClient((_) async {
          writes++;
          return response.future;
        }),
      );
      repo.user = {'id': 'customer', 'role': 'customer'};
      repo.token = 'customer';
      repo.demo = false;
      final first = repo.buy(repo.products.first);
      await expectLater(
        repo.buy(repo.products.first),
        throwsA(isA<ApiFailure>()),
      );
      response.complete(reply({'order': orderFixture()}));
      await first;
      expect(writes, 1);
      repo.dispose();
    },
  );
  for (final width in [320.0, 390.0, 934.0, 1440.0]) {
    testWidgets('mall category and detail responsive at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = offline();
      await tester.pumpWidget(ShopApp(repository: repo));
      await tester.pumpAndSettle();
      expect(find.text('把成长，放在心上。'), findsOneWidget);
      await tester.tap(find.text('编译').first);
      await tester.pumpAndSettle();
      expect(find.text('学术翻译'), findsOneWidget);
      expect(find.text('论文提纲'), findsNothing);
      await tester.ensureVisible(find.text('查看详情').first);
      await tester.tap(find.text('查看详情').first);
      await tester.pumpAndSettle();
      expect(find.text('学术翻译'), findsOneWidget);
      expect(find.text('服务内容'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      repo.dispose();
    });
  }
  testWidgets(
    'checkout close does not pay, explicit channel confirmation pays once',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = offline();
      await repo.login('customer', '');
      await tester.pumpWidget(ShopApp(repository: repo));
      await tester.pumpAndSettle();
      await tester.tap(find.text('查看详情').first);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('立即购买'));
      await tester.tap(find.text('立即购买'));
      await tester.pumpAndSettle();
      expect(find.text('确认模拟付款'), findsOneWidget);
      await tester.tap(find.text('取消').last);
      await tester.pumpAndSettle();
      expect(repo.orders.single['status'], 'pending_payment');
      await tester.ensureVisible(find.text('收银台'));
      await tester.tap(find.text('收银台'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('微信支付'));
      await tester.tap(find.text('确认模拟付款'));
      await tester.pumpAndSettle();
      expect(repo.orders.single['payment']['channel'], 'wechat');
      expect(repo.orders.single['status'], 'pending_completion');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      repo.dispose();
    },
  );
  testWidgets(
    'admin opens product editor with all required inventory controls',
    (tester) async {
      tester.view.physicalSize = const Size(390, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = offline();
      await repo.login('admin', '', asAdmin: true);
      await tester.pumpWidget(ShopApp(adminMode: true, repository: repo));
      await tester.pumpAndSettle();
      await tester.tap(find.text('新增商品'));
      await tester.pumpAndSettle();
      expect(find.text('价格（元）'), findsOneWidget);
      await tester.ensureVisible(find.text('有货'));
      expect(find.text('上架'), findsOneWidget);
      expect(find.text('有货'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('取消').last);
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      repo.dispose();
    },
  );
  testWidgets('editing zero price and multiline section preserves content', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = offline();
    await repo.login('admin', '', asAdmin: true);
    final p = copy(shopSamples.first);
    p['price_minor'] = 0;
    p['sections'] = [
      {'title': '独立标题', 'body': '第一行\n第二行|正文内容'},
    ];
    repo.products = [p];
    await tester.pumpWidget(ShopApp(adminMode: true, repository: repo));
    await tester.pumpAndSettle();
    await tester.tap(find.text('查看详情'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('编辑商品'));
    await tester.tap(find.text('编辑商品'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存').last);
    await tester.pumpAndSettle();
    expect(repo.products.single['price_minor'], 0);
    expect(repo.products.single['version'], 2);
    expect(repo.products.single['sections'][0]['body'], '第一行\n第二行|正文内容');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    repo.dispose();
  });
  for (final language in shopLanguages.keys) {
    testWidgets('locale $language and dark appearance restore', (tester) async {
      SharedPreferences.setMockInitialValues({
        'shop-language': language,
        'shop-theme': 'dark',
      });
      final repo = offline();
      await tester.pumpWidget(ShopApp(repository: repo));
      await tester.pumpAndSettle();
      expect(find.text(shopText(language, 'hero')), findsOneWidget);
      final theme = Theme.of(tester.element(find.byType(Scaffold)));
      expect(theme.brightness, Brightness.dark);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      repo.dispose();
    });
  }
  test('warm light and dark main/subtitle text passes 4.5 contrast', () {
    expect(
      shopTheme(Brightness.light).textTheme.bodyMedium!.fontFamilyFallback,
      contains('NotoSansCJKsc'),
    );
    expect(
      shopTheme(
        Brightness.light,
        packaged: true,
      ).textTheme.bodyMedium!.fontFamilyFallback,
      contains('packages/zhixu/NotoSansCJKsc'),
    );
    expect(
      shopTheme(
        Brightness.light,
        packaged: true,
      ).textTheme.bodyMedium!.fontFamilyFallback,
      contains('packages/zhixu/NotoSerifTibetan'),
    );
    for (final brightness in Brightness.values) {
      final c = shopTheme(brightness).colorScheme;
      for (final pair in [
        (c.onSurface, c.surface),
        (c.onSurfaceVariant, c.surface),
        (c.onPrimary, c.primary),
      ]) {
        final a = pair.$1.computeLuminance(), b = pair.$2.computeLuminance();
        expect(
          ((a > b ? a : b) + 0.05) / ((a > b ? b : a) + 0.05),
          greaterThanOrEqualTo(4.5),
        );
      }
    }
  });
}
