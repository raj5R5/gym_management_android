import 'package:gym_management_app/features/leads/leads.dart';

const leadA = '0000000000000000000000a1';

Map<String, dynamic> leadJson({
  String id = leadA,
  String firstName = 'Kabir',
  String status = 'new',
  String? nextFollowUpOn = '2026-11-14',
  bool due = true,
  Map<String, dynamic>? convertedMember,
}) => {
  'id': id,
  'firstName': firstName,
  'lastName': 'Malhotra',
  'phone': '90000 10001',
  'source': 'instagram',
  'status': status,
  'nextFollowUpOn': nextFollowUpOn,
  'followUpDue': due,
  'trialStartDate': status == 'trial' ? '2026-11-14' : null,
  'trialEndDate': status == 'trial' ? '2026-11-17' : null,
  'trialActive': status == 'trial',
  'lostReason': status == 'lost' ? 'Too far' : null,
  'referredBy': null,
  'convertedMember': convertedMember,
  'notes': <Map<String, dynamic>>[],
};

/// In-memory enquiries; records every call for assertions.
class FakeLeadRepository implements LeadRepository {
  FakeLeadRepository({List<Map<String, dynamic>>? leads})
    : leads = leads ?? [leadJson()];
  final List<Map<String, dynamic>> leads;
  final calls = <String>[];
  String? duplicateOf;

  Map<String, dynamic> _find(String id) =>
      leads.firstWhere((lead) => lead['id'] == id);

  @override
  Future<LeadPage> list(String gymId, LeadQuery query) async {
    final rows = query.filter == LeadFilter.due
        ? leads.where((lead) => lead['followUpDue'] == true).toList()
        : leads;
    return LeadPage.fromJson({
      'counts': {
        'new': leads.where((l) => l['status'] == 'new').length,
        'contacted': 0,
        'trial': 0,
        'joined': 0,
        'lost': 0,
        'open': leads.length,
        'followUpsDue': leads.where((l) => l['followUpDue'] == true).length,
      },
      'data': rows,
      'pagination': {'page': 1, 'limit': 20, 'total': rows.length},
    });
  }

  @override
  Future<Lead> get(String gymId, String leadId) async =>
      Lead.fromJson(_find(leadId));

  @override
  Future<Lead> create(
    String gymId, {
    required String firstName,
    String? lastName,
    required String phone,
    required LeadSource source,
    String? referredByMemberId,
    DateTime? nextFollowUpOn,
    String? note,
  }) async {
    calls.add('create:$firstName:$phone:${source.wire}');
    if (duplicateOf != null) {
      throw LeadFailure('duplicate', existingLeadId: duplicateOf);
    }
    final json = leadJson(
      id: '0000000000000000000000b${leads.length}',
      firstName: firstName,
    );
    leads.add(json);
    return Lead.fromJson(json);
  }

  @override
  Future<Lead> update(
    String gymId,
    String leadId,
    Map<String, Object?> changes,
  ) async {
    calls.add('update:$changes');
    final lead = _find(leadId);
    if (changes['status'] case final String status) lead['status'] = status;
    if (changes['lostReason'] case final String reason) {
      lead['lostReason'] = reason;
    }
    return Lead.fromJson(lead);
  }

  @override
  Future<Lead> scheduleFollowUp(String gymId, String leadId, DateTime? day) =>
      update(gymId, leadId, {'nextFollowUpOn': day?.toIso8601String()});

  @override
  Future<Lead> addNote(String gymId, String leadId, String text) async {
    calls.add('note:$text');
    return Lead.fromJson(_find(leadId));
  }

  @override
  Future<Lead> startTrial(String gymId, String leadId) async {
    calls.add('trial');
    final lead = _find(leadId)
      ..['status'] = 'trial'
      ..['trialStartDate'] = '2026-11-14'
      ..['trialEndDate'] = '2026-11-17'
      ..['trialActive'] = true;
    return Lead.fromJson(lead);
  }

  @override
  Future<Lead> convert(String gymId, String leadId, String memberId) async {
    calls.add('convert:$memberId');
    return Lead.fromJson(_find(leadId)..['status'] = 'joined');
  }

  @override
  Future<List<Referrer>> referrals(String gymId) async => const [];
}
