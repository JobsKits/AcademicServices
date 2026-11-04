import 'package:flutter/widgets.dart';

import 'package:zhixu/Ui/app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ZhixuApp(adminMode: true));
}
