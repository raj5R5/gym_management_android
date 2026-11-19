import 'package:flutter_test/flutter_test.dart';
import 'package:gym_management_app/features/leads/lead_widgets.dart';
import 'package:gym_management_app/features/leads/leads.dart';
import 'lead_fakes.dart';

void main() {
  final today = DateTime(2026, 11, 14, 17, 30);
  Lead lead({String status = 'new', String? next = '2026-11-14'}) =>
      Lead.fromJson(leadJson(status: status, nextFollowUpOn: next));

  test('follow-up labels count calendar days, not hours', () {
    expect(followUpLabel(lead(), today), 'Follow up today');
    expect(
      followUpLabel(lead(next: '2026-11-15'), today),
      'Follow up tomorrow',
    );
    // The trial bug: 16 Nov seen from the evening of 14 Nov is two days away.
    expect(followUpLabel(lead(next: '2026-11-16'), today), 'Follow up 16 Nov');
    expect(followUpLabel(lead(next: '2026-11-12'), today), 'Overdue by 2 days');
    expect(followUpLabel(lead(next: null), today), 'No follow-up set');
    expect(
      followUpLabel(lead(status: 'lost', next: null), today),
      'Lost · Too far',
    );
  });

  test('WhatsApp drafts fit the stage of the enquiry', () {
    expect(leadMessage(lead(), 'Iron Gym'), contains('free 3-day trial'));
    final trial = Lead.fromJson(leadJson(status: 'trial'));
    expect(leadMessage(trial, ''), contains('runs until 16 Nov'));
  });

  test('duplicate failures carry the existing enquiry', () {
    const failure = LeadFailure('x', existingLeadId: 'abc');
    expect(failure.existingLeadId, 'abc');
  });
}
