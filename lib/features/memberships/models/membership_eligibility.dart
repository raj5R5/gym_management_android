import '../../members/models/member_models.dart';
import '../data/billing_failure.dart';

const activeMembershipMessage =
    'This member already has an unexpired membership. Purchase or renew after its end date. You can still collect payments for the existing membership.';

// Use the server's date-derived lifecycle, including scheduled active periods.
// Do not use device time or the outstanding balance to determine eligibility.
Membership? blockingMembership(Iterable<Membership> records) =>
    records.where((record) => record.status == 'active').firstOrNull;

List<Membership> verifiedUnpaidMemberships(Iterable<Membership> records) {
  final due = <Membership>[];
  for (final record in records) {
    if (record.status == 'cancelled') continue;
    final money = record.payments;
    if (money == null ||
        money.paidPaise + money.balancePaise != record.pricePaise) {
      throw const BillingFailure(
        'Membership balances could not be verified. Refresh history.',
      );
    }
    if (money.balancePaise > 0) due.add(record);
  }
  return List.unmodifiable(due);
}
