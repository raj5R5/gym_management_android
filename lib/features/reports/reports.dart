import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/formatting/inr.dart';
import '../admin_dashboard/providers/dashboard_providers.dart';
import '../auth/data/auth_failure.dart';
import '../auth/providers/auth_providers.dart';

enum ReportKind {
  profitLoss(
    'profit-loss',
    'Profit & loss',
    'Income, expenses and profit by month',
    Icons.trending_up,
  ),
  collections(
    'collections',
    'Collections',
    'Money in by method, plan and day',
    Icons.payments_outlined,
  ),
  members(
    'members',
    'Members & retention',
    'Joins, renewals and who did not come back',
    Icons.people_outline,
  ),
  attendance(
    'attendance',
    'Attendance',
    'Busy days and hours, members who stopped coming',
    Icons.event_available_outlined,
  ),
  dues(
    'dues',
    'Dues ageing',
    'What is owed, how old it is and by whom',
    Icons.account_balance_wallet_outlined,
  ),
  leads(
    'leads',
    'Enquiries',
    'Where enquiries come from and how many join',
    Icons.contact_phone_outlined,
  ),
  trainers(
    'trainers',
    'Trainers & PT',
    'Sessions, PT money and commission per trainer',
    Icons.fitness_center_outlined,
  ),
  plans(
    'plans',
    'Plans',
    'Sales and active members per plan',
    Icons.card_membership_outlined,
  );

  const ReportKind(this.wire, this.title, this.subtitle, this.icon);
  final String wire, title, subtitle;
  final IconData icon;

  /// Dues are a snapshot of today; the period does not apply.
  bool get usesPeriod => this != dues;
  static ReportKind? parse(String wire) {
    for (final kind in values) {
      if (kind.wire == wire) return kind;
    }
    return null;
  }
}

enum ReportPeriod {
  thisMonth('thisMonth', 'This month'),
  lastMonth('lastMonth', 'Last month'),
  last3Months('last3Months', 'Last 3 months'),
  last12Months('last12Months', 'Last 12 months'),
  thisYear('thisYear', 'This year');

  const ReportPeriod(this.wire, this.label);
  final String wire, label;
}

typedef ReportQuery = ({
  ReportKind kind,
  ReportPeriod period,
  bool allBranches,
});

class ReportData {
  ReportData.fromJson(this.kind, Map<String, dynamic> json)
    : from = DateTime.parse((json['period'] as Map)['from'] as String),
      to = DateTime.parse((json['period'] as Map)['to'] as String),
      days = (json['period'] as Map)['days'] as int,
      allBranches = json['scope'] == 'all',
      branchNames = [
        for (final row in json['branches'] as List)
          (row as Map)['name'] as String,
      ],
      report = json['report'] as Map<String, dynamic>;
  final ReportKind kind;
  final DateTime from, to;
  final int days;
  final bool allBranches;
  final List<String> branchNames;
  final Map<String, dynamic> report;
}

class ReportFailure implements Exception {
  const ReportFailure(this.message);
  final String message;
  @override
  String toString() => 'ReportFailure: $message';
}

class ReportRepository {
  ReportRepository(this._client);
  final Dio _client;

  Future<ReportData> get(String gymId, ReportQuery query) async {
    try {
      final body = (await _client.get<dynamic>(
        'gyms/$gymId/reports/${query.kind.wire}',
        queryParameters: {
          'preset': query.period.wire,
          'scope': query.allBranches ? 'all' : 'branch',
        },
      )).data;
      if (body is! Map<String, dynamic> || body['success'] != true) {
        throw const ReportFailure('Unexpected response.');
      }
      return ReportData.fromJson(
        query.kind,
        body['data'] as Map<String, dynamic>,
      );
    } on DioException catch (error) {
      final data = error.response?.data;
      final failure = data is Map ? data['error'] : null;
      final code = failure is Map ? failure['code'] : null;
      throw ReportFailure(switch (code) {
        'REPORT_TOO_LARGE' =>
          'This report is too large to build. Pick a shorter period.',
        'REPORT_RANGE_TOO_LONG' => 'Pick a period of one year or less.',
        _ => AuthFailure.fromDio(error).message,
      });
    } on TypeError {
      throw const ReportFailure('The server returned an unexpected report.');
    }
  }
}

final reportRepositoryProvider = Provider<ReportRepository>(
  (ref) => ReportRepository(ref.watch(authenticatedApiClientProvider)),
);

final reportProvider = FutureProvider.autoDispose
    .family<ReportData?, ReportQuery>((ref, query) {
      final gym = ref.watch(adminGymProvider);
      if (gym == null) return null;
      return ref.watch(reportRepositoryProvider).get(gym.gymId, query);
    }, retry: (_, _) => null);

// ---------------------------------------------------------------------------
// Sections: one description per report, drawn both on screen and in the PDF.

class ReportFigure {
  const ReportFigure(this.label, this.value, {this.warn = false});
  final String label, value;
  final bool warn;
}

class ReportBar {
  const ReportBar(
    this.label,
    this.value,
    this.fraction, {
    this.negative = false,
  });
  final String label, value;

  /// 0..1 of the largest bar in the section.
  final double fraction;
  final bool negative;
}

class ReportRow {
  const ReportRow(this.title, this.trailing, {this.subtitle});
  final String title, trailing;
  final String? subtitle;
}

class ReportSection {
  const ReportSection(
    this.title, {
    this.note,
    this.figures = const [],
    this.bars = const [],
    this.rows = const [],
    this.empty,
  });
  final String title;
  final String? note, empty;
  final List<ReportFigure> figures;
  final List<ReportBar> bars;
  final List<ReportRow> rows;
  bool get isEmpty => figures.isEmpty && bars.isEmpty && rows.isEmpty;
}

/// Money that may be negative (a loss month).
String signedInr(int paise) => paise < 0
    ? '−${formatCompactInrPaise(-paise)}'
    : formatCompactInrPaise(paise);

String _percent(Object? value) => value == null ? '–' : '$value%';

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];
String monthLabel(String key) {
  final parts = key.split('-');
  return '${_months[int.parse(parts[1]) - 1]} ${parts[0]}';
}

String dayLabel(String key) {
  final parts = key.split('-');
  return '${int.parse(parts[2])} ${_months[int.parse(parts[1]) - 1]}';
}

String _title(String wire) => wire.isEmpty
    ? wire
    : wire[0].toUpperCase() + wire.substring(1).replaceAll('_', ' ');

List<Map<String, dynamic>> _list(Object? value) => [
  for (final row in (value as List? ?? const [])) row as Map<String, dynamic>,
];

List<ReportBar> _bars(
  List<Map<String, dynamic>> rows,
  String field, {
  required String Function(Map<String, dynamic>) label,
  required String Function(num) value,
}) {
  final top = rows.fold<num>(0, (max, row) {
    final v = (row[field] as num).abs();
    return v > max ? v : max;
  });
  return [
    for (final row in rows)
      ReportBar(
        label(row),
        value(row[field] as num),
        top == 0 ? 0 : (row[field] as num).abs() / top,
        negative: (row[field] as num) < 0,
      ),
  ];
}

String _member(Map<String, dynamic> row, bool allBranches) => [
  row['memberCode'],
  if (allBranches) row['branch'],
  row['phone'],
].whereType<String>().join(' · ');

List<ReportSection> reportSections(ReportData data) {
  final r = data.report;
  int i(String key) => (r[key] as num? ?? 0).toInt();
  final totals = (r['totals'] as Map?)?.cast<String, dynamic>() ?? const {};
  int t(String key) => (totals[key] as num? ?? 0).toInt();
  switch (data.kind) {
    case ReportKind.profitLoss:
      final months = _list(r['months']);
      return [
        ReportSection(
          'Summary',
          figures: [
            ReportFigure('Income', signedInr(t('incomePaise'))),
            ReportFigure('Expenses', signedInr(t('expensesPaise'))),
            ReportFigure('Trainer commission', signedInr(t('commissionPaise'))),
            ReportFigure(
              'Profit',
              signedInr(t('profitPaise')),
              warn: t('profitPaise') < 0,
            ),
            ReportFigure('Margin', _percent(totals['marginPercent'])),
          ],
        ),
        ReportSection(
          'Profit by month',
          bars: _bars(
            months,
            'profitPaise',
            label: (row) => monthLabel(row['key'] as String),
            value: (v) => signedInr(v.toInt()),
          ),
        ),
        ReportSection(
          'Month by month',
          rows: [
            for (final row in months)
              ReportRow(
                monthLabel(row['key'] as String),
                signedInr((row['profitPaise'] as num).toInt()),
                subtitle:
                    'Membership ${signedInr((row['membershipPaise'] as num).toInt())} · '
                    'PT ${signedInr((row['ptPaise'] as num).toInt())} · '
                    'Expenses ${signedInr((row['expensesPaise'] as num).toInt())} · '
                    'Commission ${signedInr((row['commissionPaise'] as num).toInt())}',
              ),
          ],
        ),
        ReportSection(
          'Expenses by category',
          empty: 'No expenses recorded in this period.',
          bars: _bars(
            _list(r['expensesByCategory']),
            'amountPaise',
            label: (row) => _title(row['key'] as String),
            value: (v) => signedInr(v.toInt()),
          ),
        ),
      ];
    case ReportKind.collections:
      return [
        ReportSection(
          'Summary',
          figures: [
            ReportFigure('Collected', signedInr(t('amountPaise'))),
            ReportFigure('Payments', '${t('count')}'),
            ReportFigure('Average payment', signedInr(t('averagePaise'))),
          ],
        ),
        ReportSection(
          'By method',
          empty: 'No payments in this period.',
          bars: _bars(
            _list(r['byMethod']),
            'amountPaise',
            label: (row) => _title(row['key'] as String),
            value: (v) => signedInr(v.toInt()),
          ),
        ),
        ReportSection(
          'By plan',
          bars: _bars(
            _list(r['byPlan']),
            'amountPaise',
            label: (row) => row['key'] as String,
            value: (v) => signedInr(v.toInt()),
          ),
        ),
        ReportSection(
          'By day',
          bars: _bars(
            _list(r['byDay']),
            'amountPaise',
            label: (row) => dayLabel(row['key'] as String),
            value: (v) => signedInr(v.toInt()),
          ),
        ),
      ];
    case ReportKind.members:
      return [
        ReportSection(
          'Summary',
          figures: [
            ReportFigure('New members added', '${i('joined')}'),
            ReportFigure('Plans started', '${i('started')}'),
            ReportFigure('First-time', '${i('firstTime')}'),
            ReportFigure('Renewals', '${i('renewals')}'),
          ],
        ),
        ReportSection(
          'Retention',
          note:
              'Of memberships that ended in this period, how many renewed within 30 days.',
          figures: [
            ReportFigure('Ended', '${i('expired')}'),
            ReportFigure('Renewed', '${i('renewed')}'),
            ReportFigure(
              'Did not return',
              '${i('churned')}',
              warn: i('churned') > 0,
            ),
            ReportFigure('Renewal rate', _percent(r['renewalRatePercent'])),
          ],
        ),
        ReportSection(
          'Active members at month end',
          bars: _bars(
            _list(r['activeAtMonthEnd']),
            'count',
            label: (row) => monthLabel(row['key'] as String),
            value: (v) => '$v',
          ),
        ),
        ReportSection(
          'Plans started',
          empty: 'No plans started in this period.',
          bars: _bars(
            _list(r['startedByPlan']),
            'count',
            label: (row) => row['key'] as String,
            value: (v) => '$v',
          ),
        ),
      ];
    case ReportKind.attendance:
      const weekdays = {
        'mon': 'Mon',
        'tue': 'Tue',
        'wed': 'Wed',
        'thu': 'Thu',
        'fri': 'Fri',
        'sat': 'Sat',
        'sun': 'Sun',
      };
      final hours = _list(
        r['byHour'],
      ).where((row) => (row['count'] as num) > 0).toList();
      return [
        ReportSection(
          'Summary',
          figures: [
            ReportFigure('Visits', '${i('visits')}'),
            ReportFigure('Members who came', '${i('uniqueMembers')}'),
            ReportFigure('Per day', '${r['averagePerDay'] ?? 0}'),
            ReportFigure('Visits per member', '${r['visitsPerMember'] ?? 0}'),
          ],
        ),
        ReportSection(
          'Busiest days',
          bars: _bars(
            _list(r['byWeekday']),
            'count',
            label: (row) => weekdays[row['key']] ?? row['key'] as String,
            value: (v) => '$v',
          ),
        ),
        ReportSection(
          'Busiest hours',
          empty: 'No check-ins in this period.',
          bars: _bars(
            hours,
            'count',
            label: (row) => '${row['key']}:00',
            value: (v) => '$v',
          ),
        ),
        ReportSection(
          'Stopped coming',
          note:
              '${i('stoppedComingCount')} of ${i('activeMembers')} active members have not visited for 14+ days.',
          empty: 'Every active member visited in the last 14 days.',
          rows: [
            for (final row in _list(r['stoppedComing']))
              ReportRow(
                row['name'] as String,
                row['daysAway'] == null
                    ? 'Never visited'
                    : '${row['daysAway']} days away',
                subtitle: _member(row, data.allBranches),
              ),
          ],
        ),
      ];
    case ReportKind.dues:
      return [
        ReportSection(
          'Summary',
          note: 'As of today.',
          figures: [
            ReportFigure(
              'Total owed',
              signedInr(i('totalDuesPaise')),
              warn: i('totalDuesPaise') > 0,
            ),
            ReportFigure('Memberships', signedInr(i('membershipDuesPaise'))),
            ReportFigure('PT packages', signedInr(i('ptDuesPaise'))),
            ReportFigure('Members owing', '${i('membersOwing')}'),
          ],
        ),
        ReportSection(
          'How old the dues are',
          note: 'Days since the unpaid membership started.',
          bars: _bars(
            _list(r['ageing']),
            'amountPaise',
            label: (row) => '${row['key']} days',
            value: (v) => signedInr(v.toInt()),
          ),
        ),
        ReportSection(
          'Who owes the most',
          empty: 'Nobody owes anything.',
          rows: [
            for (final row in _list(r['topDebtors']))
              ReportRow(
                row['name'] as String,
                signedInr((row['amountPaise'] as num).toInt()),
                subtitle:
                    '${_member(row, data.allBranches)} · oldest ${row['oldestDays']} days',
              ),
          ],
        ),
      ];
    case ReportKind.leads:
      return [
        ReportSection(
          'Funnel',
          figures: [
            ReportFigure('Enquiries', '${i('created')}'),
            ReportFigure('Took a trial', '${i('trialed')}'),
            ReportFigure('Joined', '${i('joined')}'),
            ReportFigure('Lost', '${i('lost')}'),
            ReportFigure('Still open', '${i('open')}'),
            ReportFigure('Conversion', _percent(r['conversionPercent'])),
          ],
        ),
        ReportSection(
          'By source',
          empty: 'No enquiries in this period.',
          rows: [
            for (final row in _list(r['bySource']))
              ReportRow(
                _title(row['key'] as String),
                '${row['count']}',
                subtitle:
                    '${row['joined']} joined · ${_percent(row['conversionPercent'])}',
              ),
          ],
        ),
        ReportSection(
          'Why enquiries were lost',
          empty: 'No lost enquiries.',
          bars: _bars(
            _list(r['lostReasons']),
            'count',
            label: (row) => _title(row['key'] as String),
            value: (v) => '$v',
          ),
        ),
      ];
    case ReportKind.trainers:
      return [
        ReportSection(
          'Summary',
          figures: [
            ReportFigure('PT sessions', '${t('sessions')}'),
            ReportFigure('PT collected', signedInr(t('ptCollectedPaise'))),
            ReportFigure('Commission', signedInr(t('commissionPaise'))),
            ReportFigure('PT clients', '${t('ptClients')}'),
          ],
        ),
        ReportSection(
          'Per trainer',
          empty: 'No trainers yet.',
          rows: [
            for (final row in _list(r['trainers']))
              ReportRow(
                row['name'] as String,
                signedInr((row['ptCollectedPaise'] as num).toInt()),
                subtitle: [
                  if (data.allBranches) row['branch'],
                  '${row['sessions']} sessions',
                  '${row['ptClients']} PT clients',
                  '${row['assignedMembers']} members',
                  'commission ${signedInr((row['commissionPaise'] as num).toInt())}',
                ].join(' · '),
              ),
          ],
        ),
      ];
    case ReportKind.plans:
      return [
        ReportSection(
          'Summary',
          figures: [
            ReportFigure('Plans sold', '${t('sold')}'),
            ReportFigure('Plan value sold', signedInr(t('revenuePaise'))),
            ReportFigure('Active members now', '${t('activeMembers')}'),
          ],
        ),
        ReportSection(
          'Per plan',
          note: 'Value is the plan price, whether or not it is paid yet.',
          empty: 'No plans yet.',
          rows: [
            for (final row in _list(r['plans']))
              ReportRow(
                row['key'] as String,
                signedInr((row['revenuePaise'] as num).toInt()),
                subtitle:
                    '${row['sold']} sold · ${row['activeMembers']} active now · ${_percent(row['sharePercent'])} of value',
              ),
          ],
        ),
      ];
  }
}
