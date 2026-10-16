import '../../members/data/member_repository.dart';
import '../../members/models/member_models.dart';
import 'billing_failure.dart';
import '../models/membership_eligibility.dart';

class OutstandingMember {
  OutstandingMember(this.member, this.memberships);
  final MemberProfile member;
  final List<Membership> memberships;
  int get balancePaise => memberships.fold(
    0,
    (total, membership) => total + membership.payments!.balancePaise,
  );
}

class OutstandingDues {
  OutstandingDues(this.members) {
    if (totalPaise > 9007199254740991) {
      throw const FormatException('Unsafe balance total.');
    }
  }
  final List<OutstandingMember> members;
  int get totalPaise =>
      members.fold(0, (total, member) => total + member.balancePaise);
  List<OutstandingMember> search(String value, {bool highestFirst = true}) {
    final query = value.trim().toLowerCase();
    final result = members
        .where(
          (row) =>
              '${row.member.name} ${row.member.phone} ${row.member.memberCode} ${row.memberships.map((m) => m.planName).join(' ')}'
                  .toLowerCase()
                  .contains(query),
        )
        .toList();
    result.sort((a, b) {
      final comparison = highestFirst
          ? b.balancePaise.compareTo(a.balancePaise)
          : a.member.name.toLowerCase().compareTo(b.member.name.toLowerCase());
      return comparison != 0 ? comparison : a.member.id.compareTo(b.member.id);
    });
    return List.unmodifiable(result);
  }
}

/// Compose existing server-calculated balances, including expired/future debt.
/// Walk every history page and deduplicate current/history by subscription ID.
class OutstandingDuesRepository {
  OutstandingDuesRepository(this._members);
  final MemberRepository _members;
  Future<OutstandingDues> load(
    String gymId, {
    required bool Function() current,
  }) async {
    void check() {
      if (!current()) {
        throw const BillingFailure(
          'The gym or account changed. Reopen outstanding dues.',
        );
      }
    }

    final profiles = <String, MemberProfile>{};
    for (var page = 1; ; page++) {
      check();
      final data = await _members.list(
        gymId,
        MemberListQuery(page: page, limit: 100),
      );
      check();
      for (final member in data.members) {
        profiles[member.id] = member;
      }
      if (!data.pagination.hasNext) break;
    }
    final result = <OutstandingMember>[];
    final members = profiles.values.toList();
    // Bound concurrent reads for pilot-sized gyms; no partial totals on error.
    for (var offset = 0; offset < members.length; offset += 4) {
      final batch = members.skip(offset).take(4);
      final rows = await Future.wait(
        batch.map((member) async {
          final subscriptions = await _members.allMemberships(
            gymId,
            member.id,
            guard: check,
          );
          final due = verifiedUnpaidMemberships(subscriptions);
          return due.isEmpty
              ? null
              : OutstandingMember(member, List.unmodifiable(due));
        }),
      );
      result.addAll(rows.whereType<OutstandingMember>());
    }
    check();
    return OutstandingDues(List.unmodifiable(result));
  }
}
