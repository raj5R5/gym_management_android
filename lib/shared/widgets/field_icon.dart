import 'package:flutter/material.dart';

/// One semantic icon vocabulary for the existing forms. Labels remain the
/// accessible name; these repeated visual cues do not add screen-reader stops.
class FieldIcon extends StatelessWidget {
  const FieldIcon(this.field, {super.key});
  final String field;

  IconData get _icon => switch (field) {
    'firstName' ||
    'lastName' ||
    'ownerFullName' ||
    'displayName' => Icons.person_outline,
    'memberCode' || 'trainerCode' => Icons.badge_outlined,
    'email' || 'gymContactEmail' => Icons.email_outlined,
    'phone' ||
    'contactPhone' ||
    'gymContactPhone' ||
    'gymPhone' => Icons.phone_outlined,
    'password' || 'confirmPassword' || 'currentPassword' => Icons.lock_outline,
    'gymName' => Icons.fitness_center_outlined,
    'line1' ||
    'line2' ||
    'address' ||
    'gymAddress' => Icons.location_on_outlined,
    'city' || 'state' => Icons.location_city_outlined,
    'postalCode' => Icons.markunread_mailbox_outlined,
    'countryCode' => Icons.public_outlined,
    'contactName' || 'relationship' => Icons.contact_phone_outlined,
    'specializations' => Icons.fitness_center_outlined,
    'gender' => Icons.person_outline,
    'status' => Icons.verified_user_outlined,
    'amount' => Icons.payments_outlined,
    'price' => Icons.sell_outlined,
    'name' => Icons.label_outline,
    'duration' => Icons.timelapse_outlined,
    'method' => Icons.account_balance_wallet_outlined,
    'reference' => Icons.receipt_long_outlined,
    'description' || 'reason' => Icons.notes_outlined,
    'search' => Icons.search,
    'sort' => Icons.sort,
    _ => Icons.edit_note_outlined,
  };

  @override
  Widget build(BuildContext context) =>
      ExcludeSemantics(child: Icon(_icon, size: 20));
}
