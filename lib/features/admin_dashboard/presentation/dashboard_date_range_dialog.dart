import 'package:flutter/material.dart';

import '../../../app/theme/design_tokens.dart';
import '../models/dashboard_models.dart';

/// A date-only calendar. Its viewport clock is never used to calculate a
/// business period; quick presets are resolved by the backend in the gym zone.
class DashboardDateRangeDialog extends StatefulWidget {
  const DashboardDateRangeDialog({super.key, this.initialRange});
  final DateTimeRange? initialRange;

  @override
  State<DashboardDateRangeDialog> createState() =>
      _DashboardDateRangeDialogState();
}

class _DashboardDateRangeDialogState extends State<DashboardDateRangeDialog> {
  late DateTime _month;
  DateTime? _from, _to;
  bool _selectingFrom = true;
  bool _choosingYear = false;

  @override
  void initState() {
    super.initState();
    _from = widget.initialRange?.start;
    _to = widget.initialRange?.end;
    final anchor = _from ?? DateTime.now();
    _month = DateTime.utc(anchor.year, anchor.month);
  }

  String? get _error {
    if (_from == null || _to == null) return null;
    if (_from!.isAfter(_to!)) return 'From must be on or before To.';
    try {
      DashboardQuery.range(
        CalendarDate.fromPicker(_from!),
        CalendarDate.fromPicker(_to!),
      );
      return null;
    } on FormatException {
      return 'Choose no more than 366 inclusive days.';
    }
  }

  void _select(DateTime day) => setState(() {
    if (_selectingFrom) {
      _from = day;
      _to = null;
      _selectingFrom = false;
    } else {
      _to = day;
    }
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final localizations = MaterialLocalizations.of(context);
    Widget endpoint(String title, DateTime? date, bool from) => Expanded(
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          backgroundColor: _selectingFrom == from
              ? theme.colorScheme.primaryContainer
              : null,
          padding: const EdgeInsets.all(AppSpacing.sm),
        ),
        onPressed: () => setState(() {
          _selectingFrom = from;
          _choosingYear = false;
        }),
        child: Column(
          children: [
            Text(title),
            Text(
              date == null
                  ? 'Select date'
                  : localizations.formatShortDate(date),
            ),
          ],
        ),
      ),
    );
    return Dialog(
      insetPadding: const EdgeInsets.all(AppSpacing.lg),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Select revenue dates',
                      style: theme.textTheme.titleLarge,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    const Text('Both dates included · Up to 366 days'),
                    const SizedBox(height: AppSpacing.lg),
                    Row(
                      children: [
                        endpoint('From', _from, true),
                        const SizedBox(width: AppSpacing.sm),
                        endpoint('To', _to, false),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Row(
                      children: [
                        IconButton(
                          tooltip: 'Previous month',
                          onPressed: _month.year == 1 && _month.month == 1
                              ? null
                              : () => setState(() {
                                  _month = DateTime.utc(
                                    _month.year,
                                    _month.month - 1,
                                  );
                                }),
                          icon: const Icon(Icons.chevron_left),
                        ),
                        Expanded(
                          child: TextButton(
                            onPressed: () =>
                                setState(() => _choosingYear = !_choosingYear),
                            child: Wrap(
                              alignment: WrapAlignment.center,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  localizations.formatMonthYear(_month),
                                  key: const Key('calendar-month'),
                                ),
                                const Icon(Icons.arrow_drop_down),
                              ],
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Next month',
                          onPressed: _month.year == 9999 && _month.month == 12
                              ? null
                              : () => setState(() {
                                  _month = DateTime.utc(
                                    _month.year,
                                    _month.month + 1,
                                  );
                                }),
                          icon: const Icon(Icons.chevron_right),
                        ),
                      ],
                    ),
                    if (_choosingYear)
                      SizedBox(
                        height: 260,
                        child: YearPicker(
                          firstDate: DateTime(1),
                          lastDate: DateTime(9999, 12, 30),
                          selectedDate: _month,
                          onChanged: (date) => setState(() {
                            _month = DateTime.utc(date.year, _month.month);
                            _choosingYear = false;
                          }),
                        ),
                      )
                    else
                      _calendar(context, localizations),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      _error ??
                          (_selectingFrom
                              ? 'Tap the first day, then the last day.'
                              : 'Tap the last day. Tap the same date for a single day.'),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: _error == null
                            ? theme.colorScheme.onSurfaceVariant
                            : theme.colorScheme.error,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                0,
                AppSpacing.lg,
                AppSpacing.lg,
              ),
              child: OverflowBar(
                spacing: AppSpacing.sm,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: _from == null || _to == null || _error != null
                        ? null
                        : () => Navigator.of(
                            context,
                          ).pop(DateTimeRange(start: _from!, end: _to!)),
                    child: const Text('Apply'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _calendar(BuildContext context, MaterialLocalizations localizations) {
    final theme = Theme.of(context);
    final firstWeekday = localizations.firstDayOfWeekIndex;
    final offset = (_month.weekday % 7 - firstWeekday + 7) % 7;
    final days = DateUtils.getDaysInMonth(_month.year, _month.month);
    final rows = (offset + days + 6) ~/ 7;
    final cells = <Widget>[
      for (int i = 0; i < 7; i++)
        Center(
          child: Text(
            localizations.narrowWeekdays[(firstWeekday + i) % 7],
            style: theme.textTheme.labelMedium,
          ),
        ),
      for (int i = 0; i < rows * 7; i++)
        if (i < offset || i >= offset + days)
          const SizedBox.shrink()
        else
          _day(
            context,
            DateTime.utc(_month.year, _month.month, i - offset + 1),
          ),
    ];
    // Table keeps calendar cells aligned while allowing text and touch targets
    // to grow for accessibility. No fixed-height grid can clip enlarged labels.
    return Table(
      children: [
        for (int i = 0; i < cells.length; i += 7)
          TableRow(children: cells.sublist(i, i + 7)),
      ],
    );
  }

  Widget _day(BuildContext context, DateTime date) {
    final theme = Theme.of(context);
    final endpoint =
        DateUtils.isSameDay(date, _from) || DateUtils.isSameDay(date, _to);
    final inside =
        _from != null &&
        _to != null &&
        !date.isBefore(_from!) &&
        !date.isAfter(_to!);
    final supported =
        !(date.year == 9999 && date.month == 12 && date.day == 31);
    return Semantics(
      selected: endpoint || inside,
      label: MaterialLocalizations.of(context).formatFullDate(date),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: InkWell(
          key: ValueKey('calendar-day-${CalendarDate.fromPicker(date)}'),
          onTap: supported ? () => _select(date) : null,
          borderRadius: BorderRadius.circular(AppRadii.control),
          child: Container(
            constraints: const BoxConstraints(minHeight: 44),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: endpoint
                  ? BorderRadius.circular(AppRadii.pill)
                  : null,
              color: endpoint
                  ? theme.colorScheme.primary
                  : inside
                  ? theme.colorScheme.primaryContainer
                  : null,
            ),
            child: ExcludeSemantics(
              child: Text(
                '${date.day}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: endpoint
                      ? theme.colorScheme.onPrimary
                      : supported
                      ? theme.colorScheme.onSurface
                      : theme.disabledColor,
                  fontWeight: endpoint ? FontWeight.w700 : null,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
