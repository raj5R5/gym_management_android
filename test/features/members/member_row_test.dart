import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_management_app/core/config/app_config.dart';
import 'package:gym_management_app/features/members/photos/member_photo_providers.dart';
import 'package:gym_management_app/app/theme/app_theme.dart';
import 'package:gym_management_app/features/members/models/member_overview.dart';
import 'package:gym_management_app/features/members/presentation/member_overview_widgets.dart';
import 'package:gym_management_app/shared/widgets/glass.dart';

import 'member_overview_test.dart' show membership, row;
import 'photo_fakes.dart';

void main() {
  const gym = (userId: 'user-1', gymId: '000000000000000000000001');
  final rows = [
    MemberOverviewRow.fromJson(
      row(
        membership: membership('active', daysLeft: 20),
        balance: 100000,
        due: 'sub-1',
      ),
    ),
    MemberOverviewRow.fromJson(
      row(membership: membership('expired', since: 4)),
    ),
    MemberOverviewRow.fromJson(
      row(membership: membership('active', daysLeft: 9)),
    ),
  ];

  Future<void> pump(WidgetTester tester) => tester.pumpWidget(
    ProviderScope(
      overrides: [
        appConfigProvider.overrideWithValue(AppConfig.fromValues()),
        memberPhotoStoreProvider.overrideWithValue(MemoryMemberPhotoStore()),
      ],
      child: MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: ListView(
            children: [
              MemberOverviewList(
                children: [
                  for (final r in rows)
                    MemberOverviewTile(row: r, gym: gym, gymName: 'Iron'),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );

  testWidgets('members are rows with lines between them, not cards', (
    tester,
  ) async {
    await pump(tester);
    expect(find.byType(GlassCard), findsNothing);
    expect(find.byType(Divider), findsNWidgets(rows.length - 1));
    // Each row keeps its one next step and quick contact.
    expect(find.text('Collect ₹1,000'), findsOneWidget);
    expect(find.text('Renew'), findsOneWidget);
    expect(find.text('Paid in full'), findsOneWidget);
    expect(find.byTooltip('Call Aarav'), findsNWidgets(3));
    expect(find.byTooltip('WhatsApp Aarav'), findsNWidgets(3));
  });

  testWidgets('large text on a narrow phone stacks the actions cleanly', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pump(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('Collect ₹1,000'), findsOneWidget);
  });
}
