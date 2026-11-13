import 'dart:async';
import 'dart:convert';
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zhixu/Data/models.dart';
import 'package:zhixu/Data/repository.dart' show ApiFailure;
import 'package:zhixu/Shop/app.dart';
import 'package:zhixu/Shop/repository.dart';
import 'package:zhixu/Shop/strings.dart';
import 'package:zhixu/Shop/carousel.dart';
import 'package:zhixu/Shop/navigation.dart';
import 'package:zhixu/Shop/browser_link_web.dart' as browser_link;
import 'package:zhixu/Ui/demo_login_credentials.dart';

http.Response reply(Json body, [int status = 200]) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), status);
ShopRepository offline() => ShopRepository(
  baseUrl: 'https://example.test/api/v1',
  demoMode: true,
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
  test('public routes round trip without private or unknown query data', () {
    final parser = ShopLocation.parse(
      Uri.parse(
        '/products/editing-translation?category=editing&contact=secret&requirements=private',
      ),
    );
    expect(parser.productId, 'editing-translation');
    expect(parser.category, 'editing');
    expect(
      parser.uri().toString(),
      '/products/editing-translation?category=editing',
    );
    final order = ShopLocation.parse(
      Uri.parse('/orders/order-1?status=pending_review&password=secret'),
    );
    expect(order.uri().toString(), '/orders/order-1?status=pending_review');
    expect(
      ShopLocation.parse(Uri.parse('/orders?status=invalid')).status,
      'all',
    );
    expect(
      ShopLocation.parse(Uri.parse('/category/journal')).category,
      'journal',
    );
    expect(ShopLocation.parse(Uri.parse('/profile')).page, 2);
    expect(const ShopLocation(page: 2).uri(admin: true).path, '/banners');
  });
  testWidgets(
    'deep links restore details and browser route changes restore filters and profile',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = offline();
      await repo.login('customer', 'demo-customer');
      await tester.pumpWidget(
        ShopApp(
          repository: repo,
          initialLocation:
              '/products/demo-editing-translation?category=editing',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('学术翻译'), findsOneWidget);
      expect(find.text('服务内容'), findsOneWidget);
      final delegate =
          tester.widget<MaterialApp>(find.byType(MaterialApp)).routerDelegate!
              as ShopRouterDelegate;
      expect(
        delegate.currentConfiguration.productId,
        'demo-editing-translation',
      );
      await delegate.setNewRoutePath(
        const ShopLocation(page: 1, status: 'completed'),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '已完成'))
            .selected,
        isTrue,
      );
      await delegate.setNewRoutePath(const ShopLocation(page: 2));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('profile-pending_payment')),
        findsOneWidget,
      );
      await delegate.setNewRoutePath(
        const ShopLocation(
          productId: 'demo-editing-translation',
          category: 'editing',
        ),
      );
      await tester.pumpAndSettle();
      await delegate.popRoute();
      await tester.pumpAndSettle();
      expect(
        find.byKey(const PageStorageKey('shop-category-pages')),
        findsOneWidget,
      );
      expect(tester.widget<TabBar>(find.byType(TabBar)).controller!.index, 2);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      repo.dispose();
    },
  );
  testWidgets(
    'purchase rejection keeps the complete requirement draft and persistent recovery',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var writes = 0;
      final repo = ShopRepository(
        baseUrl: 'https://example.test/api/v1',
        client: MockClient((request) async {
          if (request.method == 'POST' &&
              request.url.path.endsWith('/shop-orders')) {
            writes++;
            return reply({
              'error': {'message': 'version'},
            }, 409);
          }
          if (request.url.path.endsWith('/products'))
            return reply({'products': shopSamples});
          if (request.url.path.endsWith('/shop-orders'))
            return reply({'orders': []});
          if (request.url.path.endsWith('/banners'))
            return reply({'banners': []});
          return reply({'demo_mode': false});
        }),
      );
      repo.user = {'id': 'customer', 'role': 'customer', 'name': 'customer'};
      repo.token = 'test-token';
      repo.demo = false;
      await tester.pumpWidget(
        ShopApp(
          repository: repo,
          initialLocation: '/products/demo-graduation-outline',
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('立即购买'));
      await tester.tap(find.text('立即购买'));
      await tester.pumpAndSettle();
      final fields = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextFormField),
      );
      for (var i = 0; i < 3; i++)
        await tester.enterText(fields.at(i), 'private draft $i');
      await tester.tap(find.text('保存').last);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        find.byKey(const ValueKey('shop-persistent-error')),
        findsOneWidget,
      );
      for (var i = 0; i < 3; i++)
        expect(
          tester.widget<TextFormField>(fields.at(i)).controller?.text ??
              tester
                  .widget<EditableText>(
                    find.descendant(
                      of: fields.at(i),
                      matching: find.byType(EditableText),
                    ),
                  )
                  .controller
                  .text,
          'private draft $i',
        );
      await tester.pump(const Duration(seconds: 6));
      expect(
        find.byKey(const ValueKey('shop-persistent-error')),
        findsOneWidget,
      );
      expect(repo.orders, isEmpty);
      expect(writes, 1);
      final delegate =
          tester.widget<MaterialApp>(find.byType(MaterialApp)).routerDelegate!
              as ShopRouterDelegate;
      expect(
        delegate.currentConfiguration.uri().toString(),
        isNot(contains('private')),
      );
      await tester.tap(find.text('保存').last);
      await tester.pumpAndSettle();
      expect(writes, 2);
      await tester.tap(find.text('取消').last);
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      repo.dispose();
    },
  );
  testWidgets(
    'login returns to the purchase confirmation without submitting an order',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = offline();
      await tester.pumpWidget(
        ShopApp(
          repository: repo,
          initialLocation: '/products/demo-graduation-outline',
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('立即购买'));
      await tester.tap(find.text('立即购买'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('auth-loginAccount')),
        'customer',
      );
      await tester.enterText(
        find.byKey(const ValueKey('auth-password')),
        'demo-customer',
      );
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(FilledButton, '登录'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextFormField, '订单需求'), findsOneWidget);
      expect(repo.orders, isEmpty);
      await tester.tap(find.text('取消').last);
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      repo.dispose();
    },
  );
  test('a failed refresh keeps live orders and products until a successful replacement', () async {
    var fail = false;
    final product = copy(shopSamples.first)..['id'] = 'real-product';
    final order = orderFixture()..['owner_id'] = 'customer';
    final repo = ShopRepository(
      baseUrl: 'https://example.test/api/v1',
      client: MockClient((request) async {
        if (fail) throw Exception('network unavailable');
        if (request.url.path.endsWith('/products'))
          return reply({
            'products': [product],
          });
        if (request.url.path.endsWith('/shop-orders'))
          return reply({
            'orders': [order],
          });
        if (request.url.path.endsWith('/banners'))
          return reply({'banners': []});
        return reply({'demo_mode': false});
      }),
    );
    repo.user = {'id': 'customer', 'role': 'customer'};
    repo.token = 'test';
    await repo.refresh();
    fail = true;
    await repo.refresh();
    expect(repo.products.single['id'], 'real-product');
    expect(repo.orders.single['id'], 'order-1');
    expect(repo.demo, isFalse);
    expect(repo.refreshError, 'updateFailed');
    fail = false;
    await repo.refresh();
    expect(repo.refreshError, isNull);
    repo.dispose();
  });
  testWidgets(
    'German two hundred percent text keeps requirements checkout and settings usable',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      SharedPreferences.setMockInitialValues({'shop-language': 'de'});
      final repo = offline();
      await repo.login('customer', 'demo-customer');
      await repo.buy(repo.products.first);
      final order = repo.orders.single;
      await tester.pumpWidget(
        ShopApp(repository: repo, initialLocation: '/orders/${order['id']}'),
      );
      await tester.pumpAndSettle();
      Future<void> reach(String key) async {
        final target = find.text(shopText('de', key)).last;
        await tester.scrollUntilVisible(
          target,
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.ensureVisible(target);
        await tester.pumpAndSettle();
        await tester.tap(target);
        await tester.pumpAndSettle();
      }

      await reach('editRequirements');
      expect(
        find.widgetWithText(TextFormField, shopText('de', 'requirements')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.text(shopText('de', 'cancel')).last);
      await tester.pumpAndSettle();
      await reach('checkout');
      expect(find.text(shopText('de', 'confirmPay')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text(shopText('de', 'cancel')).last);
      await tester.pumpAndSettle();
      final delegate =
          tester.widget<MaterialApp>(find.byType(MaterialApp)).routerDelegate!
              as ShopRouterDelegate;
      delegate.navigation.go(const ShopLocation(page: 2));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byTooltip(shopText('de', 'settings')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byTooltip(shopText('de', 'settings')));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text(shopText('de', 'cancel')).last);
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      repo.dispose();
    },
  );
  testWidgets(
    'category deep link restores its page and a tab adds only one navigation state',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = offline();
      await tester.pumpWidget(
        ShopApp(repository: repo, initialLocation: '/category/journal'),
      );
      await tester.pumpAndSettle();
      expect(tester.widget<TabBar>(find.byType(TabBar)).controller!.index, 1);
      expect(
        tester
            .widget<PageView>(
              find.byKey(const PageStorageKey('shop-category-pages')),
            )
            .controller!
            .page,
        1,
      );
      final delegate =
          tester.widget<MaterialApp>(find.byType(MaterialApp)).routerDelegate!
              as ShopRouterDelegate;
      final visits = <String>[];
      delegate.navigation.addListener(
        () => visits.add(delegate.currentConfiguration.uri().toString()),
      );
      await tester.tap(find.text('编译').first);
      await tester.pumpAndSettle();
      expect(visits, ['/category/editing']);
      expect(tester.widget<TabBar>(find.byType(TabBar)).controller!.index, 2);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      repo.dispose();
    },
  );
  testWidgets(
    'browser link keyboard focus reveals an offscreen target and Enter navigates once',
    (tester) async {
      var navigations = 0;
      final scroll = ScrollController();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              controller: scroll,
              child: Column(
                children: [
                  const SizedBox(height: 1000),
                  browser_link.browserShopLink(
                    route: Uri.parse('/products/p'),
                    label: 'Keyboard product',
                    child: TextButton(
                      onPressed: () {},
                      child: const Text('Keyboard product'),
                    ),
                    onNavigate: () => navigations++,
                    focusColor: Colors.brown,
                  ),
                  const SizedBox(height: 100),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(scroll.offset, greaterThan(0));
      expect(find.text('Keyboard product').hitTestable(), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(navigations, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      scroll.dispose();
    },
  );
  testWidgets(
    'mobile destinations preserve order status and catalogue category independently',
    (tester) async {
      tester.view.physicalSize = const Size(390, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = offline();
      await repo.login('customer', 'demo-customer');
      await tester.pumpWidget(
        ShopApp(
          repository: repo,
          initialLocation: '/orders?status=pending_completion',
        ),
      );
      await tester.pumpAndSettle();
      Future<void> tab(String label) async {
        await tester.tap(
          find.descendant(
            of: find.byType(NavigationBar),
            matching: find.text(label),
          ),
        );
        await tester.pumpAndSettle();
      }

      await tab('首页');
      await tester.tap(find.text('编译').first);
      await tester.pumpAndSettle();
      await tab('我的订单');
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '待完成'))
            .selected,
        isTrue,
      );
      await tab('首页');
      expect(tester.widget<TabBar>(find.byType(TabBar)).controller!.index, 2);
      await tab('我的订单');
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '待完成'))
            .selected,
        isTrue,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      repo.dispose();
    },
  );
  test('ten locales cover every shop interaction', () {
    expect(shopLanguages.length, 10);
    expect(shopTranslationsComplete, isTrue);
  });
  test(
    'server demo configuration exposes current credentials only in demo mode',
    () async {
      var mode = true;
      final repo = ShopRepository(
        baseUrl: 'https://example.test/api/v1',
        client: MockClient(
          (_) async => reply({
            'demo_mode': mode,
            if (mode)
              'demo_credentials': [
                {
                  'role': 'customer',
                  'account': 'actual-client',
                  'password': 'dynamic-test-password',
                },
              ],
          }),
        ),
      );
      await repo.loadConfiguration();
      expect(repo.demoCredentials.single['account'], 'actual-client');
      mode = false;
      await repo.loadConfiguration();
      expect(repo.demoCredentials, isEmpty);
      repo.dispose();
    },
  );
  test(
    'requirements can change before merchant acceptance and lock afterwards',
    () async {
      final repo = offline();
      await repo.login('customer', 'demo-customer');
      await repo.buy(repo.products.first, {
        'requirements': 'initial',
        'contact': 'buyer-contact',
        'delivery_requirements': 'PDF',
      });
      final order = repo.orders.single;
      final amount = order['amount_minor'];
      await repo.action(order, 'edit', {
        'requirements': 'revised',
        'contact': 'new-contact',
        'delivery_requirements': 'video',
      });
      expect(order['requirements'], 'revised');
      expect(order['amount_minor'], amount);
      await repo.action(order, 'pay', {'channel': 'alipay'});
      await repo.action(order, 'edit', {
        'requirements': 'paid but not accepted',
        'contact': 'new',
        'delivery_requirements': 'PDF',
      });
      await repo.login('admin', '1234', asAdmin: true);
      await repo.action(repo.orders.single, 'start');
      expect(shopOrderEditable(order), isFalse);
      expect(order['accepted_at'], isNotEmpty);
      await repo.login('customer', 'demo-customer');
      await expectLater(
        repo.action(repo.orders.single, 'edit', {'requirements': 'forbidden'}),
        throwsA(isA<ApiFailure>()),
      );
      expect(order['requirements'], 'paid but not accepted');
      repo.dispose();
    },
  );
  test('successful empty banner configuration respects explicit hiding and writes support receipts', () async {
    final repo = ShopRepository(
      baseUrl: 'https://example.test/api/v1',
      client: MockClient((r) async {
        if (r.url.path.contains('/shop-operations/'))
          return reply({
            'banner': {
              'id': 'b',
              'title': 'saved',
              'image': 'https://example.test/image.png',
              'active': true,
              'sort_order': 0,
              'version': 1,
              'target_url': '',
            },
          });
        return reply({'banners': []});
      }),
    );
    await repo.loadBanners();
    expect(repo.banners, isEmpty);
    expect(repo.visibleBanners, isEmpty);
    repo.user = {'id': 'admin', 'role': 'admin'};
    repo.pending = ShopPending(
      '/admin/banners',
      'POST',
      {},
      'saved-banner-key',
    );
    await repo.reconcilePending();
    expect(repo.banners.single['title'], 'saved');
    expect(repo.pending, isNull);
    repo.dispose();
  });
  testWidgets(
    'dynamic credential copy preserves tips and never invents defaults',
    (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData')
            copied = call.arguments['text'];
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: DemoLoginCredentials(
              credentials: [
                {
                  'role': 'customer',
                  'account': 'current-buyer',
                  'password': 'configured-password',
                },
                {
                  'role': 'admin',
                  'account': 'current-merchant',
                  'password': 'merchant-password',
                },
              ],
            ),
          ),
        ),
      );
      expect(find.text('demo-customer'), findsNothing);
      expect(find.text('current-merchant'), findsOneWidget);
      expect(find.text('merchant-password'), findsOneWidget);
      expect(find.text('复制'), findsNWidgets(4));
      await tester.tap(
        find.byKey(const ValueKey('copy-demo-customer-password')),
      );
      await tester.pumpAndSettle();
      expect(copied, 'configured-password');
      expect(find.text('已复制'), findsNWidgets(2));
      expect(find.byKey(const ValueKey('demo-copy-tip')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('copy-demo-admin-account')));
      await tester.pumpAndSettle();
      expect(copied, 'current-merchant');
      expect(find.text('已复制'), findsNWidgets(2));
      expect(find.byKey(const ValueKey('demo-copy-tip')), findsOneWidget);
    },
  );
  testWidgets('clipboard failure also opens a root overlay tip', (
    tester,
  ) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData')
          throw PlatformException(code: 'unavailable');
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DemoLoginCredentials(
            credentials: [
              {
                'role': 'customer',
                'account': 'configured',
                'password': 'configured-password',
              },
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('copy-demo-customer-account')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('demo-copy-tip')), findsOneWidget);
    expect(find.text('复制失败，请选中文本复制。'), findsNWidgets(2));
    await tester.pump(const Duration(seconds: 3));
    expect(find.byKey(const ValueKey('demo-copy-tip')), findsNothing);
    expect(find.text('复制失败，请选中文本复制。'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'copy tip is above the dialog, expires and is removed with its owner',
    (tester) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (_) async => null,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (context) => AlertDialog(
                    content: const DemoLoginCredentials(
                      credentials: [
                        {
                          'role': 'customer',
                          'account': 'configured',
                          'password': 'configured-password',
                        },
                      ],
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Close'),
                      ),
                    ],
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      final copy = find.byKey(const ValueKey('copy-demo-customer-account')),
          tip = find.byKey(const ValueKey('demo-copy-tip'));
      await tester.tap(copy);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(tip, findsOneWidget);
      expect(
        find.descendant(of: find.byType(AlertDialog), matching: tip),
        findsNothing,
      );
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(copy);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 1500));
      expect(tip, findsOneWidget);
      await tester.pump(const Duration(milliseconds: 600));
      expect(tip, findsNothing);
      await tester.tap(copy);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(tip, findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(tip, findsNothing);
      await tester.pump(const Duration(seconds: 3));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'connected server clearly identifies demo mode and clears it in formal mode',
    (tester) async {
      var demoMode = true;
      final repo = ShopRepository(
        baseUrl: 'https://example.test/api/v1',
        client: MockClient((request) async {
          if (request.url.path.endsWith('/shop-config'))
            return reply({'demo_mode': demoMode, 'payment_mode': 'mock'});
          if (request.url.path.endsWith('/banners'))
            return reply({'banners': []});
          return reply({'products': shopSamples});
        }),
      );
      await tester.pumpWidget(ShopApp(repository: repo));
      await tester.pumpAndSettle();
      expect(find.text('Demo · 服务端已连接'), findsOneWidget);
      demoMode = false;
      await repo.loadConfiguration();
      await tester.pumpAndSettle();
      expect(find.text('Demo · 服务端已连接'), findsNothing);
      expect(find.text('服务端已连接'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      repo.dispose();
    },
  );
  testWidgets(
    'home tabs and horizontal pages stay synchronized; profile shortcuts filter orders',
    (tester) async {
      tester.view.physicalSize = const Size(390, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = offline();
      await repo.login('customer', 'demo-customer');
      await repo.buy(repo.products.first);
      await repo.action(repo.orders.single, 'pay', {'channel': 'wechat'});
      await tester.pumpWidget(ShopApp(repository: repo));
      await tester.pumpAndSettle();
      expect(find.text('01'), findsNothing);
      expect(find.byIcon(Icons.storefront), findsOneWidget);
      await tester.drag(
        find.byKey(const PageStorageKey('shop-category-pages')),
        const Offset(-360, 0),
      );
      await tester.pumpAndSettle();
      expect(tester.widget<TabBar>(find.byType(TabBar)).controller!.index, 1);
      await tester.tap(find.text('编译').first);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<PageView>(
              find.byKey(const PageStorageKey('shop-category-pages')),
            )
            .controller!
            .page,
        closeTo(2, .01),
      );
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('customer'),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('profile-pending_completion')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey('profile-pending_completion')),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '待完成'))
            .selected,
        isTrue,
      );
      expect(find.text('¥498.00'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      repo.dispose();
    },
  );
  testWidgets('carousel automatically advances and respects reduced motion', (
    tester,
  ) async {
    for (final reduced in [false, true]) {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: const Size(800, 600),
              disableAnimations: reduced,
            ),
            child: Scaffold(
              body: ShopCarousel(
                banners: defaultShopBanners(),
                t: (k) => shopText('zh', k),
                baseUrl: 'https://example.test',
                onOpen: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final start = tester
          .widget<PageView>(find.byKey(const ValueKey('shop-banner-pages')))
          .controller!
          .page!;
      await tester.pump(const Duration(seconds: 5));
      await tester.pump(const Duration(milliseconds: 450));
      expect(
        tester
            .widget<PageView>(find.byKey(const ValueKey('shop-banner-pages')))
            .controller!
            .page,
        closeTo(start + (reduced ? 0 : 1), .01),
      );
      await tester.pumpWidget(const SizedBox());
    }
  });
  testWidgets(
    'carousel single card is static and invalid links are not actionable',
    (tester) async {
      var opens = 0;
      for (final target in ['', 'javascript:alert(1)']) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ShopCarousel(
                banners: [
                  {...defaultShopBanners().first, 'target_url': target},
                ],
                t: (k) => shopText('zh', k),
                baseUrl: 'https://example.test',
                onOpen: (_) => opens++,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(PageView), findsNothing);
        expect(find.byType(IconButton), findsNothing);
        final card = tester.widget<InkWell>(find.byType(InkWell));
        expect(card.onTap, isNull);
        expect(card.mouseCursor, SystemMouseCursors.basic);
        await tester.pump(const Duration(seconds: 20));
        expect(opens, 0);
        await tester.pumpWidget(const SizedBox());
      }
    },
  );
  testWidgets(
    'carousel indicators select cards and restart one full interval after drag',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ShopCarousel(
              banners: defaultShopBanners(),
              t: (k) => shopText('zh', k),
              baseUrl: 'https://example.test',
              onOpen: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      double page() => tester
          .widget<PageView>(find.byKey(const ValueKey('shop-banner-pages')))
          .controller!
          .page!;
      final start = page();
      expect(find.byIcon(Icons.circle), findsOneWidget);
      expect(find.byIcon(Icons.radio_button_unchecked), findsNWidgets(2));
      expect(find.text('1 / 3'), findsNothing);
      expect(find.byIcon(Icons.pause), findsNothing);
      expect(find.byIcon(Icons.play_arrow), findsNothing);
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(seconds: 5));
        await tester.pump(const Duration(milliseconds: 450));
        expect(page(), closeTo(start + i + 1, .01));
      }
      await tester.tap(find.byKey(const ValueKey('carousel-indicator-2')));
      await tester.pumpAndSettle();
      expect(page(), closeTo(start + 5, .01));
      final chosen = page();
      await tester.pump(const Duration(milliseconds: 4800));
      expect(page(), closeTo(chosen, .01));
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump(const Duration(milliseconds: 450));
      expect(page(), closeTo(chosen + 1, .01));
      await tester.drag(
        find.byKey(const ValueKey('shop-banner-pages')),
        const Offset(-650, 0),
      );
      await tester.pumpAndSettle();
      final dragged = page();
      await tester.pump(const Duration(milliseconds: 4800));
      expect(page(), closeTo(dragged, .01));
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump(const Duration(milliseconds: 450));
      expect(page(), closeTo(dragged + 1, .01));
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('carousel pauses for keyboard focus without resuming on blur', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ShopCarousel(
            banners: defaultShopBanners(),
            t: (k) => shopText('zh', k),
            baseUrl: 'https://example.test',
            onOpen: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    double page() => tester
        .widget<PageView>(find.byKey(const ValueKey('shop-banner-pages')))
        .controller!
        .page!;
    final start = page();
    final focus = tester
        .widget<Focus>(find.byKey(const ValueKey('shop-carousel-focus')))
        .focusNode!;
    focus.requestFocus();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 7));
    expect(page(), closeTo(start, .01));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(page(), closeTo(start + 1, .01));
    focus.unfocus();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 7));
    expect(page(), closeTo(start + 1, .01));
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('carousel hover pauses and exit restarts one complete interval', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ShopCarousel(
            banners: defaultShopBanners(),
            t: (k) => shopText('zh', k),
            baseUrl: 'https://example.test',
            onOpen: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    double page() => tester
        .widget<PageView>(find.byKey(const ValueKey('shop-banner-pages')))
        .controller!
        .page!;
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(799, 599));
    await mouse.moveTo(
      tester.getCenter(find.byKey(const ValueKey('shop-banner-pages'))),
    );
    await tester.pumpAndSettle();
    final hovered = page();
    await tester.pump(const Duration(seconds: 7));
    expect(page(), closeTo(hovered, .01));
    await mouse.moveTo(const Offset(799, 599));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 4800));
    expect(page(), closeTo(hovered, .01));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 450));
    expect(page(), closeTo(hovered + 1, .01));
    await mouse.removePointer();
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'carousel timer stops offscreen and in background and restarts once',
    (tester) async {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      addTearDown(
        () => tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              controller: scroll,
              child: Column(
                children: [
                  ShopCarousel(
                    banners: defaultShopBanners(),
                    t: (k) => shopText('zh', k),
                    baseUrl: 'https://example.test',
                    onOpen: (_) {},
                  ),
                  const SizedBox(height: 2000),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      double page() => tester
          .widget<PageView>(find.byKey(const ValueKey('shop-banner-pages')))
          .controller!
          .page!;
      final start = page();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(seconds: 8));
      expect(page(), closeTo(start, .01));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump(const Duration(seconds: 5));
      await tester.pump(const Duration(milliseconds: 450));
      expect(page(), closeTo(start + 1, .01));
      scroll.jumpTo(1000);
      await tester.pumpAndSettle();
      final hidden = page();
      await tester.pump(const Duration(seconds: 8));
      expect(page(), closeTo(hidden, .01));
      scroll.jumpTo(0);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 5));
      await tester.pump(const Duration(milliseconds: 450));
      expect(page(), closeTo(hidden + 1, .01));
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 8));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'merchant banner editor persists image URL, optional link and order',
    (tester) async {
      tester.view.physicalSize = const Size(390, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = offline();
      await repo.login('admin', '1234', asAdmin: true);
      await tester.pumpWidget(ShopApp(adminMode: true, repository: repo));
      await tester.pumpAndSettle();
      await tester.tap(find.text('首页轮播'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('新增轮播'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, '轮播标题'),
        'New course',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, '图片地址'),
        'Assets/Banners/graduation.png',
      );
      await tester.ensureVisible(
        find.widgetWithText(TextFormField, '跳转地址（可选）'),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, '跳转地址（可选）'),
        'https://example.test/help',
      );
      await tester.tap(find.text('保存').last);
      await tester.pumpAndSettle();
      expect(repo.banners.first['title'], 'New course');
      expect(repo.banners.first['target_url'], 'https://example.test/help');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      repo.dispose();
    },
  );
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
  test(
    'real empty response and previous live content survive failed updates',
    () async {
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
      expect(repo.products, isEmpty);
      expect(repo.demo, isFalse);
      expect(repo.refreshError, 'updateFailed');
      fail = false;
      await repo.refresh();
      expect(repo.products, isEmpty);
      expect(repo.demo, isFalse);
      expect(repo.refreshError, isNull);
      repo.dispose();
    },
  );
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
      demoMode: true,
      client: MockClient((_) async {
        requests++;
        throw Exception('offline');
      }),
    );
    await repo.login('customer', 'demo-customer');
    final p = repo.products.first;
    await repo.buy(p);
    final order = repo.orders.single;
    expect(order['status'], 'pending_payment');
    await repo.action(order, 'pay', {'channel': 'wechat'});
    expect(order['status'], 'pending_completion');
    expect(order['payment']['mode'], 'mock');
    await expectLater(repo.action(order, 'accept'), throwsA(isA<ApiFailure>()));
    await repo.login('admin', '1234', asAdmin: true);
    expect(repo.orders, hasLength(1));
    await repo.action(repo.orders.single, 'start');
    final acceptedAt = repo.orders.single['accepted_at'];
    await repo.action(repo.orders.single, 'deliver', {'text': '课程访问及交付说明'});
    expect(repo.orders.single['accepted_at'], acceptedAt);
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
    await repo.login('customer', 'demo-customer');
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
      await tester.pumpAndSettle();
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
      await repo.login('customer', 'demo-customer');
      await tester.pumpWidget(ShopApp(repository: repo));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('查看详情').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('查看详情').first);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('立即购买'));
      await tester.tap(find.text('立即购买'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextFormField, '订单需求'), findsOneWidget);
      await tester.tap(find.text('保存').last);
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
      await repo.login('admin', '1234', asAdmin: true);
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
    await repo.login('admin', '1234', asAdmin: true);
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
      shopTheme(Brightness.light).textTheme.bodyMedium!.fontFamily,
      'NotoSansCJKsc',
    );
    expect(
      shopTheme(
        Brightness.light,
        packaged: true,
      ).textTheme.bodyMedium!.fontFamily,
      'packages/zhixu/NotoSansCJKsc',
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
