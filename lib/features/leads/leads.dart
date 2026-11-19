import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../admin_dashboard/providers/dashboard_providers.dart';
import '../auth/data/auth_failure.dart';
import '../auth/providers/auth_providers.dart';
import '../members/models/member_models.dart';

enum LeadStatus {
  newLead('new', 'New'),
  contacted('contacted', 'Contacted'),
  trial('trial', 'On trial'),
  joined('joined', 'Joined'),
  lost('lost', 'Lost');

  const LeadStatus(this.wire, this.label);
  final String wire, label;
  static LeadStatus parse(String wire) =>
      values.firstWhere((value) => value.wire == wire);
  bool get open => this == newLead || this == contacted || this == trial;
}

enum LeadSource {
  walkIn('walk_in', 'Walk-in'),
  phoneCall('phone_call', 'Phone call'),
  whatsapp('whatsapp', 'WhatsApp'),
  instagram('instagram', 'Instagram'),
  facebook('facebook', 'Facebook'),
  google('google', 'Google'),
  website('website', 'Website'),
  referral('referral', 'Referral'),
  other('other', 'Other');

  const LeadSource(this.wire, this.label);
  final String wire, label;
  static LeadSource parse(String wire) => values.firstWhere(
    (value) => value.wire == wire,
    orElse: () => LeadSource.other,
  );
}

/// Filters on the Enquiries screen; [due] is open enquiries to follow up today.
enum LeadFilter { due, open, newLead, contacted, trial, joined, lost }

extension LeadFilterText on LeadFilter {
  String get label => switch (this) {
    LeadFilter.due => 'Follow up',
    LeadFilter.open => 'Open',
    LeadFilter.newLead => 'New',
    LeadFilter.contacted => 'Contacted',
    LeadFilter.trial => 'On trial',
    LeadFilter.joined => 'Joined',
    LeadFilter.lost => 'Lost',
  };
  Map<String, String> get parameters => switch (this) {
    LeadFilter.due => {'followUp': 'due'},
    LeadFilter.open => {'status': 'open'},
    LeadFilter.newLead => {'status': 'new'},
    LeadFilter.contacted => {'status': 'contacted'},
    LeadFilter.trial => {'status': 'trial'},
    LeadFilter.joined => {'status': 'joined'},
    LeadFilter.lost => {'status': 'lost'},
  };
  String get countKey => switch (this) {
    LeadFilter.due => 'followUpsDue',
    LeadFilter.newLead => 'new',
    _ => name,
  };
}

DateTime? _day(Object? value) => value is String ? DateTime.parse(value) : null;

class LeadPerson {
  LeadPerson.fromJson(Map<String, dynamic> json)
    : id = json['id'] as String,
      name = json['name'] as String,
      memberCode = json['memberCode'] as String;
  final String id, name, memberCode;
}

class LeadNote {
  LeadNote.fromJson(Map<String, dynamic> json)
    : text = json['text'] as String,
      createdAt = DateTime.parse(json['createdAt'] as String).toLocal();
  final String text;
  final DateTime createdAt;
}

class Lead {
  Lead.fromJson(Map<String, dynamic> json)
    : id = json['id'] as String,
      firstName = json['firstName'] as String,
      lastName = json['lastName'] as String?,
      phone = json['phone'] as String,
      source = LeadSource.parse(json['source'] as String),
      status = LeadStatus.parse(json['status'] as String),
      nextFollowUpOn = _day(json['nextFollowUpOn']),
      followUpDue = json['followUpDue'] == true,
      trialStartDate = _day(json['trialStartDate']),
      trialEndDate = _day(json['trialEndDate']),
      trialActive = json['trialActive'] == true,
      lostReason = json['lostReason'] as String?,
      referredBy = json['referredBy'] is Map<String, dynamic>
          ? LeadPerson.fromJson(json['referredBy'] as Map<String, dynamic>)
          : null,
      convertedMember = json['convertedMember'] is Map<String, dynamic>
          ? LeadPerson.fromJson(json['convertedMember'] as Map<String, dynamic>)
          : null,
      notes = List.unmodifiable(
        (json['notes'] as List? ?? const []).map(
          (row) => LeadNote.fromJson(row as Map<String, dynamic>),
        ),
      );
  final String id, firstName, phone;
  final String? lastName, lostReason;
  final LeadSource source;
  final LeadStatus status;

  /// Dates are gym-local calendar days; [trialEndDate] is exclusive.
  final DateTime? nextFollowUpOn, trialStartDate, trialEndDate;
  final bool followUpDue, trialActive;
  final LeadPerson? referredBy, convertedMember;
  final List<LeadNote> notes;
  String get name => lastName == null ? firstName : '$firstName $lastName';
}

class LeadPage {
  LeadPage.fromJson(Map<String, dynamic> json)
    : counts = Map.unmodifiable(
        (json['counts'] as Map).map(
          (key, value) => MapEntry(key as String, value as int),
        ),
      ),
      leads = List.unmodifiable(
        (json['data'] as List).map(
          (row) => Lead.fromJson(row as Map<String, dynamic>),
        ),
      ),
      pagination = Pagination.fromJson(
        json['pagination'] as Map<String, dynamic>,
      );
  final Map<String, int> counts;
  final List<Lead> leads;
  final Pagination pagination;
  int count(LeadFilter filter) => counts[filter.countKey] ?? 0;
}

class Referrer {
  Referrer.fromJson(Map<String, dynamic> json)
    : member = LeadPerson.fromJson(json['member'] as Map<String, dynamic>),
      referred = json['referred'] as int,
      joined = json['joined'] as int;
  final LeadPerson member;
  final int referred, joined;
}

class LeadFailure implements Exception {
  const LeadFailure(this.message, {this.existingLeadId});
  final String message;

  /// Set when an open enquiry already uses this phone number.
  final String? existingLeadId;
  factory LeadFailure.fromDio(DioException error) {
    final data = error.response?.data;
    final failure = data is Map ? data['error'] : null;
    final code = failure is Map ? failure['code'] : null;
    if (code == 'DUPLICATE_LEAD') {
      final details = failure['details'];
      return LeadFailure(
        'An open enquiry with this phone number already exists.',
        existingLeadId: details is Map ? details['leadId'] as String? : null,
      );
    }
    return LeadFailure(switch (code) {
      'LEAD_NOT_FOUND' => 'This enquiry is no longer available.',
      'LEAD_STATE_CHANGED' =>
        'This enquiry changed or has already joined. Reload and try again.',
      'MEMBER_NOT_FOUND' => 'That member is not in this gym.',
      'VALIDATION_ERROR' => 'Check the details and try again.',
      _ => AuthFailure.fromDio(error).message,
    });
  }
  @override
  String toString() => 'LeadFailure: $message';
}

String _iso(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';

typedef LeadQuery = ({LeadFilter filter, String search, int page});

class LeadRepository {
  LeadRepository(this._client);
  final Dio _client;

  String _base(String gymId) {
    if (!RegExp(r'^[a-fA-F0-9]{24}$').hasMatch(gymId)) {
      throw const LeadFailure('Invalid gym.');
    }
    return 'gyms/$gymId/leads';
  }

  Future<Map<String, dynamic>> _data(
    Future<Response<dynamic>> Function() call,
  ) async {
    try {
      final body = (await call()).data;
      if (body is! Map<String, dynamic> || body['success'] != true) {
        throw const LeadFailure('Unexpected response.');
      }
      return body['data'] as Map<String, dynamic>;
    } on DioException catch (error) {
      throw LeadFailure.fromDio(error);
    }
  }

  Future<Lead> _lead(Future<Response<dynamic>> Function() call) async {
    try {
      return Lead.fromJson(await _data(call));
    } on TypeError {
      throw const LeadFailure('The server returned an unexpected enquiry.');
    }
  }

  Future<LeadPage> list(String gymId, LeadQuery query) async {
    try {
      return LeadPage.fromJson(
        await _data(
          () => _client.get<dynamic>(
            _base(gymId),
            queryParameters: {
              ...query.filter.parameters,
              if (query.search.trim().isNotEmpty) 'search': query.search.trim(),
              'page': '${query.page}',
              'limit': '20',
            },
          ),
        ),
      );
    } on TypeError {
      throw const LeadFailure('The server returned unexpected enquiries.');
    }
  }

  Future<Lead> get(String gymId, String leadId) =>
      _lead(() => _client.get<dynamic>('${_base(gymId)}/$leadId'));

  Future<Lead> create(
    String gymId, {
    required String firstName,
    String? lastName,
    required String phone,
    required LeadSource source,
    String? referredByMemberId,
    DateTime? nextFollowUpOn,
    String? note,
  }) => _lead(
    () => _client.post<dynamic>(
      _base(gymId),
      data: {
        'firstName': firstName,
        'lastName': ?lastName,
        'phone': phone,
        'source': source.wire,
        'referredByMemberId': ?referredByMemberId,
        if (nextFollowUpOn != null) 'nextFollowUpOn': _iso(nextFollowUpOn),
        'note': ?note,
      },
    ),
  );

  /// `nextFollowUpOn: null` inside [changes] clears the follow-up.
  Future<Lead> update(
    String gymId,
    String leadId,
    Map<String, Object?> changes,
  ) => _lead(
    () => _client.patch<dynamic>('${_base(gymId)}/$leadId', data: changes),
  );

  Future<Lead> scheduleFollowUp(String gymId, String leadId, DateTime? day) =>
      update(gymId, leadId, {'nextFollowUpOn': day == null ? null : _iso(day)});

  Future<Lead> addNote(String gymId, String leadId, String text) => _lead(
    () => _client.post<dynamic>(
      '${_base(gymId)}/$leadId/notes',
      data: {'text': text},
    ),
  );

  Future<Lead> startTrial(String gymId, String leadId) => _lead(
    () => _client.post<dynamic>('${_base(gymId)}/$leadId/trial', data: {}),
  );

  Future<Lead> convert(String gymId, String leadId, String memberId) => _lead(
    () => _client.post<dynamic>(
      '${_base(gymId)}/$leadId/convert',
      data: {'memberId': memberId},
    ),
  );

  Future<List<Referrer>> referrals(String gymId) async {
    final data = await _data(
      () => _client.get<dynamic>('${_base(gymId)}/referrals'),
    );
    return List.unmodifiable(
      (data['data'] as List).map(
        (row) => Referrer.fromJson(row as Map<String, dynamic>),
      ),
    );
  }
}

final leadRepositoryProvider = Provider<LeadRepository>(
  (ref) => LeadRepository(ref.watch(authenticatedApiClientProvider)),
);

class LeadQueryController extends Notifier<LeadQuery> {
  @override
  LeadQuery build() {
    ref.watch(adminGymProvider);
    return (filter: LeadFilter.due, search: '', page: 1);
  }

  void select(LeadFilter filter) =>
      state = (filter: filter, search: state.search, page: 1);
  void search(String text) =>
      state = (filter: state.filter, search: text.trim(), page: 1);
  void page(int page) =>
      state = (filter: state.filter, search: state.search, page: page);
}

final leadQueryProvider = NotifierProvider<LeadQueryController, LeadQuery>(
  LeadQueryController.new,
);

final leadsProvider = FutureProvider.autoDispose.family<LeadPage?, LeadQuery>((
  ref,
  query,
) {
  final gym = ref.watch(adminGymProvider);
  if (gym == null) return null;
  return ref.watch(leadRepositoryProvider).list(gym.gymId, query);
}, retry: (_, _) => null);

final leadProvider = FutureProvider.autoDispose.family<Lead?, String>((
  ref,
  leadId,
) {
  final gym = ref.watch(adminGymProvider);
  if (gym == null) return null;
  return ref.watch(leadRepositoryProvider).get(gym.gymId, leadId);
}, retry: (_, _) => null);

final referralsProvider = FutureProvider.autoDispose<List<Referrer>?>((ref) {
  final gym = ref.watch(adminGymProvider);
  if (gym == null) return null;
  return ref.watch(leadRepositoryProvider).referrals(gym.gymId);
}, retry: (_, _) => null);

/// Prefill for Add member when converting an enquiry.
class LeadPrefill {
  const LeadPrefill({
    required this.leadId,
    required this.firstName,
    this.lastName,
    required this.phone,
  });
  final String leadId, firstName, phone;
  final String? lastName;
}
