import 'package:flutter/services.dart';
import 'package:gym_management_app/shared/widgets/membership_date_range.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gym_management_app/app/theme/app_theme.dart';
import 'package:gym_management_app/app/theme/design_tokens.dart';
import 'package:gym_management_app/features/members/models/member_models.dart';
import 'package:gym_management_app/features/members/presentation/member_list_widgets.dart';
import 'member_fakes.dart';
import 'package:gym_management_app/core/config/app_config.dart';

Widget _photoScopedApp({required ThemeData theme, required Widget home}) =>
    ProviderScope(
      overrides: [appConfigProvider.overrideWithValue(AppConfig.fromValues())],
      child: MaterialApp(theme: theme, home: home),
    );

double contrast(Color first, Color second) {
  final a = first.computeLuminance(), b = second.computeLuminance();
  return ((a > b ? a : b) + .05) / ((a > b ? b : a) + .05);
}

void main() {
  setUpAll(() async {
    // Measure compact layouts with the same bundled fonts used on the phone.
    for (final family in ['Inter', 'SpaceGrotesk']) {
      await (FontLoader(
        family,
      )..addFont(rootBundle.load('assets/fonts/$family.ttf'))).load();
    }
  });
  test(
    'approved palette and semantic button/panel roles retain readable contrast',
    () {
      expect(AppPalette.softBlue, const Color(0xFFE7EFFB));
      expect(AppPalette.lavender, const Color(0xFFE7EFFB));
      for (final theme in [AppTheme.light, AppTheme.dark]) {
        final surfaces = theme.extension<AppSurfaces>()!;
        for (final tone in AppTone.values) {
          expect(
            contrast(surfaces.onAccent(tone), surfaces.accent(tone)),
            greaterThanOrEqualTo(4.5),
          );
          expect(
            contrast(
              theme.colorScheme.onSurface,
              surfaces.panel(tone, theme.brightness),
            ),
            greaterThanOrEqualTo(4.5),
          );
        }
        for (final tone in MemberCardTone.values) {
          expect(
            contrast(
              theme.colorScheme.onSurface,
              surfaces.memberCard(tone, theme.brightness),
            ),
            greaterThanOrEqualTo(4.5),
          );
        }
        expect(
          theme.filledButtonTheme.style!.backgroundColor!.resolve({}),
          theme.colorScheme.primary,
        );
        expect(
          theme.filledButtonTheme.style!.foregroundColor!.resolve({}),
          theme.colorScheme.onPrimary,
        );
        final selectedIcon = theme.navigationBarTheme.iconTheme!.resolve({
          WidgetState.selected,
        })!.color!;
        expect(
          contrast(selectedIcon, theme.navigationBarTheme.indicatorColor!),
          greaterThanOrEqualTo(4.5),
        );
      }
    },
  );

  MemberSummary summary({
    int? balance = 50000,
    bool membership = true,
    bool historicExpired = false,
    bool invalidBalance = false,
  }) {
    final json = summaryJson(populated: true);
    json['currentSubscription'] = membership ? subscriptionJson() : null;
    json['currentSubscriptionPaymentSummary'] = balance == null || !membership
        ? null
        : {
            'pricePaise': invalidBalance ? 140000 : 150000,
            'paidAmountPaise': 150000 - balance,
            'remainingAmountPaise': balance,
            'paymentCount': 1,
          };
    if (historicExpired) {
      json['subscriptionHistory'] = {
        'items': [
          subscriptionJson()..addAll({
            'status': 'expired',
            'isCurrentlyActive': false,
            'planNameSnapshot': 'Historic plan',
          }),
        ],
        'page': 1,
        'limit': 20,
        'total': 1,
      };
    }
    return MemberSummary.fromJson(json);
  }

  Future<void> showCard(
    WidgetTester tester, {
    MemberSummary? data,
    bool failed = false,
    Map<String, dynamic>? profile,
    MembershipDetail? previous,
    Brightness brightness = Brightness.light,
  }) async {
    await tester.pumpWidget(
      _photoScopedApp(
        theme: brightness == Brightness.light ? AppTheme.light : AppTheme.dark,
        home: Scaffold(
          body: SingleChildScrollView(
            child: MemberDirectoryCard(
              member: MemberProfile.fromJson(profile ?? profileJson()),
              onTap: () {},
              previousDetails: previous == null ? null : AsyncData(previous),
              summary: failed
                  ? AsyncError(
                      const FormatException('Invalid membership dates.'),
                      StackTrace.current,
                    )
                  : AsyncData(data),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets(
    'foreign photo addresses retain initials without fetching external images',
    (tester) async {
      await showCard(
        tester,
        data: summary(),
        profile: {
          ...profileJson(),
          'photoUrl': 'https://example.invalid/unsupported.jpg',
        },
      );
      expect(find.text('AR'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
      expect(find.byType(MemberPortrait), findsOneWidget);
    },
  );
  for (final balance in [0, 50000]) {
    testWidgets(
      'active membership and ${balance == 0 ? 'Fully Paid' : 'dues'} are distinct',
      (tester) async {
        await showCard(tester, data: summary(balance: balance));
        expect(find.text('Active'), findsNothing);
        expect(find.text('Payment due'), findsNothing);
        final dot = find.byTooltip('Active membership');
        expect(dot, findsOneWidget);
        final photo = tester.getRect(find.byType(MemberPortrait));
        expect(tester.getRect(dot).top, photo.top + AppSpacing.sm);
        expect(tester.getRect(dot).right, photo.right - AppSpacing.sm);
        final indicator = tester.widget<Container>(
          find.descendant(of: dot, matching: find.byType(Container)).first,
        );
        expect(
          (indicator.decoration as BoxDecoration).color,
          AppPalette.mintInk,
        );
        expect(find.byType(MemberStatusBadge), findsNothing);
        expect(
          tester.widget<Card>(find.byType(Card)).color,
          balance == 0 ? AppPalette.mint : PendingColors.surface,
        );
        if (balance == 0) {
          final badge = find.widgetWithText(StatusPill, 'Fully Paid');
          expect(tester.widget<StatusPill>(badge).tone, AppTone.positive);
          final text = tester.widget<Text>(
            find.descendant(of: badge, matching: find.byType(Text)),
          );
          expect(text.style!.color, AppPalette.mintInk);
        } else {
          expect(find.text('Fully Paid'), findsNothing);
          expect(find.text('₹500.00 due'), findsOneWidget);
          expect(
            tester.widget<Text>(find.text('₹500.00 due')).style!.color,
            PendingColors.accent,
          );
        }
        expect(find.text('Monthly'), findsNothing);
        expect(find.textContaining('ME01'), findsNothing);
        expect(find.textContaining('9876543210'), findsNothing);
        expect(
          tester
              .widget<MembershipDateRange>(find.byType(MembershipDateRange))
              .label,
          '1 Mar 2026 – 31 Mar 2026',
        );
        expect(find.text('1 Mar 2026 – 31 Mar 2026'), findsOneWidget);
        expect(
          tester.widget<Text>(find.text('1 Mar 2026 – 31 Mar 2026')).maxLines,
          1,
        );
        expect(find.textContaining('Starts:'), findsNothing);
        expect(find.textContaining('Ends:'), findsNothing);
      },
    );
  }
  for (final balance in [0, 50000]) {
    testWidgets(
      'expired membership can be ${balance == 0 ? 'paid' : 'unpaid'} independently',
      (tester) async {
        final membership = Membership.fromJson(
          subscriptionJson()
            ..addAll({'status': 'expired', 'isCurrentlyActive': false}),
        );
        await tester.pumpWidget(
          _photoScopedApp(
            theme: AppTheme.light,
            home: Scaffold(
              body: MembershipCardInfo(
                membership: membership,
                balancePaise: balance,
              ),
            ),
          ),
        );
        expect(find.text('Membership: Expired'), findsOneWidget);
        expect(
          find.text(balance == 0 ? 'Fully Paid' : '₹500.00 Due'),
          findsOneWidget,
        );
      },
    );
  }
  testWidgets(
    'latest expired membership is explicitly previous, never current',
    (tester) async {
      await showCard(
        tester,
        data: summary(membership: false, historicExpired: true),
      );
      expect(
        find.bySemanticsLabel(RegExp('Expired previous membership')),
        findsOneWidget,
      );
      expect(find.text('Expired'), findsOneWidget);
      expect(find.text('Historic plan'), findsNothing);
      expect(find.text('Fully Paid'), findsNothing);
      expect(
        tester
            .widget<MembershipDateRange>(find.byType(MembershipDateRange))
            .label,
        '1 Mar 2026 – 31 Mar 2026',
      );
      expect(find.text('Balance unavailable'), findsOneWidget);
      expect(find.text('₹0.00'), findsNothing);
    },
  );
  for (final balance in [0, 50000]) {
    testWidgets('expired card stays grey with saved balance $balance', (
      tester,
    ) async {
      final detail = MembershipDetail.fromJson({
        'subscription': subscriptionJson()
          ..addAll({'status': 'expired', 'isCurrentlyActive': false}),
        'paymentSummary': {
          'totalSuccessfulPaidPaise': 150000 - balance,
          'remainingBalancePaise': balance,
        },
      });
      await showCard(
        tester,
        data: summary(membership: false, historicExpired: true),
        previous: detail,
      );
      expect(
        tester.widget<Card>(find.byType(Card)).color,
        AppPalette.mutedGrey,
      );
      expect(find.text('Expired'), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp('Expired previous membership')),
        findsOneWidget,
      );
      expect(
        find.text(balance == 0 ? 'No balance due' : '₹500.00 due'),
        findsOneWidget,
      );
      if (balance > 0) {
        expect(
          tester.widget<Text>(find.text('₹500.00 due')).style!.color,
          PendingColors.accent,
        );
      }
      expect(find.text('Active'), findsNothing);
      for (final pill in tester.widgetList<StatusPill>(
        find.byType(StatusPill),
      )) {
        expect(pill.tone, AppTone.expired);
        final text = tester.widget<Text>(
          find.descendant(of: find.byWidget(pill), matching: find.byType(Text)),
        );
        expect(text.style!.color, AppPalette.greyInk);
      }
    });
  }
  testWidgets('mismatched expired detail cannot supply another balance', (
    tester,
  ) async {
    final detail = MembershipDetail.fromJson({
      'subscription': subscriptionJson()
        ..addAll({
          'id': 'different-membership',
          'status': 'expired',
          'isCurrentlyActive': false,
        }),
      'paymentSummary': {
        'totalSuccessfulPaidPaise': 150000,
        'remainingBalancePaise': 0,
      },
    });
    await showCard(
      tester,
      data: summary(membership: false, historicExpired: true),
      previous: detail,
    );
    expect(find.text('Balance unavailable'), findsOneWidget);
    expect(find.text('Fully Paid'), findsNothing);
  });
  testWidgets('no membership has no invented dates or paid status', (
    tester,
  ) async {
    await showCard(tester, data: summary(membership: false));
    expect(find.text('No membership'), findsOneWidget);
    expect(find.byType(MembershipDateRange), findsNothing);
    expect(find.textContaining('Starts:'), findsNothing);
    expect(find.textContaining('Ends:'), findsNothing);
    expect(find.text('Fully Paid'), findsNothing);
  });
  test('pending warning and grey status colors retain accessible contrast', () {
    expect(PendingColors.surface, const Color(0xFFFBE3DF));
    expect(PendingColors.accent, const Color(0xFFA72F35));
    expect(
      contrast(PendingColors.accent, PendingColors.surface),
      greaterThanOrEqualTo(3),
    );
    expect(
      contrast(PendingColors.onAccent, PendingColors.accent),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      contrast(AppPalette.greyInk, AppPalette.mutedGrey),
      greaterThanOrEqualTo(4.5),
    );
    for (final brightness in Brightness.values) {
      expect(
        contrast(
          PendingColors.accentFor(brightness),
          PendingColors.surfaceFor(brightness),
        ),
        greaterThanOrEqualTo(3),
      );
    }
    // General payment and destructive-action colors stay separate.
    expect(
      AppTheme.light.extension<AppSurfaces>()!.accent(AppTone.payment),
      AppPalette.peach,
    );
    expect(
      AppTheme.light.extension<AppSurfaces>()!.accent(AppTone.warning),
      AppPalette.coral,
    );
  });
  testWidgets(
    'dark pending and expired member cards preserve warning priority',
    (tester) async {
      await showCard(tester, data: summary(), brightness: Brightness.dark);
      expect(find.text('Payment due'), findsNothing);
      expect(find.byTooltip('Active membership'), findsOneWidget);
      expect(
        tester.widget<Text>(find.text('₹500.00 due')).style!.color,
        PendingColors.accentFor(Brightness.dark),
      );
      final detail = MembershipDetail.fromJson({
        'subscription': subscriptionJson()
          ..addAll({'status': 'expired', 'isCurrentlyActive': false}),
        'paymentSummary': {
          'totalSuccessfulPaidPaise': 100000,
          'remainingBalancePaise': 50000,
        },
      });
      await showCard(
        tester,
        data: summary(membership: false, historicExpired: true),
        previous: detail,
        brightness: Brightness.dark,
      );
      expect(tester.widget<Card>(find.byType(Card)).color, AppPalette.darkGrey);
      expect(
        tester
            .widgetList<StatusPill>(find.byType(StatusPill))
            .every((pill) => pill.tone == AppTone.expired),
        true,
      );
      expect(find.text('₹500.00 due'), findsOneWidget);
      expect(
        tester.widget<Text>(find.text('₹500.00 due')).style?.color,
        PendingColors.accentFor(Brightness.dark),
      );
    },
  );
  testWidgets('current membership takes precedence over expired history', (
    tester,
  ) async {
    await showCard(tester, data: summary(balance: 0, historicExpired: true));
    expect(find.text('Active'), findsNothing);
    expect(find.byTooltip('Active membership'), findsOneWidget);
    expect(find.text('Expired'), findsNothing);
    expect(tester.widget<Card>(find.byType(Card)).color, AppPalette.mint);
  });
  for (final invalid in [false, true]) {
    testWidgets(
      'missing or inconsistent saved balance is unavailable ($invalid)',
      (tester) async {
        await showCard(
          tester,
          data: summary(
            balance: invalid ? 50000 : null,
            invalidBalance: invalid,
          ),
        );
        expect(find.text('Balance unavailable'), findsOneWidget);
        expect(
          tester.widget<Card>(find.byType(Card)).color,
          AppPalette.surface,
        );
        expect(find.text('Fully Paid'), findsNothing);
        expect(find.text('₹0.00'), findsNothing);
      },
    );
  }
  testWidgets(
    'unavailable dates do not produce fabricated plan or zero balance',
    (tester) async {
      await showCard(tester, failed: true);
      expect(find.text('Membership details unavailable'), findsOneWidget);
      expect(find.textContaining('Starts:'), findsNothing);
      expect(find.text('Fully Paid'), findsNothing);
    },
  );
  for (final config in [
    (390.0, 1.0, true),
    (320.0, 1.0, false),
    (390.0, 2.0, false),
  ]) {
    testWidgets('grid responds to width ${config.$1} and scale ${config.$2}', (
      tester,
    ) async {
      tester.view.physicalSize = Size(config.$1, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        _photoScopedApp(
          theme: AppTheme.light,
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(config.$2)),
            child: Scaffold(
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: ResponsiveMemberGrid(
                  children: [
                    for (var i = 0; i < 2; i++)
                      MemberDirectoryCard(
                        key: ValueKey('card-$i'),
                        member: MemberProfile.fromJson(
                          profileJson(firstName: 'Long member name'),
                        ),
                        summary: AsyncData(summary()),
                        onTap: () {},
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      final first = tester.getRect(find.byKey(const ValueKey('card-0')));
      final second = tester.getRect(find.byKey(const ValueKey('card-1')));
      if (config.$3) {
        expect(first.top, second.top);
        expect(second.left, greaterThan(first.right));
      } else {
        expect(first.left, second.left);
        expect(second.top, greaterThan(first.bottom));
      }
      expect(tester.takeException(), isNull);
    });
  }

  test('theme text and every status surface meet normal-text contrast', () {
    for (final theme in [AppTheme.light, AppTheme.dark]) {
      final scheme = theme.colorScheme;
      final surfaces = theme.extension<AppSurfaces>()!;
      expect(
        contrast(scheme.onSurface, scheme.surface),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        contrast(scheme.onSurfaceVariant, scheme.surface),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        contrast(scheme.onPrimary, scheme.primary),
        greaterThanOrEqualTo(4.5),
      );
      for (final color in [
        surfaces.active,
        surfaces.inactive,
        surfaces.suspended,
      ]) {
        expect(contrast(surfaces.onStatus, color), greaterThanOrEqualTo(4.5));
      }
    }
  });

  for (final brightness in Brightness.values) {
    for (final status in MemberStatus.values) {
      testWidgets(
        '$brightness $status card remains readable and opens the member',
        (tester) async {
          tester.view.physicalSize = const Size(320, 850);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final member = MemberProfile.fromJson({
            ...profileJson(firstName: 'Alexandria'),
            'lastName': 'River Montgomery',
            'status': status.name,
          });
          var taps = 0;
          await tester.pumpWidget(
            _photoScopedApp(
              theme: brightness == Brightness.light
                  ? AppTheme.light
                  : AppTheme.dark,
              home: MediaQuery(
                data: const MediaQueryData(textScaler: TextScaler.linear(2)),
                child: Scaffold(
                  body: SingleChildScrollView(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: MemberDirectoryCard(
                      member: member,
                      onTap: () => taps++,
                    ),
                  ),
                ),
              ),
            ),
          );
          expect(find.text(member.name), findsOneWidget);
          expect(find.byType(MemberStatusBadge), findsNothing);
          expect(find.textContaining('ME01 · +91 9876543210'), findsNothing);
          expect(find.text('Membership details unavailable'), findsOneWidget);
          expect(find.byType(BackdropFilter), findsNothing);
          await tester.tap(find.text(member.name));
          expect(taps, 1);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
  testWidgets(
    'member cards use the compact dues photo height and readable footer',
    (tester) async {
      tester.view.physicalSize = const Size(390, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        _photoScopedApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: ResponsiveMemberGrid(
                children: [
                  for (final balance in [0, 50000])
                    MemberDirectoryCard(
                      member: MemberProfile.fromJson(profileJson()),
                      summary: AsyncData(summary(balance: balance)),
                      onTap: () {},
                    ),
                ],
              ),
            ),
          ),
        ),
      );
      for (final card in find.byType(MemberDirectoryCard).evaluate()) {
        final cardFinder = find.byWidget(card.widget);
        final photo = find.descendant(
          of: cardFinder,
          matching: find.byType(MemberPortrait),
        );
        final size = tester.getSize(cardFinder);
        expect(tester.getSize(photo).height, 168);
        expect(size.height, lessThanOrEqualTo(320));
        expect(tester.getSize(photo).width, size.width);
      }
      expect(find.text('₹500.00 due'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'settled current membership with older dues stays coral and shows the canonical total',
    (tester) async {
      await tester.pumpWidget(
        _photoScopedApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: MemberDirectoryCard(
              member: MemberProfile.fromJson(profileJson()),
              summary: AsyncData(summary(balance: 0)),
              outstandingDues: const AsyncData(70000),
              onTap: () {},
            ),
          ),
        ),
      );
      expect(
        tester.widget<Card>(find.byType(Card)).color,
        PendingColors.surface,
      );
      expect(find.text('₹700.00 due'), findsOneWidget);
      expect(find.text('Payment due'), findsNothing);
      expect(find.text('Fully Paid'), findsNothing);
    },
  );

  testWidgets(
    'verified total dues remain visible if the separate membership summary fails',
    (tester) async {
      await tester.pumpWidget(
        _photoScopedApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: MemberDirectoryCard(
              member: MemberProfile.fromJson(profileJson()),
              summary: AsyncError(
                const FormatException('Membership unavailable'),
                StackTrace.current,
              ),
              outstandingDues: const AsyncData(45000),
              onTap: () {},
              retry: () {},
            ),
          ),
        ),
      );
      expect(find.text('₹450.00 due'), findsOneWidget);
      expect(find.text('Membership details unavailable'), findsOneWidget);
      expect(find.text('Retry membership'), findsOneWidget);
      expect(find.text('Fully Paid'), findsNothing);
      expect(find.text('Active'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'unverified aggregate dues never paint a currently settled member as fully paid',
    (tester) async {
      await tester.pumpWidget(
        _photoScopedApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: MemberDirectoryCard(
              member: MemberProfile.fromJson(profileJson()),
              summary: AsyncData(summary(balance: 0)),
              outstandingDues: const AsyncLoading(),
              onTap: () {},
            ),
          ),
        ),
      );
      expect(tester.widget<Card>(find.byType(Card)).color, AppPalette.surface);
      expect(find.text('Balance unavailable'), findsOneWidget);
      expect(find.text('Fully Paid'), findsNothing);
      expect(find.text('Checking all balances…'), findsOneWidget);
    },
  );
}
