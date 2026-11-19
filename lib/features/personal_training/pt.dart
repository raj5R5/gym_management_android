import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderOrFamily;

import '../admin_dashboard/providers/dashboard_providers.dart';
import '../auth/data/auth_failure.dart';
import '../auth/models/auth_models.dart';
import '../auth/models/session_state.dart';
import '../auth/providers/auth_providers.dart';
import '../auth/providers/session_controller.dart';

enum PtStatus {
  active('active', 'Active'),
  completed('completed', 'Completed'),
  cancelled('cancelled', 'Cancelled');

  const PtStatus(this.wire, this.label);
  final String wire, label;
  static PtStatus parse(String wire) =>
      values.firstWhere((value) => value.wire == wire);
}

DateTime? _day(Object? value) => value is String ? DateTime.parse(value) : null;

class PtPerson {
  PtPerson.fromJson(Map<String, dynamic> json)
    : id = json['id'] as String,
      name = json['name'] as String,
      code = (json['memberCode'] ?? json['trainerCode']) as String,
      phone = json['phone'] as String?;
  final String id, name, code;
  final String? phone;
}

class PtSessionEntry {
  PtSessionEntry.fromJson(Map<String, dynamic> json)
    : id = json['id'] as String,
      date = DateTime.parse(json['sessionDate'] as String),
      note = json['note'] as String?;
  final String id;
  final DateTime date;
  final String? note;
}

class PtPaymentEntry {
  PtPaymentEntry.fromJson(Map<String, dynamic> json)
    : id = json['id'] as String,
      amountPaise = json['amountPaise'] as int,
      method = json['method'] as String,
      reference = json['reference'] as String?,
      paidAt = DateTime.parse(json['paidAt'] as String).toLocal(),
      commissionPaise = json['commissionPaise'] as int;
  final String id, method;
  final String? reference;
  final int amountPaise, commissionPaise;
  final DateTime paidAt;
}

/// A PT package. Money fields are null for trainers: the server omits them.
class PtPackage {
  PtPackage.fromJson(Map<String, dynamic> json)
    : id = json['id'] as String,
      name = json['name'] as String,
      member = json['member'] == null
          ? null
          : PtPerson.fromJson(json['member'] as Map<String, dynamic>),
      trainer = json['trainer'] == null
          ? null
          : PtPerson.fromJson(json['trainer'] as Map<String, dynamic>),
      sessionsTotal = json['sessionsTotal'] as int,
      sessionsUsed = json['sessionsUsed'] as int,
      startDate = DateTime.parse(json['startDate'] as String),
      expiresOn = _day(json['expiresOn']),
      expired = json['expired'] as bool,
      status = PtStatus.parse(json['status'] as String),
      pricePaise = json['pricePaise'] as int?,
      paidPaise = json['paidPaise'] as int?,
      balancePaise = json['balancePaise'] as int?,
      commissionPercent = (json['commissionPercent'] as num?)?.toDouble(),
      sessions = [
        for (final row in (json['sessions'] as List? ?? const []))
          PtSessionEntry.fromJson(row as Map<String, dynamic>),
      ],
      payments = [
        for (final row in (json['payments'] as List? ?? const []))
          PtPaymentEntry.fromJson(row as Map<String, dynamic>),
      ];
  final String id, name;
  final PtPerson? member, trainer;
  final int sessionsTotal, sessionsUsed;
  final DateTime startDate;
  final DateTime? expiresOn;
  final bool expired;
  final PtStatus status;
  final int? pricePaise, paidPaise, balancePaise;
  final double? commissionPercent;
  final List<PtSessionEntry> sessions;
  final List<PtPaymentEntry> payments;

  int get sessionsLeft => sessionsTotal - sessionsUsed;
  bool get canLogSession =>
      status == PtStatus.active && !expired && sessionsLeft > 0;
  bool get hasDue => (balancePaise ?? 0) > 0 && status != PtStatus.cancelled;
}

class CommissionRate {
  CommissionRate.fromJson(Map<String, dynamic> json)
    : trainer = PtPerson.fromJson(json['trainer'] as Map<String, dynamic>),
      percent = (json['percent'] as num).toDouble();
  final PtPerson trainer;
  final double percent;
}

class CommissionRow {
  CommissionRow.fromJson(Map<String, dynamic> json)
    : trainer = PtPerson.fromJson(json['trainer'] as Map<String, dynamic>),
      collectedPaise = json['collectedPaise'] as int,
      commissionPaise = json['commissionPaise'] as int,
      payments = json['payments'] as int,
      sessions = json['sessions'] as int;
  final PtPerson trainer;
  final int collectedPaise, commissionPaise, payments, sessions;
}

class CommissionReport {
  CommissionReport.fromJson(Map<String, dynamic> json)
    : from = DateTime.parse((json['period'] as Map)['from'] as String),
      to = DateTime.parse((json['period'] as Map)['to'] as String),
      rows = [
        for (final row in json['trainers'] as List)
          CommissionRow.fromJson(row as Map<String, dynamic>),
      ],
      collectedPaise = (json['totals'] as Map)['collectedPaise'] as int,
      commissionPaise = (json['totals'] as Map)['commissionPaise'] as int,
      sessions = (json['totals'] as Map)['sessions'] as int;
  final DateTime from, to;
  final List<CommissionRow> rows;
  final int collectedPaise, commissionPaise, sessions;
}

enum CommissionPeriod {
  thisMonth('thisMonth', 'This month'),
  last7Days('last7Days', 'Last 7 days'),
  today('today', 'Today');

  const CommissionPeriod(this.wire, this.label);
  final String wire, label;
}

class PtFailure implements Exception {
  const PtFailure(this.message);
  final String message;
  factory PtFailure.fromDio(DioException error) {
    final data = error.response?.data;
    final failure = data is Map ? data['error'] : null;
    final code = failure is Map ? failure['code'] : null;
    return PtFailure(switch (code) {
      'PT_PACKAGE_NOT_FOUND' => 'This package is no longer available.',
      'PT_PACKAGE_CLOSED' => 'This package is completed or cancelled.',
      'PT_PACKAGE_EXPIRED' => 'This package expired before that date.',
      'PT_PAYMENT_EXCEEDS_BALANCE' =>
        'A payment cannot be more than the amount still unpaid.',
      'PT_PARTICIPANT_INACTIVE' =>
        'The member and trainer must both be active.',
      'PT_SESSION_DATE_INVALID' =>
        'Pick a session date between the package start and today.',
      'MEMBER_NOT_FOUND' => 'That member is not in this gym.',
      'TRAINER_NOT_FOUND' => 'That trainer is not in this gym.',
      'VALIDATION_ERROR' => 'Check the details and try again.',
      _ => AuthFailure.fromDio(error).message,
    });
  }
  @override
  String toString() => 'PtFailure: $message';
}

String ptIsoDay(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';

typedef PtPackageQuery = ({
  String? memberId,
  String? trainerId,
  PtStatus? status,
});

class PtRepository {
  PtRepository(this._client);
  final Dio _client;

  String _base(String gymId) {
    if (!RegExp(r'^[a-fA-F0-9]{24}$').hasMatch(gymId)) {
      throw const PtFailure('Invalid gym.');
    }
    return 'gyms/$gymId/pt';
  }

  Future<T> _call<T>(
    Future<Response<dynamic>> Function() call,
    T Function(dynamic data) parse,
  ) async {
    try {
      final body = (await call()).data;
      if (body is! Map<String, dynamic> || body['success'] != true) {
        throw const PtFailure('Unexpected response.');
      }
      return parse(body['data']);
    } on DioException catch (error) {
      throw PtFailure.fromDio(error);
    } on TypeError {
      throw const PtFailure('The server returned unexpected data.');
    }
  }

  PtPackage _package(dynamic data) =>
      PtPackage.fromJson(data as Map<String, dynamic>);

  Future<List<PtPackage>> list(String gymId, PtPackageQuery query) => _call(
    () => _client.get<dynamic>(
      '${_base(gymId)}/packages',
      queryParameters: {
        'memberId': ?query.memberId,
        'trainerId': ?query.trainerId,
        'status': ?query.status?.wire,
        'limit': '100',
      },
    ),
    (data) => [
      for (final row in (data as Map)['data'] as List)
        PtPackage.fromJson(row as Map<String, dynamic>),
    ],
  );

  Future<PtPackage> get(String gymId, String packageId) => _call(
    () => _client.get<dynamic>('${_base(gymId)}/packages/$packageId'),
    _package,
  );

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
  }) => _call(
    () => _client.post<dynamic>(
      '${_base(gymId)}/packages',
      data: {
        'memberId': memberId,
        'trainerId': trainerId,
        'name': name,
        'sessions': sessions,
        'pricePaise': pricePaise,
        'validDays': ?validDays,
        if (paidNowPaise != null && paidNowPaise > 0)
          'payment': {
            'amountPaise': paidNowPaise,
            'method': method,
            'reference': ?reference,
          },
      },
    ),
    _package,
  );

  Future<PtPackage> addPayment(
    String gymId,
    String packageId, {
    required int amountPaise,
    String method = 'cash',
    String? reference,
  }) => _call(
    () => _client.post<dynamic>(
      '${_base(gymId)}/packages/$packageId/payments',
      data: {
        'amountPaise': amountPaise,
        'method': method,
        'reference': ?reference,
      },
    ),
    _package,
  );

  Future<PtPackage> logSession(
    String gymId,
    String packageId, {
    DateTime? date,
    String? note,
  }) => _call(
    () => _client.post<dynamic>(
      '${_base(gymId)}/packages/$packageId/sessions',
      data: {if (date != null) 'sessionDate': ptIsoDay(date), 'note': ?note},
    ),
    _package,
  );

  Future<PtPackage> cancel(String gymId, String packageId) => _call(
    () => _client.post<dynamic>('${_base(gymId)}/packages/$packageId/cancel'),
    _package,
  );

  Future<List<CommissionRate>> rates(String gymId) => _call(
    () => _client.get<dynamic>('${_base(gymId)}/rates'),
    (data) => [
      for (final row in data as List)
        CommissionRate.fromJson(row as Map<String, dynamic>),
    ],
  );

  Future<void> setRate(String gymId, String trainerId, double percent) => _call(
    () => _client.put<dynamic>(
      '${_base(gymId)}/rates/$trainerId',
      data: {'percent': percent},
    ),
    (_) {},
  );

  Future<CommissionReport> commissions(String gymId, CommissionPeriod period) =>
      _call(
        () => _client.get<dynamic>(
          '${_base(gymId)}/commissions',
          queryParameters: {'preset': period.wire},
        ),
        (data) => CommissionReport.fromJson(data as Map<String, dynamic>),
      );
}

/// The gym PT screens work in: the owner's selected gym, or for a trainer
/// (who has no admin grant) their first active trainer grant.
final ptGymIdProvider = Provider<String?>((ref) {
  final admin = ref.watch(adminGymProvider);
  if (admin != null) return admin.gymId;
  final session = ref.watch(sessionControllerProvider);
  if (session is! SessionAuthenticated ||
      session.identity.user.status != AccountStatus.active) {
    return null;
  }
  for (final grant in session.identity.gymAccess) {
    if (grant.role == AuthRole.trainer &&
        grant.status == AccountStatus.active) {
      return grant.gymId;
    }
  }
  return null;
});

final ptRepositoryProvider = Provider<PtRepository>(
  (ref) => PtRepository(ref.watch(authenticatedApiClientProvider)),
);

final ptPackagesProvider = FutureProvider.autoDispose
    .family<List<PtPackage>?, PtPackageQuery>((ref, query) {
      final gymId = ref.watch(ptGymIdProvider);
      if (gymId == null) return null;
      return ref.watch(ptRepositoryProvider).list(gymId, query);
    }, retry: (_, _) => null);

final ptPackageProvider = FutureProvider.autoDispose.family<PtPackage?, String>(
  (ref, packageId) {
    final gymId = ref.watch(ptGymIdProvider);
    if (gymId == null) return null;
    return ref.watch(ptRepositoryProvider).get(gymId, packageId);
  },
  retry: (_, _) => null,
);

final commissionRatesProvider =
    FutureProvider.autoDispose<List<CommissionRate>?>((ref) {
      final gym = ref.watch(adminGymProvider);
      if (gym == null) return null;
      return ref.watch(ptRepositoryProvider).rates(gym.gymId);
    }, retry: (_, _) => null);

final commissionReportProvider = FutureProvider.autoDispose
    .family<CommissionReport?, CommissionPeriod>((ref, period) {
      final gym = ref.watch(adminGymProvider);
      if (gym == null) return null;
      return ref.watch(ptRepositoryProvider).commissions(gym.gymId, period);
    }, retry: (_, _) => null);

/// Refreshes every PT view after a write. Pass `ref.invalidate`, or a
/// container's `invalidate` when the widget may be gone after an await.
void invalidatePt(void Function(ProviderOrFamily provider) invalidate) {
  invalidate(ptPackagesProvider);
  invalidate(ptPackageProvider);
  invalidate(commissionReportProvider);
}
