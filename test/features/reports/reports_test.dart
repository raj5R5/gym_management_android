import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_management_app/app/theme/app_theme.dart';
import 'package:gym_management_app/features/admin_dashboard/providers/dashboard_providers.dart';
import 'package:gym_management_app/features/branches/branches.dart';
import 'package:gym_management_app/features/reports/report_pdf.dart';
import 'package:gym_management_app/features/reports/reports.dart';
import 'package:gym_management_app/features/reports/reports_page.dart';
import 'package:gym_management_app/shared/sharing/share_pdf.dart';

const gymId = '0000000000000000000000f1';

Map<String, dynamic> envelope(
  Map<String, dynamic> report, {
  String scope = 'branch',
}) => {
  'kind': 'profit-loss',
  'scope': scope,
  'period': {
    'from': '2026-10-01',
    'to': '2026-11-16',
    'days': 47,
    'timezone': 'UTC',
  },
  'branches': [
    {'gymId': gymId, 'name': 'Iron Gym'},
    if (scope == 'all') {'gymId': 'b', 'name': 'Iron Gym East'},
  ],
  'report': report,
};

final profitLoss = {
  'months': [
    {
      'key': '2026-10',
      'membershipPaise': 100000,
      'ptPaise': 0,
      'expensesPaise': 150000,
      'commissionPaise': 0,
      'incomePaise': 100000,
      'profitPaise': -50000,
    },
    {
      'key': '2026-11',
      'membershipPaise': 300000,
      'ptPaise': 40000,
      'expensesPaise': 30000,
      'commissionPaise': 4000,
      'incomePaise': 340000,
      'profitPaise': 306000,
    },
  ],
  'expensesByCategory': [
    {'key': 'rent', 'amountPaise': 180000},
  ],
  'totals': {
    'membershipPaise': 400000,
    'ptPaise': 40000,
    'incomePaise': 440000,
    'expensesPaise': 180000,
    'commissionPaise': 4000,
    'profitPaise': 256000,
    'marginPercent': 58.2,
  },
};

class _FakeReports implements ReportRepository {
  final queries = <ReportQuery>[];
  @override
  Future<ReportData> get(String gymId, ReportQuery query) async {
    queries.add(query);
    return ReportData.fromJson(
      query.kind,
      envelope(profitLoss, scope: query.allBranches ? 'all' : 'branch'),
    );
  }
}

class _FixedGym extends AdminGymController {
  @override
  AdminGymContext? build() => (userId: 'u1', gymId: gymId);
}

void main() {
  final data = ReportData.fromJson(ReportKind.profitLoss, envelope(profitLoss));

  test('profit & loss sections show losses as negative and flagged', () {
    final sections = reportSections(data);
    final summary = sections.first;
    expect(summary.figures.map((f) => f.value), [
      '₹4,400',
      '₹1,800',
      '₹40',
      '₹2,560',
      '58.2%',
    ]);
    final byMonth = sections[1];
    expect(byMonth.bars.first.label, 'Oct 2026');
    expect(byMonth.bars.first.value, '−₹500');
    expect(byMonth.bars.first.negative, isTrue);
    expect(byMonth.bars.last.fraction, 1);
    expect(sections.last.bars.single.label, 'Rent');
  });

  test('every report kind builds sections from an empty report', () {
    for (final kind in ReportKind.values) {
      final empty = ReportData.fromJson(kind, envelope({}));
      expect(reportSections(empty), isNotEmpty, reason: kind.wire);
    }
    expect(ReportKind.parse('dues'), ReportKind.dues);
    expect(ReportKind.dues.usesPeriod, isFalse);
    expect(signedInr(-12345), '−₹123.45');
  });

  testWidgets('the PDF embeds the font and lists branches', (tester) async {
    final bytes = await tester.runAsync(
      () => buildReportPdf(
        data: ReportData.fromJson(
          ReportKind.profitLoss,
          envelope(profitLoss, scope: 'all'),
        ),
        gymName: 'All branches',
        periodLabel: '1 Oct – 16 Nov',
        generatedOn: '16 Nov 2026',
      ),
    );
    expect(latin1.decode(bytes!.sublist(0, 5)), '%PDF-');
    expect(latin1.decode(bytes).contains('/FontFile2'), isTrue);
  });

  testWidgets('report page switches period and branch scope', (tester) async {
    final repository = _FakeReports();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          adminGymProvider.overrideWith(_FixedGym.new),
          reportRepositoryProvider.overrideWithValue(repository),
          branchNamesProvider.overrideWithValue({
            gymId: 'Iron Gym',
            'b': 'East',
          }),
        ],
        child: MaterialApp(
          theme: AppTheme.dark,
          home: const Scaffold(body: ReportPage(kind: ReportKind.profitLoss)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('₹2,560'), findsOneWidget);
    expect(find.text('−₹500'), findsWidgets);
    await tester.tap(find.text('Last month'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('All branches'));
    await tester.pumpAndSettle();
    expect(repository.queries.last.period, ReportPeriod.lastMonth);
    expect(repository.queries.last.allBranches, isTrue);
    expect(find.textContaining('2 branches'), findsOneWidget);
  });

  test('shared PDFs get readable, safe file names', () {
    expect(
      safePdfName('Dues ageing As of 16 Nov 2026'),
      'Dues ageing As of 16 Nov 2026.pdf',
    );
    expect(
      safePdfName('Profit & loss 1 Oct – 16 Nov'),
      'Profit  loss 1 Oct - 16 Nov.pdf'.replaceAll('  ', ' '),
    );
    expect(safePdfName('Receipt R-00012'), 'Receipt R-00012.pdf');
    expect(safePdfName('///'), 'document.pdf');
  });
}
