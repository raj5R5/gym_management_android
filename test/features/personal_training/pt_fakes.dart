import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gym_management_app/app/theme/app_theme.dart';
import 'package:gym_management_app/features/admin_dashboard/providers/dashboard_providers.dart';
import 'package:gym_management_app/features/auth/models/session_state.dart';
import 'package:gym_management_app/features/auth/providers/session_controller.dart';
import 'package:gym_management_app/features/personal_training/pt.dart';

const gymId = '0000000000000000000000f1';
const pkgA = '0000000000000000000000c1';
const memberA = '0000000000000000000000d1';
const trainerA = '0000000000000000000000e1';

Map<String, dynamic> ptJson({
  String id = pkgA,
  String status = 'active',
  int used = 1,
  int total = 4,
  bool money = true,
  int paid = 100000,
  bool expired = false,
}) => {
  'id': id,
  'name': 'Personal training',
  'member': {
    'id': memberA,
    'name': 'Riya Shah',
    'memberCode': 'ME001',
    'phone': '9876543210',
  },
  'trainer': {'id': trainerA, 'name': 'Vikram Rao', 'trainerCode': 'TR01'},
  'sessionsTotal': total,
  'sessionsUsed': used,
  'sessionsLeft': total - used,
  'startDate': '2026-11-01',
  'expiresOn': '2026-12-31',
  'expired': expired,
  'status': status,
  'createdAt': '2026-11-01T10:00:00.000Z',
  if (money) ...{
    'pricePaise': 400000,
    'paidPaise': paid,
    'balancePaise': 400000 - paid,
    'commissionPercent': 12.5,
  },
  'sessions': [
    {'id': 's1', 'sessionDate': '2026-11-10', 'note': 'Legs'},
  ],
  if (money)
    'payments': [
      {
        'id': 'p1',
        'amountPaise': paid,
        'method': 'cash',
        'reference': null,
        'paidAt': '2026-11-01T10:00:00.000Z',
        'commissionPercent': 12.5,
        'commissionPaise': paid ~/ 8,
      },
    ],
};

/// Records calls; returns the stored packages.
class FakePtRepository implements PtRepository {
  FakePtRepository({List<Map<String, dynamic>>? packages})
    : packages = packages ?? [ptJson()];
  final List<Map<String, dynamic>> packages;
  final calls = <String>[];

  PtPackage _one(String id) =>
      PtPackage.fromJson(packages.firstWhere((row) => row['id'] == id));

  @override
  Future<List<PtPackage>> list(String gymId, PtPackageQuery query) async => [
    for (final row in packages)
      if (query.memberId == null ||
          (row['member'] as Map)['id'] == query.memberId)
        PtPackage.fromJson(row),
  ];

  @override
  Future<PtPackage> get(String gymId, String packageId) async =>
      _one(packageId);

  @override
  Future<PtPackage> create(
    String gymId, {
    required String memberId,
    required String trainerId,
    required String name,
    required int sessions,
    required int pricePaise,
    int? validDays,
    int? paidNowPaise,
    String method = 'cash',
    String? reference,
  }) async {
    calls.add(
      'create:$memberId:$trainerId:$sessions:$pricePaise:$validDays:$paidNowPaise:$method',
    );
    final json = ptJson(
      id: '0000000000000000000000c9',
      total: sessions,
      used: 0,
    );
    packages.add(json);
    return PtPackage.fromJson(json);
  }

  @override
  Future<PtPackage> addPayment(
    String gymId,
    String packageId, {
    required int amountPaise,
    String method = 'cash',
    String? reference,
  }) async {
    calls.add('pay:$amountPaise:$method');
    return _one(packageId);
  }

  @override
  Future<PtPackage> logSession(
    String gymId,
    String packageId, {
    DateTime? date,
    String? note,
  }) async {
    calls.add('session:$note');
    final row = packages.firstWhere((row) => row['id'] == packageId);
    row['sessionsUsed'] = (row['sessionsUsed'] as int) + 1;
    return PtPackage.fromJson(row);
  }

  @override
  Future<PtPackage> cancel(String gymId, String packageId) async {
    calls.add('cancel');
    return _one(packageId);
  }

  @override
  Future<List<CommissionRate>> rates(String gymId) async => [
    CommissionRate.fromJson({
      'trainer': {'id': trainerA, 'name': 'Vikram Rao', 'trainerCode': 'TR01'},
      'percent': 12.5,
    }),
  ];

  @override
  Future<void> setRate(String gymId, String trainerId, double percent) async =>
      calls.add('rate:$trainerId:$percent');

  @override
  Future<CommissionReport> commissions(
    String gymId,
    CommissionPeriod period,
  ) async => CommissionReport.fromJson({
    'period': {'from': '2026-11-01', 'to': '2026-11-30'},
    'trainers': [
      {
        'trainer': {
          'id': trainerA,
          'name': 'Vikram Rao',
          'trainerCode': 'TR01',
        },
        'collectedPaise': 300000,
        'commissionPaise': 37500,
        'payments': 2,
        'sessions': 5,
      },
    ],
    'totals': {
      'collectedPaise': 300000,
      'commissionPaise': 37500,
      'sessions': 5,
    },
  });
}

class _FixedGym extends AdminGymController {
  @override
  AdminGymContext? build() => (userId: 'u1', gymId: gymId);
}

class _NoSession extends SessionController {
  @override
  SessionState build() => const SessionUnauthenticated();
}

Widget ptHarness(
  FakePtRepository repository,
  Widget child, {
  List<dynamic> overrides = const [],
}) => ProviderScope(
  overrides: [
    ...overrides.cast(),
    adminGymProvider.overrideWith(_FixedGym.new),
    ptRepositoryProvider.overrideWithValue(repository),
    sessionControllerProvider.overrideWith(_NoSession.new),
  ],
  child: MaterialApp(
    theme: AppTheme.dark,
    home: Scaffold(body: child),
  ),
);
