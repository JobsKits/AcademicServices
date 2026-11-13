import 'dart:async';
import 'dart:convert';
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zhixu/Data/models.dart';
import 'package:zhixu/Shop/app.dart';
import 'package:zhixu/Shop/carousel.dart';
import 'package:zhixu/Shop/navigation.dart';
import 'package:zhixu/Shop/repository.dart';
import 'package:zhixu/Shop/strings.dart';

http.Response response(Json body, [int status = 200]) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), status);

class AccountService {
  AccountService({
    this.demo = false,
    this.rejectLogin = false,
    this.configuration,
  });

  final bool demo;
  final bool rejectLogin;
  final Future<http.Response> Function(int)? configuration;
  int configurationReads = 0;
  final requests = <http.Request>[];

  late final repository = ShopRepository(
    baseUrl: 'https://account.test/api/v1',
    demoMode: demo,
    client: MockClient((request) async {
      requests.add(request);
      final path = request.url.path;
      if (path.endsWith('/shop-config')) {
        configurationReads++;
        if (configuration != null) return configuration!(configurationReads);
        return response({
          'demo_mode': demo,
          'payment_mode': 'mock',
          if (demo)
            'demo_credentials': [
              {'role': 'admin', 'account': 'admin', 'password': '1234'},
            ],
        });
      }
      if (path.endsWith('/products')) {
        return response({'products': shopSamples});
      }
      if (path.endsWith('/shop-orders')) return response({'orders': []});
      if (path.endsWith('/banners')) {
        return response({'banners': defaultShopBanners()});
      }
      if (path.endsWith('/auth/login')) {
        if (rejectLogin) {
          return response({
            'error': {'message': 'invalid_credentials'},
          }, 401);
        }
        final body = object(jsonDecode(request.body));
        final admin = body['account'] == 'admin';
        return response({
          'token': 'fixture-session',
          'user': {
            'id': admin ? 'admin-id' : 'river-id',
            'role': admin ? 'admin' : 'customer',
            'name': admin ? 'admin' : 'river-user',
            'username': admin ? 'admin' : 'river-user',
            'avatar_url': '',
          },
        });
      }
      return response({
        'error': {'message': 'fixture route missing'},
      }, 404);
    }),
  );

  int get productReads => requests
      .where((r) => r.method == 'GET' && r.url.path.endsWith('/products'))
      .length;
}

Future<void> openShop(
  WidgetTester tester,
  ShopRepository repository, {
  bool admin = false,
  String location = '/',
  bool settle = true,
}) async {
  tester.view.physicalSize = const Size(1440, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    repository.dispose();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(
    ShopApp(
      repository: repository,
      adminMode: admin,
      initialLocation: location,
    ),
  );
  if (settle) await tester.pumpAndSettle();
}

Finder get loginEntry => find.byKey(const ValueKey('shop-login-entry'));

Future<void> openAccountDoor(WidgetTester tester) async {
  await tester.tap(loginEntry);
  await tester.pumpAndSettle();
  expect(find.byType(AlertDialog), findsOneWidget);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('visitors browse the catalogue with one settings entry', (
    tester,
  ) async {
    final service = AccountService();
    await openShop(tester, service.repository);

    expect(service.repository.user, isNull);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(ShopCarousel), findsOneWidget);
    expect(find.byType(TabBar), findsOneWidget);
    expect(loginEntry, findsOneWidget);
    expect(find.byTooltip(shopText('zh', 'settings')), findsOneWidget);
    expect(find.text(shopText('zh', 'reload')), findsNothing);
    expect(tester.widget(loginEntry), isA<FilledButton>());
    expect(service.productReads, greaterThan(0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the account door keeps login register and recovery reachable', (
    tester,
  ) async {
    final service = AccountService();
    await openShop(tester, service.repository);
    await openAccountDoor(tester);

    for (final tab in ['login', 'register', 'forgotPassword']) {
      expect(find.byKey(ValueKey('auth-tab-$tab')), findsOneWidget);
    }
    await tester.tap(find.byKey(const ValueKey('auth-tab-forgotPassword')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('auth-email')), findsOneWidget);
    expect(find.byKey(const ValueKey('auth-emailCode')), findsOneWidget);
    expect(find.byKey(const ValueKey('auth-confirmPassword')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('auth-tab-register')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('auth-username')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('auth-tab-login')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('auth-loginAccount')), findsOneWidget);
    expect(find.byKey(const ValueKey('auth-emailCode')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'guest personal navigation asks for login and cancel stays home',
    (tester) async {
      final service = AccountService();
      await openShop(tester, service.repository);
      tester.view.physicalSize = const Size(390, 900);
      await tester.pumpAndSettle();
      await tester.tap(find.text(shopText('zh', 'mine')).last);
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.byKey(const PageStorageKey('shop-profile')), findsNothing);
      await tester.tap(
        find.widgetWithText(TextButton, shopText('zh', 'cancel')),
      );
      await tester.pumpAndSettle();

      final router =
          tester.widget<MaterialApp>(find.byType(MaterialApp)).routerDelegate!
              as ShopRouterDelegate;
      expect(router.currentConfiguration.page, 0);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(ShopCarousel), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'guest profile deep link hides private cards and cancels to home',
    (tester) async {
      final service = AccountService();
      await openShop(tester, service.repository, location: '/profile');

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.byKey(const PageStorageKey('shop-profile')), findsNothing);
      expect(
        find.byKey(const ValueKey('profile-pending_payment')),
        findsNothing,
      );
      await tester.tap(
        find.widgetWithText(TextButton, shopText('zh', 'cancel')),
      );
      await tester.pumpAndSettle();

      final router =
          tester.widget<MaterialApp>(find.byType(MaterialApp)).routerDelegate!
              as ShopRouterDelegate;
      expect(router.currentConfiguration.page, 0);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(ShopCarousel), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('registration mismatch preserves the draft and visible error', (
    tester,
  ) async {
    final service = AccountService();
    await openShop(tester, service.repository);
    await openAccountDoor(tester);
    await tester.tap(find.byKey(const ValueKey('auth-tab-register')));
    await tester.pumpAndSettle();

    final draft = {
      'email': 'river@example.test',
      'emailCode': '123456',
      'username': 'river',
      'password': 'password-one',
      'confirmPassword': 'password-two',
    };
    for (final entry in draft.entries) {
      await tester.enterText(
        find.byKey(ValueKey('auth-${entry.key}')),
        entry.value,
      );
    }
    await tester.tap(find.byKey(const ValueKey('auth-submit')));
    await tester.pumpAndSettle();

    expect(
      find.textContaining(shopText('zh', 'passwordMismatch')),
      findsOneWidget,
    );
    for (final entry in draft.entries) {
      expect(
        tester
            .widget<TextField>(find.byKey(ValueKey('auth-${entry.key}')))
            .controller!
            .text,
        entry.value,
      );
    }
    expect(
      service.requests.where((r) => r.url.path.endsWith('/auth/register')),
      isEmpty,
    );
    await tester.pump(const Duration(seconds: 6));
    expect(
      find.textContaining(shopText('zh', 'passwordMismatch')),
      findsOneWidget,
    );
  });

  for (final location in ['/products', '/orders', '/banners']) {
    testWidgets(
      'formal admin deep link $location stays behind the account gate',
      (tester) async {
        final service = AccountService();
        await openShop(
          tester,
          service.repository,
          admin: true,
          location: location,
        );

        expect(service.repository.user, isNull);
        expect(find.text(shopText('zh', 'adminSignIn')), findsOneWidget);
        expect(find.byType(TabBar), findsNothing);
        expect(find.byType(NavigationBar), findsNothing);
        expect(find.text(shopText('zh', 'newProduct')), findsNothing);
        expect(find.byType(ShopCarousel), findsNothing);
        expect(
          service.requests.where((r) => r.url.path.endsWith('/auth/login')),
          isEmpty,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'explicit Demo admin opens the workspace with its sample account',
    (tester) async {
      final service = AccountService(demo: true);
      await openShop(tester, service.repository, admin: true);

      expect(service.repository.admin, isTrue);
      expect(find.text(shopText('zh', 'adminSignIn')), findsNothing);
      expect(find.text(shopText('zh', 'newProduct')), findsOneWidget);
      expect(loginEntry, findsNothing);
      final logins = service.requests
          .where((r) => r.url.path.endsWith('/auth/login'))
          .toList();
      expect(logins, hasLength(1));
      expect(jsonDecode(logins.single.body), {
        'account': 'admin',
        'password': '1234',
      });
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'late Demo discovery still opens admin after an earlier config is superseded',
    (tester) async {
      final first = Completer<http.Response>();
      final second = Completer<http.Response>();
      final service = AccountService(
        configuration: (read) async {
          if (read == 1) return first.future;
          if (read == 2) return second.future;
          return response({'demo_mode': true, 'payment_mode': 'mock'});
        },
      );
      await openShop(tester, service.repository, admin: true, settle: false);
      await tester.pump();
      expect(service.configurationReads, 2);
      expect(find.text(shopText('zh', 'newProduct')), findsNothing);

      // A newer pending request invalidates the workspace's early Demo result.
      first.complete(response({'demo_mode': true, 'payment_mode': 'mock'}));
      await tester.pump();
      expect(service.repository.user, isNull);
      expect(service.repository.demoMode, isFalse);
      expect(find.text(shopText('zh', 'adminSignIn')), findsOneWidget);
      expect(find.text(shopText('zh', 'newProduct')), findsNothing);

      second.complete(response({'demo_mode': true, 'payment_mode': 'mock'}));
      await tester.pumpAndSettle();
      expect(service.repository.demoMode, isTrue);
      expect(service.repository.admin, isTrue);
      expect(find.text(shopText('zh', 'adminSignIn')), findsNothing);
      expect(find.text(shopText('zh', 'newProduct')), findsOneWidget);
      expect(loginEntry, findsNothing);
      expect(
        service.requests.where((r) => r.url.path.endsWith('/auth/login')),
        hasLength(1),
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final demo in [false, true]) {
    testWidgets(
      'connection settings are ${demo ? 'visible in Demo' : 'hidden in formal mode'}',
      (tester) async {
        final service = AccountService(demo: demo);
        await openShop(tester, service.repository);
        await tester.tap(find.byTooltip(shopText('zh', 'settings')));
        await tester.pumpAndSettle();

        expect(find.text(shopText('zh', 'language')), findsOneWidget);
        expect(find.text(shopText('zh', 'theme')), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.widgetWithText(TextButton, shopText('zh', 'login')),
          ),
          findsNothing,
        );
        expect(find.text(shopText('zh', 'switchAccount')), findsNothing);
        expect(
          find.text(shopText('zh', 'api')),
          demo ? findsOneWidget : findsNothing,
        );
        expect(
          find.text(shopText('zh', 'timeout')),
          demo ? findsOneWidget : findsNothing,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('successful login replaces entry and refreshes current data', (
    tester,
  ) async {
    final service = AccountService();
    await openShop(tester, service.repository);
    final readsBefore = service.productReads;
    await openAccountDoor(tester);
    await tester.enterText(
      find.byKey(const ValueKey('auth-loginAccount')),
      'river@example.test',
    );
    await tester.enterText(
      find.byKey(const ValueKey('auth-password')),
      'password-one',
    );
    await tester.tap(find.byKey(const ValueKey('auth-submit')));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(loginEntry, findsNothing);
    expect(find.text('river-user'), findsWidgets);
    expect(find.byType(ClipOval), findsWidgets);
    expect(find.text(shopText('zh', 'myOrders')), findsOneWidget);
    expect(service.productReads, greaterThan(readsBefore));
    if (kIsWeb) {
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.text('river-user'),
        ),
        findsOneWidget,
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'home carousel advances automatically with dots inside lower right',
    (tester) async {
      final service = AccountService();
      await openShop(tester, service.repository);
      final pages = find.byKey(const ValueKey('shop-banner-pages'));
      final first = find.byKey(const ValueKey('carousel-indicator-0'));
      final second = find.byKey(const ValueKey('carousel-indicator-1'));

      IconData? indicator(Finder finder) => tester
          .widget<Icon>(
            find.descendant(of: finder, matching: find.byType(Icon)),
          )
          .icon;
      expect(indicator(first), Icons.circle);
      await tester.pump(const Duration(seconds: 5));
      await tester.pump(const Duration(milliseconds: 450));
      expect(indicator(second), Icons.circle);
      expect(indicator(first), Icons.radio_button_unchecked);

      final banner = tester.getRect(pages);
      final dots = tester
          .getRect(first)
          .expandToInclude(tester.getRect(second));
      expect(banner.contains(dots.topLeft), isTrue);
      expect(banner.contains(dots.bottomRight), isTrue);
      expect(dots.center.dx, greaterThan(banner.center.dx));
      expect(dots.center.dy, greaterThan(banner.center.dy));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('mouse can drag banners and autoplay resumes after leaving', (
    tester,
  ) async {
    final service = AccountService();
    await openShop(tester, service.repository);
    final pages = find.byKey(const ValueKey('shop-banner-pages'));
    final bounds = tester.getRect(pages);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    final start = Offset(bounds.left + bounds.width * .8, bounds.center.dy);
    await mouse.addPointer(location: start);
    await tester.pump();
    await mouse.down(start);
    await mouse.moveTo(
      Offset(bounds.left + bounds.width * .15, bounds.center.dy),
    );
    await tester.pump(const Duration(milliseconds: 200));
    await mouse.up();
    await tester.pumpAndSettle();

    IconData? indicator(int index) => tester
        .widget<Icon>(
          find.descendant(
            of: find.byKey(ValueKey('carousel-indicator-$index')),
            matching: find.byType(Icon),
          ),
        )
        .icon;
    expect(indicator(1), Icons.circle);
    await mouse.moveTo(const Offset(5, 5));
    await tester.pump();
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 450));
    expect(indicator(2), Icons.circle);
    await mouse.removePointer();
    expect(tester.takeException(), isNull);
  });
}
