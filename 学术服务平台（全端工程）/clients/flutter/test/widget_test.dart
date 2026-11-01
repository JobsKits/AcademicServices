import 'dart:convert';
import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zhixu/data/models.dart';
import 'package:zhixu/data/repository.dart';
import 'package:zhixu/ui/app.dart';
import 'package:zhixu/ui/theme.dart';
import 'package:zhixu/ui/actions.dart';

void main() {
  testWidgets('fold feature keeps controls inside one usable pane', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(934, 678);
    tester.view.devicePixelRatio = 1;
    tester.view.displayFeatures = [
      DisplayFeature(
        bounds: const Rect.fromLTWH(460, 0, 14, 678),
        type: DisplayFeatureType.hinge,
        state: DisplayFeatureState.postureHalfOpened,
      ),
    ];
    addTearDown(tester.view.resetDisplayFeatures);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = WorkspaceRepository(
      baseUrl: 'https://example.test/api/v1',
      client: MockClient(
        (r) async => http.Response.bytes(
          utf8.encode(jsonEncode({'services': demoServices})),
          200,
        ),
      ),
    );
    await tester.pumpWidget(ZhixuApp(repository: repo));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byType(Scaffold)).right, lessThanOrEqualTo(460));
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    repo.dispose();
  });
  test('unknown refunds offer original-result reconciliation, not ordinary failure', () {
    final c = {
      ...demoCases('a').first,
      'order': {
        'status': 'cancelled',
        'payments': [
          {'id': 'p', 'status': 'succeeded'},
        ],
        'refunds': [
          {'id': 'r', 'status': 'unknown'},
        ],
        'feedback': [],
      },
    };
    final codes = actionsFor(c, true).map((x) => x.code);
    expect(codes, contains('resolve_refund_failed'));
    expect(codes, contains('confirm_refund'));
    expect(codes, isNot(contains('fail_refund')));
    expect(codes, isNot(contains('approve_refund')));
  });
  test('completed main service keeps after-sale revision handling and grouped delivery choices', () {
    final c = {
      ...demoCases('a').first,
      'after_sales': [
        {'id': 'af', 'status': 'open'},
      ],
      'order': {
        'status': 'completed',
        'payments': [],
        'refunds': [],
        'feedback': [
          {'id': 'f', 'status': 'requested', 'delivery_id': 'af-2'},
        ],
        'deliveries': [
          {'id': 'main', 'status': 'released'},
          {'id': 'af-1', 'status': 'released', 'after_sale_id': 'af'},
          {'id': 'af-2', 'status': 'released', 'after_sale_id': 'af'},
          {'id': 'draft', 'status': 'draft', 'after_sale_id': 'af'},
        ],
      },
    };
    expect(actionsFor(c, true).map((x) => x.code), contains('accept_revision'));
    expect(
      availableDeliveries(c, 'accept_delivery').map((x) => x['id']).toList(),
      ['af-2'],
    );
  });
  for (final width in [390.0, 1200.0]) {
    testWidgets(
      'responsive manager at width $width can open and close quote form',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        http.Response reply(Json body) =>
            http.Response.bytes(utf8.encode(jsonEncode(body)), 200);
        final repo = WorkspaceRepository(
          baseUrl: 'https://example.test/api/v1',
          client: MockClient((r) async {
            if (r.url.path.endsWith('/auth/login')) {
              return reply({
                'token': 'admin-token',
                'user': {'id': 'admin', 'name': '管理员', 'role': 'admin'},
              });
            }
            if (r.url.path.endsWith('/services')) {
              return reply({'services': demoServices});
            }
            return reply({
              'user': {'id': 'admin', 'name': '管理员', 'role': 'admin'},
              'services': demoServices,
              'cases': [
                {...demoCases('a').first, 'id': 'live-case'},
              ],
            });
          }),
        );
        await repo.login('admin', 'password');
        await tester.pumpWidget(ZhixuApp(repository: repo, adminMode: true));
        await tester.pumpAndSettle();
        expect(find.text('知序 / 管理工作台'), findsOneWidget);
        await tester.tap(find.text('需求').last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('英文摘要语言润色').first);
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('发布报价'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('发布报价'));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        await tester.tap(find.text('取消').last);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        repo.dispose();
      },
    );
  }
  testWidgets('public API service information does not claim local demo', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final repo = WorkspaceRepository(
      baseUrl: 'https://example.test/api/v1',
      client: MockClient(
        (r) async => http.Response.bytes(
          utf8.encode(jsonEncode({'services': demoServices})),
          200,
        ),
      ),
    );
    await tester.pumpWidget(ZhixuApp(repository: repo));
    await tester.pumpAndSettle();
    expect(find.text('服务信息已连接 · 登录后办理需求'), findsOneWidget);
    expect(find.textContaining('本地演示 · 服务信息'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    repo.dispose();
  });
  for (final service in demoServices) {
    testWidgets(
      '${service['id']} form only asks relevant required fields and allows optional blanks',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        tester.view.physicalSize = const Size(1200, 1100);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        Json? submitted;
        http.Response reply(Json body) =>
            http.Response.bytes(utf8.encode(jsonEncode(body)), 200);
        final repo = WorkspaceRepository(
          baseUrl: 'https://example.test/api/v1',
          client: MockClient((r) async {
            if (r.url.path.endsWith('/auth/login')) {
              return reply({
                'token': 'token',
                'user': {'id': 'a', 'name': '客户', 'role': 'customer'},
              });
            }
            if (r.url.path.endsWith('/services')) {
              return reply({'services': demoServices});
            }
            if (r.method == 'POST' && r.url.path.endsWith('/cases')) {
              submitted = object(jsonDecode(r.body));
              return reply({
                'case': {
                  ...demoCases('a').first,
                  ...submitted!,
                  'id': 'real-case',
                },
              });
            }
            return reply({
              'user': {'id': 'a', 'name': '客户', 'role': 'customer'},
              'services': demoServices,
              'cases': [],
            });
          }),
        );
        await repo.login('a', 'password');
        await tester.pumpWidget(ZhixuApp(repository: repo));
        await tester.pumpAndSettle();
        final index = demoServices.indexOf(service);
        await tester.tap(find.text('了解并提交需求').at(index));
        await tester.pumpAndSettle();
        Finder field(String label) => find.widgetWithText(TextField, label);
        expect(
          field('学历 / 阶段 *'),
          service['id'] == 'graduation' ? findsOneWidget : findsNothing,
        );
        expect(
          field('语种 / 编译方向 *'),
          service['id'] == 'editing' ? findsOneWidget : findsNothing,
        );
        await tester.enterText(field('需求标题 *'), '测试服务需求');
        await tester.enterText(field('目标、现有材料与交付要求 *'), '本人稿件服务范围说明');
        if (service['id'] != 'editing') {
          await tester.enterText(
            field(service['id'] == 'journal' ? '专业 / 期刊方向 *' : '专业 / 学科 *'),
            '计算机',
          );
        } else {
          await tester.enterText(field('语种 / 编译方向 *'), '英语到中文');
        }
        await tester.ensureVisible(find.byType(CheckboxListTile));
        await tester.tap(find.byType(CheckboxListTile));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, '提交需求'));
        await tester.pumpAndSettle();
        expect(submitted, isNotNull);
        expect(submitted!['service_id'], service['id']);
        expect(submitted!['word_count'], 0);
        expect(submitted!['deadline'], '');
        expect(submitted!['level'], service['id'] == 'graduation' ? '本科' : '');
        if (service['id'] == 'editing') {
          expect(submitted!['language'], '英语到中文');
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        repo.dispose();
      },
    );
  }
  for (final size in [
    const Size(320, 640),
    const Size(390, 844),
    const Size(678, 467),
    const Size(934, 678),
    const Size(1440, 900),
  ]) {
    testWidgets('responsive service page $size', (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = WorkspaceRepository(
        baseUrl: 'https://example.test/api/v1',
        client: MockClient(
          (r) async =>
              http.Response(jsonEncode({'services': demoServices}), 200),
        ),
      );
      await tester.pumpWidget(ZhixuApp(repository: repo));
      await tester.pumpAndSettle();
      expect(find.text('毕业论文'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('我的').last);
      await tester.pumpAndSettle();
      expect(find.text('显示主题'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      repo.dispose();
    });
  }
  testWidgets('large text empty workspace has reload and login entry', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.platformDispatcher.textScaleFactorTestValue = 1.8;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final repo = WorkspaceRepository(
      baseUrl: 'https://example.test/api/v1',
      client: MockClient(
        (r) async => http.Response(jsonEncode({'services': demoServices}), 200),
      ),
    );
    await tester.pumpWidget(ZhixuApp(repository: repo));
    await tester.pumpAndSettle();
    await tester.tap(find.text('需求').last);
    await tester.pumpAndSettle();
    expect(find.text('登录 / 体验演示'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    repo.dispose();
  });
  test('theme semantic foreground/background contrast >=4.5', () {
    double ratio(Color a, Color b) {
      final l = [a.computeLuminance(), b.computeLuminance()]..sort();
      return (l.last + .05) / (l.first + .05);
    }

    for (final brightness in Brightness.values) {
      final s = appTheme(brightness).colorScheme;
      expect(ratio(s.onSurface, s.surface), greaterThanOrEqualTo(4.5));
      expect(ratio(s.onSurfaceVariant, s.surface), greaterThanOrEqualTo(4.5));
      expect(ratio(s.onPrimary, s.primary), greaterThanOrEqualTo(4.5));
      expect(
        ratio(s.onSecondaryContainer, s.secondaryContainer),
        greaterThanOrEqualTo(4.5),
      );
    }
  });
}
