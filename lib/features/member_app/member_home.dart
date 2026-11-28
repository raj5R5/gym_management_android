import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/data/auth_failure.dart';
import '../auth/models/auth_models.dart';
import '../auth/models/session_state.dart';
import '../auth/providers/auth_providers.dart';
import '../auth/providers/session_controller.dart';

DateTime? _day(Object? value) => value is String ? DateTime.parse(value) : null;

class MemberHomeMembership {
  MemberHomeMembership.fromJson(Map<String, dynamic> json)
    : state = json['state'] as String,
      planName = json['planName'] as String,
      startDate = DateTime.parse(json['startDate'] as String),
      endDate = DateTime.parse(json['endDate'] as String),
      daysLeft = json['daysLeft'] as int,
      daysSinceExpiry = json['daysSinceExpiry'] as int? ?? 0,
      expiringSoon = json['expiringSoon'] as bool? ?? false,
      renewedAhead = json['renewedAhead'] as bool? ?? false,
      frozenUntil = _day(json['frozenUntil']);

  /// `active`, `upcoming` or `expired`.
  final String state;
  final String planName;

  /// [endDate] is exclusive: the last day is the one before it.
  final DateTime startDate, endDate;
  final int daysLeft, daysSinceExpiry;
  final bool expiringSoon, renewedAhead;
  final DateTime? frozenUntil;

  DateTime get lastDay => endDate.subtract(const Duration(days: 1));
}

class MemberHomePt {
  MemberHomePt.fromJson(Map<String, dynamic> json)
    : id = json['id'] as String,
      name = json['name'] as String,
      trainerName = json['trainerName'] as String?,
      sessionsTotal = json['sessionsTotal'] as int,
      sessionsLeft = json['sessionsLeft'] as int,
      expiresOn = _day(json['expiresOn']),
      expired = json['expired'] as bool,
      balancePaise = json['balancePaise'] as int;
  final String id, name;
  final String? trainerName;
  final int sessionsTotal, sessionsLeft, balancePaise;
  final DateTime? expiresOn;
  final bool expired;
}

class MemberHome {
  MemberHome.fromJson(Map<String, dynamic> json)
    : today = DateTime.parse(json['today'] as String),
      gymName = (json['gym'] as Map)['name'] as String,
      gymPhone = (json['gym'] as Map)['phone'] as String?,
      gymAddress = (json['gym'] as Map)['address'] as String?,
      upiId = (json['gym'] as Map)['upiId'] as String?,
      upiPayeeName = (json['gym'] as Map)['upiPayeeName'] as String?,
      memberId = (json['member'] as Map)['id'] as String,
      memberCode = (json['member'] as Map)['memberCode'] as String,
      firstName = (json['member'] as Map)['firstName'] as String,
      lastName = (json['member'] as Map)['lastName'] as String,
      membership = json['membership'] == null
          ? null
          : MemberHomeMembership.fromJson(
              json['membership'] as Map<String, dynamic>,
            ),
      balancePaise = (json['dues'] as Map)['balancePaise'] as int,
      dueSubscriptionId = (json['dues'] as Map)['dueSubscriptionId'] as String?,
      pendingClaimPaise =
          (json['dues'] as Map)['pendingClaimPaise'] as int? ?? 0,
      visitsThisMonth = (json['visits'] as Map)['thisMonth'] as int,
      lastVisit = _day((json['visits'] as Map)['lastVisitDate']),
      visitedToday = (json['visits'] as Map)['visitedToday'] as bool,
      weekStreak = (json['visits'] as Map)['weekStreak'] as int,
      recentVisits = [
        for (final day in (json['visits'] as Map)['recent'] as List)
          DateTime.parse(day as String),
      ],
      pt = [
        for (final row in json['pt'] as List)
          MemberHomePt.fromJson(row as Map<String, dynamic>),
      ];
  final DateTime today;
  final String gymName, memberId, memberCode, firstName, lastName;
  final String? gymPhone, gymAddress, upiId, upiPayeeName, dueSubscriptionId;
  final MemberHomeMembership? membership;
  final int balancePaise, visitsThisMonth, weekStreak;

  /// UPI payments reported by the member that the gym has not confirmed yet.
  final int pendingClaimPaise;

  /// What the member can still report as paid.
  int get claimablePaise => balancePaise - pendingClaimPaise > 0
      ? balancePaise - pendingClaimPaise
      : 0;
  final DateTime? lastVisit;
  final bool visitedToday;
  final List<DateTime> recentVisits;
  final List<MemberHomePt> pt;
}

class MemberPaymentEntry {
  MemberPaymentEntry.fromJson(Map<String, dynamic> json)
    : id = json['id'] as String,
      amountPaise = json['amountPaise'] as int,
      method = json['paymentMethod'] as String,
      paidAt = DateTime.parse(json['paidAt'] as String).toLocal();
  final String id, method;
  final int amountPaise;
  final DateTime paidAt;
}

/// A UPI payment the member reported, as they see it.
class MemberClaim {
  MemberClaim.fromJson(Map<String, dynamic> json)
    : amountPaise = json['amountPaise'] as int,
      status = json['status'] as String,
      rejectReason = json['rejectReason'] as String?,
      createdAt = DateTime.parse(json['createdAt'] as String).toLocal();
  final int amountPaise;

  /// `pending`, `confirmed` or `rejected`.
  final String status;
  final String? rejectReason;
  final DateTime createdAt;
}

class MemberAppFailure implements Exception {
  const MemberAppFailure(this.message);
  final String message;
  @override
  String toString() => 'MemberAppFailure: $message';
}

/// Reads for the signed-in member; the server resolves who they are.
class MemberHomeRepository {
  MemberHomeRepository(this._client);
  final Dio _client;

  Future<T> _get<T>(String path, T Function(dynamic data) parse) =>
      _send(() => _client.get<dynamic>(path), parse);

  Future<T> _send<T>(
    Future<Response<dynamic>> Function() call,
    T Function(dynamic data) parse,
  ) async {
    try {
      final body = (await call()).data;
      if (body is! Map<String, dynamic> || body['success'] != true) {
        throw const MemberAppFailure('Unexpected response.');
      }
      return parse(body['data']);
    } on DioException catch (error) {
      final data = error.response?.data;
      final failure = data is Map ? data['error'] : null;
      final code = failure is Map ? failure['code'] : null;
      throw MemberAppFailure(switch (code) {
        'CLAIM_EXCEEDS_DUE' => 'That is more than the amount due.',
        'DUPLICATE_CLAIM_REFERENCE' =>
          'This UPI transaction ID was already reported.',
        'VALIDATION_ERROR' => 'Enter the 12-digit UPI transaction ID.',
        'RATE_LIMITED' => 'Too many tries. Wait a few minutes.',
        'FORBIDDEN' =>
          'Your app access for this gym is off. Please ask the gym.',
        _ => AuthFailure.fromDio(error).message,
      });
    } on TypeError {
      throw const MemberAppFailure('The server returned unexpected data.');
    }
  }

  Future<MemberHome> home(String gymId) => _get(
    'me/gyms/$gymId/home',
    (data) => MemberHome.fromJson(data as Map<String, dynamic>),
  );

  /// Reports a UPI payment for the gym to confirm.
  Future<void> reportUpiPayment(
    String gymId, {
    required int amountPaise,
    required String reference,
  }) => _send(
    () => _client.post<dynamic>(
      'me/gyms/$gymId/payment-claims',
      data: {'amountPaise': amountPaise, 'reference': reference},
    ),
    (_) {},
  );

  /// Latest UPI reports, newest first.
  Future<List<MemberClaim>> claims(String gymId) => _get(
    'me/gyms/$gymId/payment-claims',
    (data) => [
      for (final row in data as List)
        MemberClaim.fromJson(row as Map<String, dynamic>),
    ],
  );

  Future<List<MemberPaymentEntry>> payments(String gymId) => _get(
    'me/gyms/$gymId/payments?limit=50',
    (data) => [
      for (final row in (data as Map)['payments'] as List)
        MemberPaymentEntry.fromJson(row as Map<String, dynamic>),
    ],
  );
}

final memberHomeRepositoryProvider = Provider<MemberHomeRepository>(
  (ref) => MemberHomeRepository(ref.watch(authenticatedApiClientProvider)),
);

/// The gyms the signed-in person is an active member of.
final memberGymsProvider = Provider<List<AuthGymAccess>>((ref) {
  final session = ref.watch(sessionControllerProvider);
  if (session is! SessionAuthenticated ||
      session.identity.user.status != AccountStatus.active) {
    return const [];
  }
  return [
    for (final grant in session.identity.gymAccess)
      if (grant.role == AuthRole.member && grant.status == AccountStatus.active)
        grant,
  ];
});

/// The gym a member of several gyms picked; null means the first one.
class MemberGymChoice extends Notifier<String?> {
  @override
  String? build() => null;
  void choose(String gymId) => state = gymId;
}

final memberGymChoiceProvider = NotifierProvider<MemberGymChoice, String?>(
  MemberGymChoice.new,
);

/// The member gym being shown: the one picked, else the first.
final memberGymIdProvider = Provider<String?>((ref) {
  final gyms = ref.watch(memberGymsProvider);
  if (gyms.isEmpty) return null;
  final chosen = ref.watch(memberGymChoiceProvider);
  return gyms.any((grant) => grant.gymId == chosen) ? chosen : gyms.first.gymId;
});

final memberHomeProvider = FutureProvider.autoDispose<MemberHome?>((ref) {
  final gymId = ref.watch(memberGymIdProvider);
  if (gymId == null) return null;
  return ref.watch(memberHomeRepositoryProvider).home(gymId);
}, retry: (_, _) => null);

final memberClaimsProvider = FutureProvider.autoDispose<List<MemberClaim>?>((
  ref,
) {
  final gymId = ref.watch(memberGymIdProvider);
  if (gymId == null) return null;
  return ref.watch(memberHomeRepositoryProvider).claims(gymId);
}, retry: (_, _) => null);

/// The newest report when the gym turned it down in the last two weeks.
MemberClaim? recentRejection(List<MemberClaim>? claims, DateTime now) {
  final latest = claims == null || claims.isEmpty ? null : claims.first;
  if (latest == null || latest.status != 'rejected') return null;
  return now.difference(latest.createdAt).inDays <= 14 ? latest : null;
}

final memberPaymentsProvider =
    FutureProvider.autoDispose<List<MemberPaymentEntry>?>((ref) {
      final gymId = ref.watch(memberGymIdProvider);
      if (gymId == null) return null;
      return ref.watch(memberHomeRepositoryProvider).payments(gymId);
    }, retry: (_, _) => null);
