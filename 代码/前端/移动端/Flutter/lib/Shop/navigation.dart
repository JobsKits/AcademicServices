import 'package:flutter/material.dart';

const shopCategories = ['graduation', 'journal', 'editing'];
const shopStatuses = [
  'all',
  'pending_payment',
  'pending_completion',
  'pending_review',
  'completed',
  'cancelled',
];

/// Only public navigation state belongs in an address; drafts stay in the form.
class ShopLocation {
  const ShopLocation({
    this.page = 0,
    this.category = 'graduation',
    this.productId,
    this.orderId,
    this.status = 'all',
  });
  final int page;
  final String category, status;
  final String? productId, orderId;

  factory ShopLocation.parse(Uri uri) {
    final parts = uri.pathSegments;
    final category = shopCategories.contains(uri.queryParameters['category'])
        ? uri.queryParameters['category']!
        : 'graduation';
    if (parts.length == 2 &&
        parts.first == 'category' &&
        shopCategories.contains(parts.last)) {
      return ShopLocation(category: parts.last);
    }
    if (parts.length == 2 && parts.first == 'products') {
      return ShopLocation(productId: parts.last, category: category);
    }
    if (parts.isNotEmpty && parts.first == 'orders') {
      return ShopLocation(
        page: 1,
        orderId: parts.length == 2 ? parts.last : null,
        status: shopStatuses.contains(uri.queryParameters['status'])
            ? uri.queryParameters['status']!
            : 'all',
      );
    }
    if (parts.length == 1 && ['profile', 'banners'].contains(parts.first)) {
      return const ShopLocation(page: 2);
    }
    return const ShopLocation();
  }

  Uri uri({bool admin = false}) {
    if (page == 1) {
      return Uri(
        pathSegments: ['', 'orders', ?orderId],
        queryParameters: status == 'all' ? null : {'status': status},
      );
    }
    if (page == 2) return Uri(path: admin ? '/banners' : '/profile');
    if (productId != null) {
      return Uri(
        pathSegments: ['', 'products', productId!],
        queryParameters: {'category': category},
      );
    }
    return Uri(path: category == 'graduation' ? '/' : '/category/$category');
  }
}

class ShopNavigation extends ChangeNotifier {
  ShopLocation location = const ShopLocation();
  void go(ShopLocation next) {
    if (next.uri().toString() == location.uri().toString()) return;
    location = next;
    notifyListeners();
  }
}

class ShopRouteParser extends RouteInformationParser<ShopLocation> {
  const ShopRouteParser({this.admin = false});
  final bool admin;
  @override
  Future<ShopLocation> parseRouteInformation(
    RouteInformation routeInformation,
  ) async => ShopLocation.parse(routeInformation.uri);
  @override
  RouteInformation restoreRouteInformation(ShopLocation configuration) =>
      RouteInformation(uri: configuration.uri(admin: admin));
}

class ShopRouterDelegate extends RouterDelegate<ShopLocation>
    with ChangeNotifier, PopNavigatorRouterDelegateMixin<ShopLocation> {
  ShopRouterDelegate(this.navigation, this.builder) {
    navigation.addListener(notifyListeners);
  }
  final ShopNavigation navigation;
  final WidgetBuilder builder;
  @override
  GlobalKey<NavigatorState> get navigatorKey => _navigatorKey;
  final _navigatorKey = GlobalKey<NavigatorState>();
  @override
  ShopLocation get currentConfiguration => navigation.location;
  @override
  Future<void> setNewRoutePath(ShopLocation configuration) async =>
      navigation.go(configuration);
  @override
  Future<bool> popRoute() async {
    if (await _navigatorKey.currentState?.maybePop() ?? false) return true;
    final here = navigation.location;
    if (here.productId != null) {
      navigation.go(ShopLocation(category: here.category));
      return true;
    }
    if (here.orderId != null) {
      navigation.go(ShopLocation(page: 1, status: here.status));
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) => Navigator(
    key: navigatorKey,
    pages: [
      MaterialPage<void>(
        key: const ValueKey('shop-workspace'),
        child: builder(context),
      ),
    ],
    onDidRemovePage: (_) {},
  );
  @override
  void dispose() {
    navigation.removeListener(notifyListeners);
    super.dispose();
  }
}
