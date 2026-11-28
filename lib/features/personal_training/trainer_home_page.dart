import 'package:flutter/material.dart';
import '../gym_join/join_gym_page.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/navigation/foundation_screens.dart';
import '../../app/theme/design_tokens.dart';
import '../../shared/widgets/glass.dart';
import '../admin_dashboard/providers/dashboard_providers.dart';
import '../auth/models/session_state.dart';
import '../auth/providers/session_controller.dart';
import '../member_app/member_home.dart';
import '../member_app/member_home_page.dart';
import 'pt.dart';
import 'pt_pages.dart';
import 'pt_widgets.dart';
import 'trainer_clients.dart';
import '../../shared/contact/member_contact.dart';
import '../../shared/widgets/confirm_dialog.dart';
import '../../shared/widgets/page_section.dart';

/// `/home` for a signed-in user: trainers get their PT clients, members their
/// membership home; everyone else keeps the account screen.
class RoleHome extends ConsumerWidget {
  const RoleHome({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(adminGymProvider) != null) {
      return const AuthenticatedHomeScreen();
    }
    if (ref.watch(ptGymIdProvider) != null) return const TrainerHomePage();
    if (ref.watch(memberGymIdProvider) != null) return const MemberHomePage();
    // Signed in with a verified phone but in no gym yet: ask one to join.
    final session = ref.watch(sessionControllerProvider);
    if (session is SessionAuthenticated &&
        session.identity.user.phoneVerified &&
        session.identity.gymAccess.isEmpty) {
      return const JoinGymPage();
    }
    return const AuthenticatedHomeScreen();
  }
}

const _activeQuery = (memberId: null, trainerId: null, status: PtStatus.active);

/// What a trainer needs on the gym floor: today's clients and one-tap
/// session logging. No prices, payments or commission.
class TrainerHomePage extends ConsumerStatefulWidget {
  const TrainerHomePage({super.key});
  @override
  ConsumerState<TrainerHomePage> createState() => _TrainerHomePageState();
}

class _TrainerHomePageState extends ConsumerState<TrainerHomePage> {
  final _busy = <String>{};

  void _open(PtPackage pkg) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        body: SafeArea(child: PtPackageDetailPage(packageId: pkg.id)),
      ),
    ),
  );

  Future<void> _log(PtPackage pkg) async {
    final gymId = ref.read(ptGymIdProvider);
    if (gymId == null || _busy.contains(pkg.id)) return;
    final messenger = ScaffoldMessenger.of(context);
    final container = ProviderScope.containerOf(context, listen: false);
    setState(() => _busy.add(pkg.id));
    try {
      final updated = await ref
          .read(ptRepositoryProvider)
          .logSession(gymId, pkg.id);
      invalidatePt(container.invalidate);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Logged for ${pkg.member?.name ?? 'client'} · '
            '${updated.sessionsLeft} left',
          ),
        ),
      );
    } on PtFailure catch (failure) {
      messenger.showSnackBar(SnackBar(content: Text(failure.message)));
    } finally {
      if (mounted) setState(() => _busy.remove(pkg.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final session = ref.watch(sessionControllerProvider);
    final user = session is SessionAuthenticated ? session.identity.user : null;
    final name = (user?.displayName?.trim().isNotEmpty ?? false)
        ? user!.displayName!.trim().split(' ').first
        : null;
    final state = ref.watch(ptPackagesProvider(_activeQuery));
    final rows = state.asData?.value;
    final left = rows?.fold<int>(0, (sum, pkg) => sum + pkg.sessionsLeft);
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(ptPackagesProvider(_activeQuery));
            ref.invalidate(myClientsProvider);
            await ref.read(ptPackagesProvider(_activeQuery).future);
          },
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      name == null ? 'My clients' : 'Hi $name',
                      style: theme.textTheme.headlineSmall,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Account',
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const Scaffold(
                          body: SafeArea(child: AuthenticatedHomeScreen()),
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.account_circle_outlined),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              GlassCard(
                child: Row(
                  children: [
                    Expanded(
                      child: _Stat(
                        value: rows == null ? '–' : '${rows.length}',
                        label: 'Active PT clients',
                      ),
                    ),
                    Expanded(
                      child: _Stat(
                        value: left == null ? '–' : '$left',
                        label: 'Sessions to run',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text('PT clients', style: theme.textTheme.titleMedium),
              const SizedBox(height: AppSpacing.sm),
              if (state.hasError && rows == null)
                PlainBlock(
                  child: Column(
                    children: [
                      Text(
                        state.error is PtFailure
                            ? (state.error! as PtFailure).message
                            : 'Clients could not be loaded.',
                        textAlign: TextAlign.center,
                      ),
                      TextButton(
                        onPressed: () =>
                            ref.invalidate(ptPackagesProvider(_activeQuery)),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              else if (rows == null)
                const Center(child: CircularProgressIndicator())
              else if (rows.isEmpty)
                const PlainBlock(
                  child: Text(
                    'No active PT clients yet. When the gym sells you a PT '
                    'package, the client shows up here.',
                    textAlign: TextAlign.center,
                  ),
                )
              else
                for (final pkg in rows) ...[
                  PtPackageTile(
                    pkg: pkg,
                    onTap: () => _open(pkg),
                    onLog: _busy.contains(pkg.id) ? null : () => _log(pkg),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],
              const SizedBox(height: AppSpacing.lg),
              _MyMembers(onRefresh: () => ref.invalidate(myClientsProvider)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});
  final String value, label;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: theme.textTheme.headlineMedium),
        Text(label, style: theme.textTheme.bodySmall),
      ],
    );
  }
}

/// Members this trainer works with; any active member can be taken on.
class _MyMembers extends ConsumerStatefulWidget {
  const _MyMembers({required this.onRefresh});
  final VoidCallback onRefresh;
  @override
  ConsumerState<_MyMembers> createState() => _MyMembersState();
}

class _MyMembersState extends ConsumerState<_MyMembers> {
  bool _busy = false;

  Future<void> _write(
    Future<void> Function(String gymId) action,
    String done,
  ) async {
    final gymId = ref.read(ptGymIdProvider);
    if (gymId == null || _busy) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await action(gymId);
      widget.onRefresh();
      messenger.showSnackBar(SnackBar(content: Text(done)));
    } on PtFailure catch (failure) {
      messenger.showSnackBar(SnackBar(content: Text(failure.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _takeOn(List<TrainerClient> current) async {
    final picked = await showDialog<TrainerClient>(
      context: context,
      builder: (_) => TakeOnMemberDialog(
        alreadyMine: {for (final row in current) row.memberId},
      ),
    );
    if (picked == null) return;
    await _write(
      (gymId) => ref
          .read(trainerClientRepositoryProvider)
          .takeOn(gymId, picked.memberId),
      '${picked.name} added to your members',
    );
  }

  Future<void> _release(TrainerClient client) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Remove ${client.name} from your members?',
      message: 'Any PT package stays as it is.',
      keepLabel: 'Keep member',
      confirmLabel: 'Remove member',
      destructive: true,
    );
    if (confirmed != true) return;
    await _write(
      (gymId) => ref
          .read(trainerClientRepositoryProvider)
          .release(gymId, client.memberId),
      '${client.name} removed from your members',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = ref.watch(myClientsProvider);
    final rows = state.asData?.value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                rows == null ? 'My members' : 'My members · ${rows.length}',
                style: theme.textTheme.titleMedium,
              ),
            ),
            TextButton.icon(
              onPressed: _busy || rows == null ? null : () => _takeOn(rows),
              icon: const Icon(Icons.person_add_alt_1_outlined),
              label: const Text('Take on'),
            ),
          ],
        ),
        if (state.hasError && rows == null)
          PlainBlock(
            child: Column(
              children: [
                Text(
                  state.error is PtFailure
                      ? (state.error! as PtFailure).message
                      : 'Members could not be loaded.',
                  textAlign: TextAlign.center,
                ),
                TextButton(
                  onPressed: widget.onRefresh,
                  child: const Text('Retry'),
                ),
              ],
            ),
          )
        else if (rows == null)
          const LinearProgressIndicator(minHeight: 2)
        else if (rows.isEmpty)
          const PlainBlock(
            child: Text(
              'Take on any member of the gym to keep them on your list.',
              textAlign: TextAlign.center,
            ),
          )
        else
          SeparatedRows(
            children: [
              for (final client in rows)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(client.name),
                  subtitle: Text(client.memberCode),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (client.phone != null)
                        IconButton(
                          tooltip: 'Call',
                          onPressed: () => callMember(context, client.phone!),
                          icon: const Icon(Icons.call_outlined),
                        ),
                      IconButton(
                        tooltip: 'Remove from my members',
                        onPressed: _busy ? null : () => _release(client),
                        icon: const Icon(Icons.person_remove_outlined),
                      ),
                    ],
                  ),
                ),
            ],
          ),
      ],
    );
  }
}
