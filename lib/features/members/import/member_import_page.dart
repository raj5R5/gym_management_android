import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_routes.dart';
import '../../../app/theme/design_tokens.dart';
import '../../../shared/formatting/inr.dart';
import '../../../shared/sharing/share_pdf.dart';
import '../../../shared/widgets/glass.dart';
import '../../../shared/widgets/page_section.dart';
import '../../admin_dashboard/providers/dashboard_providers.dart';
import '../../memberships/models/billing_models.dart';
import '../../memberships/providers/membership_providers.dart';
import '../data/onboarding_failure.dart';
import '../providers/member_overview_providers.dart';
import '../providers/onboarding_providers.dart';
import 'member_import.dart';

/// Brings a gym's existing members in from a CSV or Excel sheet: choose the
/// file, check every row, then add the good ones one by one.
class MemberImportPage extends ConsumerStatefulWidget {
  const MemberImportPage({super.key});
  @override
  ConsumerState<MemberImportPage> createState() => _MemberImportPageState();
}

enum _Stage { choose, preview, importing, done }

class _Outcome {
  const _Outcome(this.row, this.error);
  final ImportRow row;

  /// Null when the member was added.
  final String? error;
}

class _MemberImportPageState extends ConsumerState<MemberImportPage> {
  _Stage _stage = _Stage.choose;
  String? _fileName, _error;
  List<ImportRow> _rows = const [];
  final _outcomes = <_Outcome>[];
  bool _loading = false;

  /// One key per row of this import: a retry never adds the member twice.
  final _importId = List.generate(
    16,
    (_) => Random.secure().nextInt(36).toRadixString(36),
  ).join();

  Future<List<MembershipPlan>> _plans(String gymId) async {
    final repository = ref.read(membershipRepositoryProvider);
    final plans = <MembershipPlan>[];
    for (var page = 1; page <= 20; page++) {
      final result = await repository.plans(gymId, page);
      plans.addAll(result.items);
      if (!result.pagination.hasNext) break;
    }
    return plans;
  }

  Future<void> _choose() async {
    final gym = ref.read(adminGymProvider);
    if (gym == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final picked = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['csv', 'xlsx', 'txt'],
      );
      final file = picked.singleOrNull;
      if (file == null) return;
      final sheet = readMemberSheet(await file.readAsBytes(), file.name);
      final plans = await _plans(gym.gymId);
      final rows = checkImportRows(sheet, plans);
      if (!mounted) return;
      setState(() {
        _fileName = file.name;
        _rows = rows;
        _stage = _Stage.preview;
      });
    } on MemberSheetFailure catch (failure) {
      if (mounted) setState(() => _error = failure.message);
    } on Object {
      if (mounted) {
        setState(
          () => _error =
              'The file could not be read. Save it as CSV or Excel (.xlsx) and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _template() => shareFile(
    Uint8List.fromList(utf8.encode(memberImportTemplate)),
    fileName: 'member-import-template.csv',
    mimeType: 'text/csv',
    text: 'Fill one member per row, then import it in the app.',
  );

  Future<void> _import() async {
    final gym = ref.read(adminGymProvider);
    if (gym == null) return;
    // The page may close mid-import; keep the container, not ref.
    final container = ProviderScope.containerOf(context, listen: false);
    final repository = container.read(memberOnboardingRepositoryProvider);
    setState(() {
      _stage = _Stage.importing;
      _outcomes.clear();
    });
    for (final row in _rows.where((row) => row.ok)) {
      String? error;
      try {
        await repository.complete(
          gym.gymId,
          row.toRequest(),
          'import-$_importId-${row.line}',
        );
      } on OnboardingFailure catch (failure) {
        error = switch (failure.diagnostics?.code) {
          'DUPLICATE_MEMBER_CODE' => 'Member code already exists',
          'DUPLICATE_MEMBER_PHONE' => 'Phone already belongs to a member',
          _ => failure.message,
        };
      } on Object {
        error = 'Could not be added. Try this member again later.';
      }
      if (!mounted) return;
      setState(() => _outcomes.add(_Outcome(row, error)));
    }
    container
      ..invalidate(memberOverviewProvider)
      ..invalidate(dashboardProvider);
    if (mounted) setState(() => _stage = _Stage.done);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ready = _rows.where((row) => row.ok).length;
    return PopScope(
      // Leaving mid-import would hide which members were added.
      canPop: _stage != _Stage.importing,
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          Row(
            children: [
              IconButton(
                tooltip: 'Back',
                onPressed: _stage == _Stage.importing
                    ? null
                    : () => context.canPop()
                          ? context.pop()
                          : context.go(AppRoutes.members),
                icon: const Icon(Icons.arrow_back),
              ),
              Expanded(
                child: Text(
                  'Import members',
                  style: theme.textTheme.titleLarge,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          ...switch (_stage) {
            _Stage.choose => _chooseStep(theme),
            _Stage.preview => _previewStep(theme, ready),
            _Stage.importing => _importingStep(theme, ready),
            _Stage.done => _doneStep(theme),
          },
        ],
      ),
    );
  }

  List<Widget> _chooseStep(ThemeData theme) => [
    Text(
      'Bring in the members you already have, with their current plan and '
      'what they have paid.',
      style: theme.textTheme.bodyMedium,
    ),
    const SizedBox(height: AppSpacing.lg),
    GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Your sheet needs these columns',
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final (label, note) in const [
            ('Member code', 'optional; left out, the app numbers them'),
            ('First name, Last name', 'or one Name column'),
            ('Phone', '10-digit mobile number'),
            ('Plan', 'the plan name, as in your Plans'),
            ('Plan started', 'e.g. 2026-11-01 or 01/11/2026'),
            ('Paid', 'optional, what they paid for this plan'),
            ('Method', 'optional: cash, upi, card, bank'),
          ])
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: label,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    TextSpan(text: ' · $note'),
                  ],
                ),
                style: theme.textTheme.bodySmall,
              ),
            ),
        ],
      ),
    ),
    const SizedBox(height: AppSpacing.lg),
    if (_error != null) ...[
      Text(
        _error!,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: AppPalette.accentLight,
        ),
      ),
      const SizedBox(height: AppSpacing.md),
    ],
    FilledButton.icon(
      onPressed: _loading ? null : _choose,
      icon: _loading
          ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.upload_file),
      label: const Text('Choose CSV or Excel file'),
    ),
    const SizedBox(height: AppSpacing.sm),
    OutlinedButton.icon(
      onPressed: _template,
      icon: const Icon(Icons.description_outlined),
      label: const Text('Get the template'),
    ),
  ];

  List<Widget> _previewStep(ThemeData theme, int ready) {
    final problems = _rows.length - ready;
    return [
      Text(_fileName ?? '', style: theme.textTheme.bodySmall),
      const SizedBox(height: AppSpacing.sm),
      Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: problems > 0 ? AppPalette.amberWash : AppColors.glass,
          borderRadius: BorderRadius.circular(AppRadii.lg),
        ),
        child: Text(
          problems == 0
              ? '$ready ${ready == 1 ? 'member is' : 'members are'} ready to import.'
              : '$ready ready · $problems ${problems == 1 ? 'needs' : 'need'} fixing. Rows with problems are skipped; '
                    'fix them in the sheet and import that file again.',
          style: theme.textTheme.titleSmall,
        ),
      ),
      const SizedBox(height: AppSpacing.md),
      FilledButton(
        onPressed: ready == 0 ? null : _import,
        child: Text('Import $ready ${ready == 1 ? 'member' : 'members'}'),
      ),
      TextButton(
        onPressed: () => setState(() {
          _stage = _Stage.choose;
          _rows = const [];
        }),
        child: const Text('Choose another file'),
      ),
      PageSection(
        title: 'Rows',
        top: AppSpacing.lg,
        children: [
          SeparatedRows(
            children: [for (final row in _rows) _RowTile(row: row)],
          ),
        ],
      ),
    ];
  }

  List<Widget> _importingStep(ThemeData theme, int ready) => [
    const SizedBox(height: AppSpacing.xl),
    Text(
      'Adding ${_outcomes.length + 1 > ready ? ready : _outcomes.length + 1} of $ready…',
      style: theme.textTheme.titleMedium,
    ),
    const SizedBox(height: AppSpacing.md),
    LinearProgressIndicator(
      value: ready == 0 ? null : _outcomes.length / ready,
    ),
    const SizedBox(height: AppSpacing.md),
    Text(
      'Keep this screen open until it finishes.',
      style: theme.textTheme.bodySmall,
    ),
  ];

  List<Widget> _doneStep(ThemeData theme) {
    final added = _outcomes.where((outcome) => outcome.error == null).length;
    final failed = _outcomes.where((outcome) => outcome.error != null).toList();
    return [
      Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: failed.isEmpty ? AppColors.glass : AppPalette.amberWash,
          borderRadius: BorderRadius.circular(AppRadii.lg),
        ),
        child: Text(
          failed.isEmpty
              ? '$added ${added == 1 ? 'member' : 'members'} added.'
              : '$added added · ${failed.length} could not be added.',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      if (failed.isNotEmpty)
        PageSection(
          title: 'Not added',
          top: AppSpacing.lg,
          children: [
            SeparatedRows(
              children: [
                for (final outcome in failed)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      'Row ${outcome.row.line} · ${outcome.row.name}',
                    ),
                    subtitle: Text(outcome.error!),
                  ),
              ],
            ),
          ],
        ),
      const SizedBox(height: AppSpacing.lg),
      FilledButton(
        onPressed: () => context.go(AppRoutes.members),
        child: const Text('Go to members'),
      ),
    ];
  }
}

class _RowTile extends StatelessWidget {
  const _RowTile({required this.row});
  final ImportRow row;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dates = MaterialLocalizations.of(context);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        row.ok ? Icons.check_circle_outline : Icons.error_outline,
        color: row.ok ? null : AppPalette.accentLight,
      ),
      title: Text(
        [
          row.name.isEmpty ? 'Row ${row.line}' : row.name,
          if (row.memberCode.isNotEmpty) row.memberCode,
        ].join(' · '),
      ),
      subtitle: Text(
        row.ok
            ? '${row.plan!.name} · from ${dates.formatMediumDate(row.startDate!.value)}'
                  ' · ${row.paidPaise == 0 ? 'nothing paid' : '${formatInrPaise(row.paidPaise)} paid'}'
            : 'Row ${row.line}: ${row.problems.map((problem) => problem.replaceAll(RegExp(r'\.$'), '')).join(' · ')}',
        style: row.ok
            ? null
            : theme.textTheme.bodySmall?.copyWith(
                color: AppPalette.accentLight,
              ),
      ),
    );
  }
}
