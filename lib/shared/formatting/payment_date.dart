import 'package:flutter/material.dart';
import 'package:timezone/data/latest_all.dart' as database;
import 'package:timezone/timezone.dart' as tz;

bool _initialized = false;

/// Display only. Never changes the stored instant or server calendar boundaries.
String formatPaymentDateTime(
  MaterialLocalizations localizations,
  DateTime instant, {
  String? timezone,
}) {
  if (!_initialized) {
    database.initializeTimeZones();
    _initialized = true;
  }
  final location = timezone == null
      ? null
      : tz.timeZoneDatabase.locations[timezone];
  final date = location == null
      ? instant.toUtc()
      : tz.TZDateTime.from(instant, location);
  final zoneLabel = location == null
      ? 'UTC (gym timezone unavailable)'
      : timezone!;
  return '${localizations.formatShortDate(date)} · '
      '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(date))} · $zoneLabel';
}
