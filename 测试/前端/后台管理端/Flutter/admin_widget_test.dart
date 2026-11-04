import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zhixu/Data/models.dart';
import 'package:zhixu/Data/repository.dart';
import 'package:zhixu/Ui/app.dart';
import 'package:zhixu/Ui/actions.dart';

void main() {
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
}
