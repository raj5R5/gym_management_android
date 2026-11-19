import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router/app_routes.dart';
import '../../app/theme/design_tokens.dart';
import '../../shared/formatting/inr.dart';
import '../../shared/widgets/glass.dart';
import '../admin_dashboard/providers/dashboard_providers.dart';
import '../members/models/member_overview.dart';
import '../members/photos/member_photo_widgets.dart';
import '../members/providers/member_overview_providers.dart';
import '../members/providers/member_providers.dart';
import '../memberships/presentation/billing_components.dart';
import 'visit_models.dart';
import 'visit_repository.dart';

/// Front-desk check-in: scan a member QR or search, then one tap.
class CheckInPage extends ConsumerStatefulWidget {
  const CheckInPage({super.key});
  @override
  ConsumerState<CheckInPage> createState() => _CheckInPageState();
}

class _CheckInPageState extends ConsumerState<CheckInPage> {
  final _search = TextEditingController();
  String _query = '';
  bool _busy = false;
  CheckInResult? _last;
  String? _error;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _refreshCaches(String memberId) {
    ref.invalidate(todayVisitsProvider);
    ref.invalidate(memberVisitHistoryProvider(memberId));
    ref.invalidate(memberOverviewProvider);
    ref.invalidate(dashboardProvider);
  }

  Future<void> _checkIn(
    String memberId, {
    VisitMethod method = VisitMethod.manual,
    bool override = false,
  }) async {
    final gym = ref.read(adminGymProvider);
    if (gym == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await ref
          .read(visitRepositoryProvider)
          .checkIn(gym.gymId, memberId, method: method, override: override);
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      _refreshCaches(memberId);
      setState(() {
        _last = result;
        _search.clear();
        _query = '';
      });
    } on MembershipNotActive catch (refusal) {
      if (!mounted) return;
      setState(() => _busy = false);
      final choice = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(
            Icons.warning_amber_rounded,
            color: AppPalette.amber,
          ),
          title: Text(refusal.title),
          content: Text(refusal.message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Don't check in"),
            ),
            // A frozen membership is paid for; renewing is not the fix.
            if (refusal.state != 'frozen')
              TextButton(
                onPressed: () => Navigator.pop(context, 'renew'),
                child: Text(refusal.state == 'none' ? 'Add plan' : 'Renew'),
              ),
            FilledButton(
              onPressed: () => Navigator.pop(context, 'override'),
              child: const Text('Check in anyway'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      if (choice == 'override') {
        await _checkIn(memberId, method: method, override: true);
      } else if (choice == 'renew') {
        context.push(membershipPath(scopeFor(gym, memberId)));
      }
      return;
    } on VisitFailure catch (failure) {
      if (mounted) setState(() => _error = failure.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _scan() async {
    final gym = ref.read(adminGymProvider);
    if (gym == null) return;
    final raw = await context.push<String>(AppRoutes.checkInScan);
    if (raw == null || !mounted) return;
    final memberId = MemberQrCode.memberIdFor(raw, gymId: gym.gymId);
    if (memberId == null) {
      setState(
        () => _error = MemberQrCode.isOtherGym(raw, gymId: gym.gymId)
            ? 'This QR belongs to a member of another gym.'
            : 'This isn’t a MuscleDesk member QR.',
      );
      return;
    }
    await _checkIn(memberId, method: VisitMethod.qr);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final today = ref.watch(todayVisitsProvider).asData?.value;
    final results = _query.isEmpty
        ? null
        : ref.watch(
            memberOverviewProvider(
              MemberOverviewQuery(search: _query, limit: 10),
            ),
          );
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Check in', style: theme.textTheme.headlineMedium),
            ),
            TextButton.icon(
              onPressed: () => context.push(AppRoutes.todayVisits),
              icon: const Icon(Icons.today_outlined),
              label: Text(today == null ? 'Today' : 'Today · ${today.total}'),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        FilledButton.icon(
          onPressed: _busy ? null : _scan,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
          icon: const Icon(Icons.qr_code_scanner),
          label: const Text('Scan member QR'),
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          controller: _search,
          enabled: !_busy,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            labelText: 'Or search a member',
            hintText: 'Name, phone or member code',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _query.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear search',
                    onPressed: () => setState(() {
                      _search.clear();
                      _query = '';
                    }),
                    icon: const Icon(Icons.close),
                  ),
          ),
          onSubmitted: (value) => setState(() => _query = value.trim()),
          onChanged: (value) {
            // Search as the owner types, once there is enough to narrow it.
            final text = value.trim();
            if (text.length >= 2 || text.isEmpty) setState(() => _query = text);
          },
        ),
        const SizedBox(height: AppSpacing.md),
        if (_busy) const LinearProgressIndicator(minHeight: 2),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: Text(
              _error!,
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ),
        if (_last != null && _query.isEmpty) CheckInResultCard(result: _last!),
        if (results != null)
          ...switch (results) {
            AsyncData(:final value?) when value.rows.isEmpty => [
              Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Text('No members match “$_query”.'),
              ),
            ],
            AsyncData(:final value?) => [
              for (final row in value.rows)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: _SearchRow(
                    row: row,
                    busy: _busy,
                    onCheckIn: () => _checkIn(row.member.id),
                  ),
                ),
            ],
            AsyncError() => [const Text('Search failed. Try again.')],
            _ => [const LinearProgressIndicator(minHeight: 2)],
          },
      ],
    );
  }
}

class _SearchRow extends StatelessWidget {
  const _SearchRow({
    required this.row,
    required this.busy,
    required this.onCheckIn,
  });
  final MemberOverviewRow row;
  final bool busy;
  final VoidCallback onCheckIn;
  @override
  Widget build(BuildContext context) {
    final membership = row.membership;
    final active = membership?.state == OverviewMembershipState.active;
    return GlassCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      radius: AppRadii.lg,
      child: Row(
        children: [
          ExcludeSemantics(
            child: MemberPhotoAvatar(member: row.member, radius: 20),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.member.name,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                Text(
                  membership == null
                      ? '${row.member.memberCode} · No membership'
                      : '${row.member.memberCode} · ${membership.statusLabel}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: active ? null : AppPalette.accentLight,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          FilledButton(
            onPressed: busy ? null : onCheckIn,
            child: Text(
              'Check in',
              semanticsLabel: 'Check in ${row.member.name}',
            ),
          ),
        ],
      ),
    );
  }
}

/// Confirmation after a check-in, with anything the desk should act on.
class CheckInResultCard extends ConsumerWidget {
  const CheckInResultCard({super.key, required this.result});
  final CheckInResult result;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final gym = ref.watch(adminGymProvider);
    final membership = result.membership;
    // Renew when it ends soon, has ended, or there is none to show.
    final renew =
        membership == null ||
        membership.expiringSoon ||
        membership.state == OverviewMembershipState.expired;
    final time = TimeOfDay.fromDateTime(
      result.visit.checkedInAt,
    ).format(context);
    final headline = result.alreadyCheckedIn
        ? 'Already checked in today at $time'
        : result.visit.override
        ? 'Checked in with override at $time'
        : 'Checked in at $time';
    return Semantics(
      liveRegion: true,
      child: GlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  result.visit.override
                      ? Icons.warning_amber_rounded
                      : Icons.check_circle,
                  color: result.visit.override
                      ? AppPalette.amber
                      : theme.colorScheme.primary,
                  size: 28,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    result.member.name,
                    style: theme.textTheme.titleLarge,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(headline, style: theme.textTheme.bodyMedium),
            if (membership != null)
              Text(
                '${membership.planName} · ${membership.statusLabel}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: membership.expiringSoon ? AppPalette.amber : null,
                ),
              ),
            if (result.balancePaise > 0 || renew)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: Wrap(
                  spacing: AppSpacing.sm,
                  children: [
                    if (result.balancePaise > 0)
                      OutlinedButton(
                        onPressed: gym == null
                            ? null
                            : () => context.push(
                                membershipPath(scopeFor(gym, result.member.id)),
                              ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppPalette.accentLight,
                        ),
                        child: Text(
                          '${formatCompactInrPaise(result.balancePaise)} due · Collect',
                        ),
                      ),
                    if (renew)
                      OutlinedButton(
                        onPressed: gym == null
                            ? null
                            : () => context.push(
                                membershipPath(scopeFor(gym, result.member.id)),
                              ),
                        child: Text(membership == null ? 'Add plan' : 'Renew'),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
