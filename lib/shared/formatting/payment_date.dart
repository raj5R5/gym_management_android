import 'package:flutter/material.dart';
import 'package:timezone/data/latest_all.dart' as database;
import 'package:timezone/timezone.dart' as tz;

bool _initialized = false;

/// Display only. Never changes the stored instant or server calendar boundaries.
/// [showZone] false drops the gym zone name where the context already says it
/// is gym time; a missing zone is always named, since the time is then UTC.
String formatPaymentDateTime(
  MaterialLocalizations localizations,
  DateTime instant, {
  String? timezone,
  bool showZone = true,
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
  final when =
      '${localizations.formatShortDate(date)} · '
      '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(date))}';
  return showZone || location == null ? '$when · $zoneLabel' : when;
}
