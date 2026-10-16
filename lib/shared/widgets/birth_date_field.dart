import 'package:flutter/material.dart';
import '../../features/admin_dashboard/models/dashboard_models.dart';
import '../validators/profile_validators.dart';

/// The caller retains the original ISO calendar value. Display formatting and
/// opening/cancelling the picker never rewrite that value or make a draft dirty.
class BirthDateField extends StatefulWidget {
  const BirthDateField({
    super.key,
    required this.controller,
    required this.enabled,
  });
  final TextEditingController controller;
  final bool enabled;
  @override
  State<BirthDateField> createState() => _BirthDateFieldState();
}

class _BirthDateFieldState extends State<BirthDateField> {
  final _display = TextEditingController();
  bool _opening = false;
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_sync);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(BirthDateField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_sync);
      widget.controller.addListener(_sync);
    }
    _sync();
  }

  void _sync() {
    final text = widget.controller.text;
    try {
      _display.text = text.isEmpty
          ? ''
          : MaterialLocalizations.of(
              context,
            ).formatShortDate(CalendarDate.parse(text).value);
    } on FormatException {
      _display.text = text;
    }
    if (mounted) setState(() {});
  }

  Future<void> _pick() async {
    if (_opening || !widget.enabled) return;
    _opening = true;
    FocusScope.of(context).unfocus();
    try {
      final today = CalendarDate.fromPicker(DateTime.now().toUtc()).value;
      DateTime? selected;
      try {
        selected = CalendarDate.parse(widget.controller.text).value;
      } on FormatException {
        selected = null;
      }
      final result = await showDatePicker(
        context: context,
        initialDate: selected != null && !selected.isAfter(today)
            ? selected
            : today,
        firstDate: DateTime(1),
        lastDate: today,
        currentDate: today,
        helpText: 'Date of birth',
      );
      if (result != null && mounted && widget.enabled) {
        widget.controller.text = CalendarDate.fromPicker(result).toString();
      }
    } finally {
      _opening = false;
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_sync);
    _display.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        'Date of birth (optional)',
        style: Theme.of(context).textTheme.labelLarge,
      ),
      const SizedBox(height: 8),
      TextFormField(
        key: const ValueKey('dateOfBirth'),
        controller: _display,
        readOnly: true,
        maxLines: 2,
        enabled: widget.enabled,
        onTap: _pick,
        validator: (_) => validateBirthDate(widget.controller.text),
        decoration: InputDecoration(
          hintText: 'Choose a date',
          prefixIcon: const Icon(Icons.calendar_month_outlined),
          suffixIcon: widget.controller.text.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Clear date of birth',
                  onPressed: widget.enabled ? widget.controller.clear : null,
                  icon: const Icon(Icons.clear),
                ),
        ),
      ),
    ],
  );
}
