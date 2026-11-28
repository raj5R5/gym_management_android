import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/contact/member_contact.dart';
import '../admin_dashboard/providers/dashboard_providers.dart';
import '../auth/data/auth_failure.dart';
import '../auth/providers/auth_providers.dart';

/// What a notification is about; the server sends the wire names.
enum NotificationKind {
  expiring('expiring', 'Ending soon'),
  expired('expired', 'Expired'),
  dues('dues', 'Dues to collect'),
  claim('claim', 'UPI reports'),
  followup('followup', 'Enquiry follow-ups'),
  birthday('birthday', 'Birthdays'),
  inactive('inactive', 'Not visiting'),
  join('join', 'Join requests');

  const NotificationKind(this.wire, this.label);
  final String wire, label;

  static NotificationKind? from(Object? value) {
    for (final kind in values) {
      if (kind.wire == value) return kind;
    }
    return null;
  }

  /// Kinds that are reminders a member can be sent on WhatsApp.
  bool get remindable => switch (this) {
    expiring || expired || dues || birthday || inactive || followup => true,
    claim || join => false,
  };
}

class NotificationPerson {
  NotificationPerson.fromJson(Map<String, dynamic> json)
    : id = json['id'] as String,
      name = json['name'] as String,
      phone = json['phone'] as String,
      memberCode = json['memberCode'] as String?;
  final String id, name, phone;
  final String? memberCode;
  String get firstName => name.split(' ').first;
}

class GymNotification {
  GymNotification.fromJson(Map<String, dynamic> json)
    : key = json['key'] as String,
      kind = NotificationKind.from(json['kind'])!,
      severity = json['severity'] as String,
      title = json['title'] as String,
      detail = json['detail'] as String,
      unread = json['unread'] == true,
      date = DateTime.tryParse(json['date'] as String? ?? ''),
      amountPaise = json['amountPaise'] as int?,
      planName = json['planName'] as String?,
      daysLeft = json['daysLeft'] as int?,
      subscriptionId = json['subscriptionId'] as String?,
      member = json['member'] == null
          ? null
          : NotificationPerson.fromJson(json['member'] as Map<String, dynamic>),
      lead = json['lead'] == null
          ? null
          : NotificationPerson.fromJson(json['lead'] as Map<String, dynamic>);
  final String key, severity, title, detail;
  final NotificationKind kind;
  final bool unread;
  final DateTime? date;
  final int? amountPaise, daysLeft;
  final String? planName, subscriptionId;
  final NotificationPerson? member, lead;

  NotificationPerson? get person => member ?? lead;
  bool get urgent => severity == 'high';

  /// The WhatsApp draft for this reminder.
  String message(String gymName) {
    final name = person?.firstName ?? '';
    return switch (kind) {
      NotificationKind.expiring => ReminderMessages.expiring(
        firstName: name,
        planName: planName ?? 'membership',
        daysLeft: (daysLeft ?? 1).clamp(1, 365),
        gymName: gymName,
      ),
      NotificationKind.expired => ReminderMessages.expired(
        firstName: name,
        planName: planName ?? 'membership',
        gymName: gymName,
      ),
      NotificationKind.dues => ReminderMessages.dues(
        firstName: name,
        balancePaise: amountPaise ?? 0,
        gymName: gymName,
      ),
      NotificationKind.birthday => ReminderMessages.birthday(
        firstName: name,
        today: title.endsWith('today'),
        gymName: gymName,
      ),
      NotificationKind.inactive => ReminderMessages.missYou(
        firstName: name,
        gymName: gymName,
      ),
      NotificationKind.followup =>
        'Hi $name, thanks for asking about the gym. '
            'Would you like to come in for a free trial this week?'
            '${gymName.isEmpty ? '' : '\n– $gymName'}',
      NotificationKind.claim || NotificationKind.join => '',
    };
  }
}

class NotificationFeed {
  NotificationFeed.fromJson(Map<String, dynamic> json)
    : unread = json['unread'] as int,
      items = [
        for (final row in json['data'] as List)
          if (NotificationKind.from((row as Map)['kind']) != null)
            GymNotification.fromJson(row.cast<String, dynamic>()),
      ];
  final int unread;
  final List<GymNotification> items;

  List<GymNotification> of(NotificationKind kind) =>
      items.where((item) => item.kind == kind).toList();
}

class NotificationFailure implements Exception {
  const NotificationFailure(this.message);
  final String message;
  @override
  String toString() => 'NotificationFailure: $message';
}

class NotificationRepository {
  NotificationRepository(this._client);
  final Dio _client;

  Future<T> _call<T>(
    Future<Response<dynamic>> Function() call,
    T Function(dynamic data) parse,
  ) async {
    try {
      final body = (await call()).data;
      if (body is! Map<String, dynamic> || body['success'] != true) {
        throw const NotificationFailure('Unexpected response.');
      }
      return parse(body['data']);
    } on DioException catch (error) {
      throw NotificationFailure(AuthFailure.fromDio(error).message);
    } on TypeError {
      throw const NotificationFailure('The server returned unexpected data.');
    }
  }

  Future<NotificationFeed> feed(String gymId) => _call(
    () => _client.get<dynamic>('gyms/$gymId/notifications'),
    (data) => NotificationFeed.fromJson(data as Map<String, dynamic>),
  );

  Future<void> markSeen(String gymId) => _call(
    () => _client.post<dynamic>('gyms/$gymId/notifications/seen'),
    (_) {},
  );
}

final notificationRepositoryProvider = Provider<NotificationRepository>(
  (ref) => NotificationRepository(ref.watch(authenticatedApiClientProvider)),
);

final notificationFeedProvider = FutureProvider.autoDispose<NotificationFeed?>((
  ref,
) {
  final gym = ref.watch(adminGymProvider);
  if (gym == null) return null;
  return ref.watch(notificationRepositoryProvider).feed(gym.gymId);
}, retry: (_, _) => null);
