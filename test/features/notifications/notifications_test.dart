import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_management_app/app/theme/app_theme.dart';
import 'package:gym_management_app/core/config/app_config.dart';
import 'package:gym_management_app/features/admin_dashboard/providers/dashboard_providers.dart';
import 'package:gym_management_app/features/notifications/notifications.dart';
import 'package:gym_management_app/features/notifications/notifications_page.dart';

Map<String, dynamic> item(
  String kind, {
  String key = 'k',
  String severity = 'high',
  bool unread = true,
  Map<String, dynamic>? extra,
}) => {
  'key': '$kind:$key',
  'kind': kind,
  'severity': severity,
  'title': '$kind title $key',
  'detail': 'detail',
  'date': '2026-11-28',
  'unread': unread,
  'member': {
    'id': 'm$key',
    'name': 'Ravi Kumar',
    'memberCode': 'M1',
    'phone': '9876543210',
  },
  ...?extra,
};

class _FakeRepository extends NotificationRepository {
  _FakeRepository(this.feedJson) : super(Dio());
  final Map<String, dynamic> feedJson;
  int seen = 0;
  @override
  Future<NotificationFeed> feed(String gymId) async =>
      NotificationFeed.fromJson(feedJson);
  @override
  Future<void> markSeen(String gymId) async => seen += 1;
}

void main() {
  test('messages fit each reminder and use the first name', () {
    final expiring = GymNotification.fromJson(
      item('expiring', extra: {'planName': 'Monthly', 'daysLeft': 2}),
    );
    expect(expiring.message('Iron'), contains('Hi Ravi'));
    expect(
      expiring.message('Iron'),
      contains('Monthly membership ends in 2 days'),
    );
    expect(expiring.message('Iron'), endsWith('– Iron'));
    final dues = GymNotification.fromJson(
      item('dues', extra: {'amountPaise': 50000}),
    );
    expect(dues.message(''), contains('₹500'));
    expect(NotificationKind.claim.remindable, isFalse);
  });

  test('unknown kinds from a newer server are skipped', () {
    final feed = NotificationFeed.fromJson({
      'unread': 1,
      'data': [item('dues'), item('something_new')],
    });
    expect(feed.items.map((i) => i.kind), [NotificationKind.dues]);
  });

  Future<_FakeRepository> pump(
    WidgetTester tester,
    Map<String, dynamic> feed,
  ) async {
    final repository = _FakeRepository(feed);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(AppConfig.fromValues()),
          notificationRepositoryProvider.overrideWithValue(repository),
          adminGymProvider.overrideWithBuild(
            (ref, _) => (userId: 'u1', gymId: 'g1'),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.dark,
          home: const Scaffold(body: NotificationsPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return repository;
  }

  testWidgets('grouped by what to do, marked read once opened', (tester) async {
    final repository = await pump(tester, {
      'unread': 2,
      'data': [
        item('dues', key: '1'),
        item('dues', key: '2', unread: false),
        item('expiring', key: '3', severity: 'medium', unread: true),
      ],
    });
    expect(find.text('2 new · 3 to look at'), findsOneWidget);
    expect(find.text('Dues to collect · 2'), findsOneWidget);
    expect(find.text('Ending soon · 1'), findsOneWidget);
    // Two or more people in a group can be reminded in one run.
    expect(find.text('Remind all'), findsOneWidget);
    expect(repository.seen, 1);
  });

  testWidgets('remind all walks through each member', (tester) async {
    await pump(tester, {
      'unread': 0,
      'data': [item('dues', key: '1'), item('dues', key: '2')],
    });
    await tester.tap(find.text('Remind all'));
    await tester.pumpAndSettle();
    expect(find.text('1 of 2'), findsOneWidget);
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    expect(find.text('2 of 2'), findsOneWidget);
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    expect(find.text('0 reminders opened in WhatsApp.'), findsOneWidget);
  });

  testWidgets('an empty feed says all clear', (tester) async {
    await pump(tester, {'unread': 0, 'data': <Object>[]});
    expect(find.text('All clear'), findsOneWidget);
  });
}
