import '../../admin_dashboard/models/dashboard_models.dart';

Map<String, dynamic> object(Object? value) {
  if (value is! Map<String, dynamic>) {
    throw const FormatException('Invalid member response.');
  }
  return value;
}

String text(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.isEmpty) {
    throw const FormatException('Missing member field.');
  }
  return value;
}

String? optionalText(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! String) throw const FormatException('Invalid member field.');
  return value;
}

int integer(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! int || value < 0 || value > 9007199254740991) {
    throw const FormatException('Invalid member number.');
  }
  return value;
}

bool boolean(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! bool) throw const FormatException('Invalid member flag.');
  return value;
}

List<T> items<T>(Object? value, T Function(Map<String, dynamic>) parse) {
  if (value is! List) throw const FormatException('Invalid member collection.');
  return List.unmodifiable(value.map((item) => parse(object(item))));
}

T? optionalObject<T>(Object? value, T Function(Map<String, dynamic>) parse) =>
    value == null ? null : parse(object(value));

enum MemberStatus { active, inactive, suspended }

const memberGenders = [
  'female',
  'male',
  'non_binary',
  'other',
  'prefer_not_to_say',
];

class MemberAddress {
  MemberAddress.fromJson(Map<String, dynamic> json)
    : line1 = text(json, 'line1'),
      city = text(json, 'city'),
      countryCode = text(json, 'countryCode'),
      line2 = optionalText(json, 'line2'),
      region = optionalText(json, 'state'),
      postalCode = optionalText(json, 'postalCode');
  final String line1, city, countryCode;
  final String? line2, region, postalCode;
  Map<String, dynamic> toJson() => {
    'line1': line1,
    'city': city,
    'countryCode': countryCode,
    if (line2 != null) 'line2': line2,
    if (region != null) 'state': region,
    if (postalCode != null) 'postalCode': postalCode,
  };
  String get display => [
    line1,
    line2,
    city,
    region,
    postalCode,
    countryCode,
  ].whereType<String>().join(', ');
}

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
      branchId = optionalText(json, 'branchId'),
      memberCode = text(json, 'memberCode'),
      firstName = text(json, 'firstName'),
      lastName = text(json, 'lastName'),
      phone = text(json, 'phone'),
      status = MemberStatus.values.byName(text(json, 'status')),
      gender = optionalText(json, 'gender'),
      dateOfBirth = json['dateOfBirth'] == null
          ? null
          : CalendarDate.parse(text(json, 'dateOfBirth')),
      address = optionalObject(json['address'], MemberAddress.fromJson),
      emergencyContact = optionalObject(
        json['emergencyContact'],
        EmergencyContact.fromJson,
      );
  final String id, memberCode, firstName, lastName, phone;
  // Member 360 deliberately excludes gymId and userId. Scope belongs to the request.
  final String? gymId, branchId, gender;
  final CalendarDate? dateOfBirth;
  final MemberStatus status;
  final MemberAddress? address;
  final EmergencyContact? emergencyContact;
  String get name => '$firstName $lastName';
}

class Pagination {
  Pagination.fromJson(Map<String, dynamic> json)
    : page = integer(json, 'page'),
      limit = integer(json, 'limit'),
      total = integer(json, 'total') {
    if (page < 1 || page > 10000 || limit < 1 || limit > 100) {
      throw const FormatException('Invalid pagination.');
    }
  }
  final int page, limit, total;
  bool get hasNext => page < 10000 && page * limit < total;
  bool get hasPrevious => page > 1;
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
  }) : search = search.trim() {
    if (page < 1 ||
        page > 10000 ||
        limit < 1 ||
        limit > 100 ||
        this.search.length > 100) {
      throw const FormatException('Invalid member query.');
    }
  }
  final int page, limit;
  final String search;
  final MemberStatus? status;
  MemberListQuery withPage(int page) =>
      MemberListQuery(page: page, limit: limit, search: search, status: status);
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
      cancellationReason = optionalText(json, 'cancellationReason') {
    if (!['active', 'expired', 'cancelled'].contains(status) ||
        durationDays < 1) {
      throw const FormatException('Invalid membership.');
    }
  }
  final String id, planId, planName, status;
  final String? previousId, cancellationReason;
  final int durationDays, pricePaise;
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

class MemberBranch {
  MemberBranch.fromJson(Map<String, dynamic> json)
    : id = text(json, 'id'),
      name = text(json, 'name'),
      status = text(json, 'status');
  final String id, name, status;
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

class MemberVisit {
  MemberVisit.fromJson(Map<String, dynamic> json)
    : id = text(json, 'id'),
      status = text(json, 'status'),
      checkInAt = DateTime.parse(text(json, 'checkInAt')),
      checkOutAt = json['checkOutAt'] == null
          ? null
          : DateTime.parse(text(json, 'checkOutAt'));
  final String id, status;
  final DateTime checkInAt;
  final DateTime? checkOutAt;
}

class MemberAttendanceSummary {
  MemberAttendanceSummary.fromJson(Map<String, dynamic> json)
    : visits = integer(json, 'totalCompletedVisits'),
      checkedIn = boolean(json, 'currentlyCheckedIn'),
      latest = optionalObject(json['latestAttendance'], MemberVisit.fromJson),
      current = optionalObject(json['currentAttendance'], MemberVisit.fromJson);
  final int visits;
  final bool checkedIn;
  final MemberVisit? latest, current;
}

class MemberSummary {
  MemberSummary.fromJson(Map<String, dynamic> json)
    : member = MemberProfile.fromJson(object(json['member'])),
      branch = optionalObject(json['currentBranch'], MemberBranch.fromJson),
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
      ),
      attendance = MemberAttendanceSummary.fromJson(
        object(json['attendanceSummary']),
      );
  final MemberProfile member;
  final MemberBranch? branch;
  final List<AssignedTrainer> trainers;
  final Membership? currentSubscription;
  final List<Membership> history;
  final Pagination historyPagination;
  final MemberPaymentSummary payments;
  final CurrentMembershipPayments? currentPayments;
  final MemberAttendanceSummary attendance;
}
