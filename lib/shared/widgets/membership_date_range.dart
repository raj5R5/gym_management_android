import 'package:flutter/material.dart';

/// Displays saved calendar components without shifting timezone or changing the
/// backend's exclusive end date. Month names match the app's current English UI.
class MembershipDateRange extends StatelessWidget {
  const MembershipDateRange({
    super.key,
    required this.start,
    required this.end,
    this.previous = false,
    this.singleLine = false,
  });
  final DateTime start, end;
  final bool previous;
  final bool singleLine;
  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  static String _date(DateTime value) =>
      '${value.day} ${_months[value.month - 1]} ${value.year}';
  String get label => '${_date(start)} – ${_date(end)}';
  @override
  Widget build(BuildContext context) {
    final style = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(fontSize: singleLine ? 10 : 12);
    return Semantics(
      label:
          '${previous ? 'Previous membership' : 'Membership'} dates: $label. End date is exclusive.',
      child: ExcludeSemantics(
        child: singleLine
            ? FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(label, style: style, maxLines: 1, softWrap: false),
              )
            : Wrap(
                spacing: 4,
                runSpacing: 2,
                children: [
                  Text('${_date(start)} –', style: style, softWrap: true),
                  Text(_date(end), style: style, softWrap: true),
                ],
              ),
      ),
    );
  }
}
