import 'package:flutter/widgets.dart';

import 'package:zhixu/Shop/app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ShopApp(adminMode: true));
}
