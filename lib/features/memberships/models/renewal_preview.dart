import '../../members/models/member_models.dart';
import 'billing_models.dart';
import 'package:timezone/data/latest_all.dart' as database;
import 'package:timezone/timezone.dart' as tz;
import '../../admin_dashboard/models/dashboard_models.dart';

/// Dates and commercial terms are supplied by the subscription service.
/// Flutter formats calendar dates; it never calculates renewal periods/prices.
class RenewalPreview {
  RenewalPreview.fromJson(Map<String, dynamic> json)
    : gymId = text(json, 'gymId'),
      subscriptionId = text(json, 'subscriptionId'),
      memberId = text(object(json['member']), 'id'),
      memberName =
          '${text(object(json['member']), 'firstName')} ${text(object(json['member']), 'lastName')}',
      memberCode = text(object(json['member']), 'memberCode'),
      planId = text(json, 'planId'),
      previousEndDate = CalendarDate.parse(text(json, 'previousEndDate')),
      calendarTimezone = text(json, 'calendarTimezone'),
      planName = text(object(json['terms']), 'planName'),
      durationDays = integer(object(json['terms']), 'durationDays'),
      pricePaise = integer(object(json['terms']), 'pricePaise'),
      startDate = CalendarDate.parse(text(object(json['terms']), 'startDate')),
      endDate = CalendarDate.parse(text(object(json['terms']), 'endDate')),
      initialPaymentPaise = integer(json, 'initialPaymentPaise'),
      outstandingBalancePaise = integer(json, 'outstandingBalancePaise') {
    for (final id in [gymId, memberId, subscriptionId, planId]) {
      if (!RegExp(r'^[a-fA-F0-9]{24}$').hasMatch(id)) {
        throw const FormatException('Invalid renewal identity.');
      }
    }
    database.initializeTimeZones();
    if (!tz.timeZoneDatabase.locations.containsKey(calendarTimezone) ||
        durationDays < 1 ||
        durationDays > 3650 ||
        pricePaise > maximumPaymentPaise ||
        initialPaymentPaise != 0 ||
        outstandingBalancePaise != pricePaise ||
        startDate.compareTo(previousEndDate) < 0 ||
        endDate.compareTo(startDate) <= 0) {
      throw const FormatException('Invalid renewal preview.');
    }
  }
  final String gymId,
      subscriptionId,
      memberId,
      memberName,
      memberCode,
      planId,
      planName,
      calendarTimezone;
  final int durationDays,
      pricePaise,
      initialPaymentPaise,
      outstandingBalancePaise;
  final CalendarDate previousEndDate, startDate, endDate;
  Map<String, dynamic> get terms => {
    'planName': planName,
    'durationDays': durationDays,
    'pricePaise': pricePaise,
    'startDate': startDate.toString(),
    'endDate': endDate.toString(),
  };
  Map<String, dynamic> toRequest() => {'expectedTerms': terms};
}
