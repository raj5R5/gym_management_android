import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/router/app_routes.dart';
import '../../app/theme/design_tokens.dart';
import '../../shared/sharing/share_pdf.dart';
import '../../shared/widgets/glass.dart';
import '../../shared/widgets/page_section.dart';
import '../branches/branches.dart';
import '../owner_profile/owner_profile.dart';
import 'report_pdf.dart';
import 'reports.dart';
import '../../shared/widgets/card_reveal.dart';

/// The list of reports.
class ReportsPage extends StatelessWidget {
  const ReportsPage({super.key});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        Text('Reports', style: theme.textTheme.headlineSmall),
        Text(
          'Pick a report, choose the period, and share it as a PDF.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: AppSpacing.md),
        SeparatedRows(
          indent: 40,
          children: [
            for (final kind in ReportKind.values)
              Builder(
                builder: (tileContext) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(kind.icon),
                  title: Text(kind.title),
                  subtitle: Text(kind.subtitle),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => pushFromCard(
                    tileContext,
                    '${AppRoutes.reports}/${kind.wire}',
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class ReportPage extends ConsumerStatefulWidget {
  const ReportPage({super.key, required this.kind});
  final ReportKind kind;
  @override
  ConsumerState<ReportPage> createState() => _ReportPageState();
}

class _ReportPageState extends ConsumerState<ReportPage> {
  ReportPeriod _period = ReportPeriod.thisMonth;
  bool _all = false, _sharing = false;

  ReportQuery get _query =>
      (kind: widget.kind, period: _period, allBranches: _all);

  String _periodLabel(ReportData data) {
    final localizations = MaterialLocalizations.of(context);
    if (!widget.kind.usesPeriod) {
      return 'As of ${localizations.formatMediumDate(data.to)}';
    }
    return '${localizations.formatMediumDate(data.from)} – '
        '${localizations.formatMediumDate(data.to)}';
  }

  Future<void> _share(ReportData data) async {
    if (_sharing) return;
    final messenger = ScaffoldMessenger.of(context);
    final period = _periodLabel(data);
    final generated = MaterialLocalizations.of(
      context,
    ).formatMediumDate(DateTime.now());
    final gymName = _all
        ? 'All branches'
        : ref.read(ownerProfileProvider).value?.gymName ??
              (data.branchNames.isEmpty ? '' : data.branchNames.first);
    setState(() => _sharing = true);
    try {
      final bytes = await buildReportPdf(
        data: data,
        gymName: gymName,
        periodLabel: period,
        generatedOn: generated,
      );
      await sharePdf(
        bytes,
        title: '${data.kind.title} $period',
        text: '${data.kind.title} · $period',
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('The PDF could not be created.')),
      );
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = ref.watch(reportProvider(_query));
    final data = state.asData?.value;
    final branches = ref.watch(branchNamesProvider);
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        Row(
          children: [
            IconButton(
              tooltip: 'Back',
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.arrow_back),
            ),
            Expanded(
              child: Text(
                widget.kind.title,
                style: theme.textTheme.headlineSmall,
              ),
            ),
            IconButton(
              tooltip: 'Share PDF',
              onPressed: data == null || _sharing ? null : () => _share(data),
              icon: _sharing
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.picture_as_pdf_outlined),
            ),
          ],
        ),
        if (widget.kind.usesPeriod)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final period in ReportPeriod.values) ...[
                  ChoiceChip(
                    label: Text(period.label),
                    selected: _period == period,
                    onSelected: (_) => setState(() => _period = period),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                ],
              ],
            ),
          ),
        if (branches.length > 1) ...[
          const SizedBox(height: AppSpacing.sm),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('This branch')),
              ButtonSegment(value: true, label: Text('All branches')),
            ],
            selected: {_all},
            onSelectionChanged: (value) => setState(() => _all = value.first),
          ),
        ],
        const SizedBox(height: AppSpacing.sm),
        if (data != null)
          Text(
            [
              _periodLabel(data),
              if (data.allBranches) '${data.branchNames.length} branches',
            ].join(' · '),
            style: theme.textTheme.bodySmall,
          ),
        if (state.hasError && data == null)
          GlassCard(
            child: Column(
              children: [
                Text(
                  state.error is ReportFailure
                      ? (state.error! as ReportFailure).message
                      : 'The report could not be loaded.',
                  textAlign: TextAlign.center,
                ),
                TextButton(
                  onPressed: () => ref.invalidate(reportProvider(_query)),
                  child: const Text('Retry'),
                ),
              ],
            ),
          )
        else if (data == null)
          const Padding(
            padding: EdgeInsets.all(AppSpacing.xl),
            child: Center(child: CircularProgressIndicator()),
          )
        else
          for (final (index, section) in reportSections(data).indexed)
            Padding(
              padding: EdgeInsets.only(
                top: index == 0 ? AppSpacing.md : AppSpacing.xl,
              ),
              // The headline figures are the main block; the rest sit plain.
              child: ReportSectionCard(section: section, card: index == 0),
            ),
      ],
    );
  }
}

class ReportSectionCard extends StatelessWidget {
  const ReportSectionCard({
    super.key,
    required this.section,
    this.card = false,
  });
  final ReportSection section;

  /// Draws the section on a glass card; other sections sit on the page.
  final bool card;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(section.title, style: theme.textTheme.titleMedium),
        ),
        if (section.note != null)
          Text(section.note!, style: theme.textTheme.bodySmall),
        if (section.isEmpty && section.empty != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(section.empty!, style: theme.textTheme.bodySmall),
        ],
        if (section.figures.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = (constraints.maxWidth - AppSpacing.md) / 2;
              return Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.sm,
                children: [
                  for (final figure in section.figures)
                    SizedBox(
                      width: width,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              figure.value,
                              style: theme.textTheme.headlineSmall?.copyWith(
                                color: figure.warn ? AppPalette.amber : null,
                              ),
                            ),
                          ),
                          Text(figure.label, style: theme.textTheme.bodySmall),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
        ],
        if (section.bars.isNotEmpty) const SizedBox(height: AppSpacing.sm),
        for (final bar in section.bars)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                SizedBox(
                  width: 92,
                  child: Text(
                    bar.label,
                    style: theme.textTheme.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadii.sm),
                    child: LinearProgressIndicator(
                      minHeight: 8,
                      value: bar.fraction,
                      color: bar.negative ? AppPalette.amber : null,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                SizedBox(
                  width: 84,
                  child: Text(
                    bar.value,
                    textAlign: TextAlign.right,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        if (section.rows.isNotEmpty)
          SeparatedRows(
            children: [
              for (final row in section.rows)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(row.title),
                  subtitle: row.subtitle == null ? null : Text(row.subtitle!),
                  trailing: Text(
                    row.trailing,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
            ],
          ),
      ],
    );
    return card ? GlassCard(child: body) : body;
  }
}
