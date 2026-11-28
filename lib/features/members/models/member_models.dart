import '../../admin_dashboard/models/dashboard_models.dart';
import '../../../shared/models/profile_models.dart';
export '../../../shared/models/profile_models.dart';

enum MemberStatus { active, inactive, suspended }

const memberGenders = [
  'female',
  'male',
  'non_binary',
  'other',
  'prefer_not_to_say',
];

typedef MemberAddress = ProfileAddress;

class EmergencyContact {
  EmergencyContact.fromJson(Map<String, dynamic> json)
    : name = text(json, 'name'),
      phone = text(json, 'phone'),
      relationship = optionalText(json, 'relationship');
  final String name, phone;
  final String? relationship;
  Map<String, dynamic> toJson() => {
    'name': name,
    'phone': phone,
    if (relationship != null) 'relationship': relationship,
  };
}

class MemberProfile {
  MemberProfile.fromJson(Map<String, dynamic> json)
    : id = text(json, 'id'),
      gymId = optionalText(json, 'gymId'),
      memberCode = text(json, 'memberCode'),
      firstName = text(json, 'firstName'),
      lastName = text(json, 'lastName'),
      phone = text(json, 'phone'),
      phoneVerified = json['phoneVerified'] == true,
      status = MemberStatus.values.byName(text(json, 'status')),
      gender = optionalText(json, 'gender'),
      photoUrl = optionalText(json, 'photoUrl'),
      photoRevision = json['photoRevision'] is int
          ? json['photoRevision'] as int
          : 0,
      dateOfBirth = json['dateOfBirth'] == null
          ? null
          : CalendarDate.parse(text(json, 'dateOfBirth')),
      address = optionalObject(json['address'], MemberAddress.fromJson),
      emergencyContact = optionalObject(
        json['emergencyContact'],
        EmergencyContact.fromJson,
      );
  final String id, memberCode, firstName, lastName, phone;

  /// The member read back an SMS code sent to [phone].
  final bool phoneVerified;
  // Member 360 deliberately excludes gymId and userId. Scope belongs to the request.
  final String? gymId, gender, photoUrl;
  final int photoRevision;
  final CalendarDate? dateOfBirth;
  final MemberStatus status;
  final MemberAddress? address;
  final EmergencyContact? emergencyContact;
  String get name => '$firstName $lastName';
}

class MembersPage {
  MembersPage(this.members, this.pagination);
  final List<MemberProfile> members;
  final Pagination pagination;
}

class MemberListQuery {
  MemberListQuery({
    this.page = 1,
    this.limit = 20,
    String search = '',
    this.status,
    this.gender,
  }) : search = search.trim() {
    if (page < 1 ||
        page > 10000 ||
        limit < 1 ||
        limit > 100 ||
        this.search.length > 100 ||
        gender != null && !['male', 'female'].contains(gender)) {
      throw const FormatException('Invalid member query.');
    }
  }
  final int page, limit;
  final String search;
  final MemberStatus? status;
  // Presentation-only filter: the existing backend list API has no gender query.
  final String? gender;
  MemberListQuery withPage(int page) => MemberListQuery(
    page: page,
    limit: limit,
    search: search,
    status: status,
    gender: gender,
  );
  Map<String, dynamic> toParameters() => {
    'page': '$page',
    'limit': '$limit',
    if (search.isNotEmpty) 'search': search,
    if (status != null) 'status': status!.name,
  };
}

class Membership {
  Membership.fromJson(Map<String, dynamic> json)
    : id = text(json, 'id'),
      planId = text(json, 'membershipPlanId'),
      planName = text(json, 'planNameSnapshot'),
      durationDays = integer(json, 'durationDaysSnapshot'),
      pricePaise = integer(json, 'pricePaiseSnapshot'),
      startDate = CalendarDate.parse(text(json, 'startDate')),
      endDate = CalendarDate.parse(text(json, 'endDate')),
      status = text(json, 'status'),
      currentlyActive = boolean(json, 'isCurrentlyActive'),
      previousId = optionalText(json, 'previousSubscriptionId'),
      payments = optionalObject(
        json['paymentSummary'],
        MembershipPayments.fromJson,
      ),
      cancelledAt = json['cancelledAt'] == null
          ? null
          : DateTime.parse(text(json, 'cancelledAt')),
      cancellationReason = optionalText(json, 'cancellationReason'),
      frozenDays = json['frozenDays'] is int ? json['frozenDays'] as int : 0,
      discountPaise = json['discountPaise'] is int
          ? json['discountPaise'] as int
          : 0 {
    if (!['active', 'expired', 'cancelled'].contains(status) ||
        durationDays < 1) {
      throw const FormatException('Invalid membership.');
    }
  }
  final String id, planId, planName, status;
  final String? previousId, cancellationReason;
  final int durationDays, pricePaise;

  /// Days added to the end date by freezes, and money taken off the price.
  final int frozenDays, discountPaise;
  final CalendarDate startDate, endDate;
  final bool currentlyActive;
  final MembershipPayments? payments;
  final DateTime? cancelledAt;
}

class MembershipPayments {
  MembershipPayments.fromJson(Map<String, dynamic> json)
    : paidPaise = integer(json, 'totalSuccessfulPaidPaise'),
      balancePaise = integer(json, 'remainingBalancePaise');
  final int paidPaise, balancePaise;
}

class MembershipHistory {
  MembershipHistory.fromResponse(
    Map<String, dynamic> data,
    Map<String, dynamic> pagination,
  ) : memberId = text(object(data['member']), 'id'),
      current = optionalObject(data['currentMembership'], Membership.fromJson),
      subscriptions = items(data['subscriptions'], Membership.fromJson),
      pagination = Pagination.fromJson(pagination);
  final String memberId;
  final Membership? current;
  final List<Membership> subscriptions;
  final Pagination pagination;
}

class MembershipDetail {
  MembershipDetail.fromJson(Map<String, dynamic> json)
    : subscription = Membership.fromJson(object(json['subscription'])),
      payments = MembershipPayments.fromJson(object(json['paymentSummary']));
  final Membership subscription;
  final MembershipPayments payments;
}

class AssignedTrainer {
  AssignedTrainer.fromJson(Map<String, dynamic> json)
    : id = text(json, 'trainerId'),
      code = text(json, 'trainerCode'),
      firstName = text(json, 'firstName'),
      lastName = text(json, 'lastName'),
      phone = text(json, 'phone');
  final String id, code, firstName, lastName, phone;
  String get name => '$firstName $lastName';
}

class SuccessfulPayment {
  SuccessfulPayment.fromJson(Map<String, dynamic> json)
    : id = text(json, 'id'),
      amountPaise = integer(json, 'amountPaise'),
      method = text(json, 'paymentMethod'),
      paidAt = DateTime.parse(text(json, 'paidAt'));
  final String id, method;
  final int amountPaise;
  final DateTime paidAt;
}

class MemberPaymentSummary {
  MemberPaymentSummary.fromJson(Map<String, dynamic> json)
    : totalPaise = integer(json, 'totalSuccessfulAmountPaise'),
      count = integer(json, 'successfulPaymentCount'),
      latest = optionalObject(
        json['latestSuccessfulPayment'],
        SuccessfulPayment.fromJson,
      );
  final int totalPaise, count;
  final SuccessfulPayment? latest;
}

class CurrentMembershipPayments {
  CurrentMembershipPayments.fromJson(Map<String, dynamic> json)
    : pricePaise = integer(json, 'pricePaise'),
      paidPaise = integer(json, 'paidAmountPaise'),
      balancePaise = integer(json, 'remainingAmountPaise'),
      count = integer(json, 'paymentCount');
  final int pricePaise, paidPaise, balancePaise, count;
}

class MemberSummary {
  MemberSummary.fromJson(Map<String, dynamic> json)
    : member = MemberProfile.fromJson(object(json['member'])),
      trainers = items(json['currentTrainers'], AssignedTrainer.fromJson),
      currentSubscription = optionalObject(
        json['currentSubscription'],
        Membership.fromJson,
      ),
      history = items(
        object(json['subscriptionHistory'])['items'],
        Membership.fromJson,
      ),
      historyPagination = Pagination.fromJson(
        object(json['subscriptionHistory']),
      ),
      payments = MemberPaymentSummary.fromJson(object(json['paymentSummary'])),
      currentPayments = optionalObject(
        json['currentSubscriptionPaymentSummary'],
        CurrentMembershipPayments.fromJson,
      );
  final MemberProfile member;
  final List<AssignedTrainer> trainers;
  final Membership? currentSubscription;
  final List<Membership> history;
  final Pagination historyPagination;
  final MemberPaymentSummary payments;
  final CurrentMembershipPayments? currentPayments;
}
