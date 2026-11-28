import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router/app_routes.dart';
import '../../app/theme/design_tokens.dart';
import '../../shared/contact/member_contact.dart';
import '../../shared/formatting/inr.dart';
import '../../shared/widgets/page_section.dart';
import '../admin_dashboard/providers/dashboard_providers.dart';
import '../members/presentation/member_components.dart';
import '../members/providers/member_providers.dart';
import '../owner_profile/owner_profile.dart';
import 'notifications.dart';

/// The bell in the top bar: a red count of unread notifications.
class NotificationBell extends ConsumerWidget {
  const NotificationBell({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread =
        ref.watch(notificationFeedProvider).asData?.value?.unread ?? 0;
    return IconButton(
      tooltip: unread == 0 ? 'Notifications' : 'Notifications, $unread unread',
      onPressed: () => context.push(AppRoutes.notifications),
      icon: Badge(
        isLabelVisible: unread > 0,
        backgroundColor: AppPalette.accentLight,
        label: Text(unread > 99 ? '99+' : '$unread'),
        child: const Icon(Icons.notifications_outlined),
      ),
    );
  }
}

/// Everything that needs the owner today, grouped by what to do about it.
class NotificationsPage extends ConsumerStatefulWidget {
  const NotificationsPage({super.key});
  @override
  ConsumerState<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends ConsumerState<NotificationsPage> {
  bool _marked = false;
  ProviderContainer? _container;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _container = ProviderScope.containerOf(context, listen: false);
  }

  @override
  void dispose() {
    // Leaving the page: the bell shows the new unread count.
    if (_marked) _container?.invalidate(notificationFeedProvider);
    super.dispose();
  }

  /// Opening the page marks what it shows as read, once loaded.
  Future<void> _markSeen() async {
    if (_marked) return;
    _marked = true;
    final gym = ref.read(adminGymProvider);
    if (gym == null) return;
    final container = ProviderScope.containerOf(context, listen: false);
    try {
      await container.read(notificationRepositoryProvider).markSeen(gym.gymId);
    } on NotificationFailure {
      // Unread counts are a convenience; the list itself is already shown.
      return;
    }
    // Keep the "new" marks on screen; the bell refreshes next time.
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = ref.watch(notificationFeedProvider);
    final feed = state.asData?.value;
    if (feed != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _markSeen());
    }
    final gymName = currentOwnerProfile(ref)?.gymName ?? '';
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(notificationFeedProvider);
        await ref.read(notificationFeedProvider.future).catchError((_) => null);
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          Row(
            children: [
              IconButton(
                tooltip: 'Back',
                onPressed: () => context.canPop()
                    ? context.pop()
                    : context.go(AppRoutes.dashboard),
                icon: const Icon(Icons.arrow_back),
              ),
              Expanded(
                child: Text('Notifications', style: theme.textTheme.titleLarge),
              ),
            ],
          ),
          if (state.hasError && feed == null)
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                children: [
                  Text(
                    state.error is NotificationFailure
                        ? (state.error! as NotificationFailure).message
                        : 'Notifications could not be loaded.',
                    textAlign: TextAlign.center,
                  ),
                  TextButton(
                    onPressed: () => ref.invalidate(notificationFeedProvider),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            )
          else if (feed == null)
            const Padding(
              padding: EdgeInsets.all(AppSpacing.xl),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (feed.items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxxl),
              child: Column(
                children: [
                  const Icon(Icons.notifications_none, size: 48),
                  const SizedBox(height: AppSpacing.md),
                  Text('All clear', style: theme.textTheme.titleMedium),
                  Text(
                    'Nothing needs your attention right now.',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            )
          else ...[
            Text(
              feed.unread == 0
                  ? '${feed.items.length} to look at'
                  : '${feed.unread} new · ${feed.items.length} to look at',
              style: theme.textTheme.bodySmall,
            ),
            for (final kind in NotificationKind.values)
              if (feed.of(kind) case final items when items.isNotEmpty)
                PageSection(
                  title: '${kind.label} · ${items.length}',
                  top: AppSpacing.xl,
                  trailing:
                      kind.remindable &&
                          items.where((item) => item.person != null).length > 1
                      ? TextButton.icon(
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => ReminderRunPage(
                                kind: kind,
                                items: items,
                                gymName: gymName,
                              ),
                            ),
                          ),
                          icon: const Icon(Icons.send_outlined, size: 18),
                          label: const Text('Remind all'),
                        )
                      : kind == NotificationKind.claim
                      ? TextButton(
                          onPressed: () =>
                              context.push(AppRoutes.paymentClaims),
                          child: const Text('Review'),
                        )
                      : kind == NotificationKind.join
                      ? TextButton(
                          onPressed: () => context.push(AppRoutes.joinRequests),
                          child: const Text('Review'),
                        )
                      : null,
                  children: [
                    SeparatedRows(
                      indent: 40,
                      children: [
                        for (final item in items)
                          _NotificationTile(item: item, gymName: gymName),
                      ],
                    ),
                  ],
                ),
          ],
        ],
      ),
    );
  }
}

class _NotificationTile extends ConsumerWidget {
  const _NotificationTile({required this.item, required this.gymName});
  final GymNotification item;
  final String gymName;

  void _open(BuildContext context, WidgetRef ref) {
    final gym = ref.read(adminGymProvider);
    if (gym == null) return;
    switch (item.kind) {
      case NotificationKind.claim:
        context.push(AppRoutes.paymentClaims);
      case NotificationKind.join:
        context.push(AppRoutes.joinRequests);
      case NotificationKind.followup:
        if (item.lead case final lead?) {
          context.push('${AppRoutes.leads}/${lead.id}');
        }
      case _:
        if (item.member case final member?) {
          context.push(memberPath(scopeFor(gym, member.id)));
        }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final person = item.person;
    final color = item.urgent ? AppPalette.accentLight : null;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: () => _open(context, ref),
      leading: Badge(
        isLabelVisible: item.unread,
        smallSize: 8,
        backgroundColor: AppPalette.accentLight,
        child: Icon(switch (item.kind) {
          NotificationKind.expiring => Icons.hourglass_bottom,
          NotificationKind.expired => Icons.event_busy_outlined,
          NotificationKind.dues => Icons.account_balance_wallet_outlined,
          NotificationKind.claim => Icons.mark_email_unread_outlined,
          NotificationKind.followup => Icons.contact_phone_outlined,
          NotificationKind.birthday => Icons.cake_outlined,
          NotificationKind.inactive => Icons.directions_walk,
          NotificationKind.join => Icons.group_add_outlined,
        }, color: color),
      ),
      title: Text(
        item.title,
        style: item.unread
            ? theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700)
            : null,
      ),
      subtitle: Text(
        item.amountPaise != null
            ? '${formatInrPaise(item.amountPaise!)} · ${item.detail}'
            : item.kind == NotificationKind.followup &&
                  item.detail.startsWith('Overdue') &&
                  item.date != null
            ? 'Overdue since ${MaterialLocalizations.of(context).formatShortMonthDay(item.date!)}'
            : item.detail,
      ),
      trailing: person == null || !item.kind.remindable
          ? null
          : IconButton(
              tooltip: 'WhatsApp ${person.firstName}',
              onPressed: () =>
                  whatsappMember(context, person.phone, item.message(gymName)),
              icon: const Icon(Icons.chat_outlined),
            ),
    );
  }
}

/// Sends one reminder after another: WhatsApp opens with the message ready,
/// the owner sends it there, comes back and taps Next.
class ReminderRunPage extends StatefulWidget {
  const ReminderRunPage({
    super.key,
    required this.kind,
    required this.items,
    required this.gymName,
  });
  final NotificationKind kind;
  final List<GymNotification> items;
  final String gymName;
  @override
  State<ReminderRunPage> createState() => _ReminderRunPageState();
}

class _ReminderRunPageState extends State<ReminderRunPage> {
  late final List<GymNotification> _queue = [
    for (final item in widget.items)
      if (item.person != null) item,
  ];
  int _index = 0, _sent = 0;

  Future<void> _send() async {
    final item = _queue[_index];
    await whatsappMember(
      context,
      item.person!.phone,
      item.message(widget.gymName),
    );
    if (!mounted) return;
    setState(() {
      _sent += 1;
      _index += 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final done = _index >= _queue.length;
    final item = done ? null : _queue[_index];
    return Scaffold(
      appBar: AppBar(title: Text('Remind · ${widget.kind.label}')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: done
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(Icons.check_circle_outline, size: 56),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      '$_sent ${_sent == 1 ? 'reminder' : 'reminders'} opened in WhatsApp.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    FilledButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Done'),
                    ),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '${_index + 1} of ${_queue.length}',
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    LinearProgressIndicator(value: _index / _queue.length),
                    const SizedBox(height: AppSpacing.xl),
                    Text(
                      item!.person!.name,
                      style: theme.textTheme.headlineSmall,
                    ),
                    Text(item.person!.phone, style: theme.textTheme.bodySmall),
                    const SizedBox(height: AppSpacing.md),
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      decoration: BoxDecoration(
                        color: AppColors.glass,
                        borderRadius: BorderRadius.circular(AppRadii.lg),
                      ),
                      child: Text(item.message(widget.gymName)),
                    ),
                    const Spacer(),
                    FilledButton.icon(
                      onPressed: _send,
                      icon: const Icon(Icons.chat_outlined),
                      label: const Text('Open in WhatsApp'),
                    ),
                    TextButton(
                      onPressed: () => setState(() => _index += 1),
                      child: const Text('Skip'),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
