import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../formatting/inr.dart';

/// Digits for wa.me links. Ten-digit numbers are treated as Indian mobiles
/// (the app's market); numbers with a country code are kept as entered.
String? whatsappNumber(String phone) {
  var digits = phone.replaceAll(RegExp(r'\D'), '');
  if (digits.length == 11 && digits.startsWith('0')) {
    digits = digits.substring(1);
  }
  if (digits.length == 10) return '91$digits';
  if (digits.length >= 11 && digits.length <= 15) return digits;
  return null;
}

Uri whatsappUri(String phone, String message) =>
    Uri.https('wa.me', '/${whatsappNumber(phone) ?? ''}', {'text': message});

Uri callUri(String phone) =>
    Uri(scheme: 'tel', path: phone.replaceAll(RegExp(r'[^0-9+]'), ''));

/// Reminder texts are drafts: WhatsApp opens with the text, and the owner sends it.
abstract final class ReminderMessages {
  static String _sign(String gymName) => gymName.isEmpty ? '' : '\n– $gymName';

  static String expiring({
    required String firstName,
    required String planName,
    required int daysLeft,
    required String gymName,
  }) =>
      'Hi $firstName, your $planName membership ends in '
      '${daysLeft == 1 ? '1 day' : '$daysLeft days'}. '
      'Renew now to keep training without a break.${_sign(gymName)}';

  static String dues({
    required String firstName,
    required int balancePaise,
    required String gymName,
  }) =>
      'Hi $firstName, a membership balance of '
      '${formatCompactInrPaise(balancePaise)} is pending. '
      'You can pay at the front desk on your next visit.${_sign(gymName)}';

  static String missYou({required String firstName, required String gymName}) =>
      'Hi $firstName, we haven’t seen you at the gym for a while. '
      'Your membership is active, so drop in today and keep your progress going.${_sign(gymName)}';

  static String birthday({
    required String firstName,
    required bool today,
    required String gymName,
  }) => today
      ? 'Happy birthday, $firstName! Wishing you a strong and healthy year ahead.${_sign(gymName)}'
      : 'Hi $firstName, happy birthday in advance! Wishing you a strong and healthy year ahead.${_sign(gymName)}';

  static String expired({
    required String firstName,
    required String planName,
    required String gymName,
  }) =>
      'Hi $firstName, your $planName membership has ended. '
      'We miss you at the gym. Renew to get back on track.${_sign(gymName)}';
}

Future<void> openExternal(BuildContext context, Uri uri, String failure) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  var opened = false;
  try {
    opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    opened = false;
  }
  if (!opened) {
    messenger?.showSnackBar(SnackBar(content: Text(failure)));
  }
}

Future<void> callMember(BuildContext context, String phone) =>
    openExternal(context, callUri(phone), 'Could not open the phone app.');

Future<void> whatsappMember(
  BuildContext context,
  String phone,
  String message,
) {
  if (whatsappNumber(phone) == null) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(
        content: Text('This phone number can’t be used for WhatsApp.'),
      ),
    );
    return Future.value();
  }
  return openExternal(
    context,
    whatsappUri(phone, message),
    'Could not open WhatsApp. Is it installed?',
  );
}
