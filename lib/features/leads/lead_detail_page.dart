import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router/app_routes.dart';
import '../../app/theme/design_tokens.dart';
import '../../shared/contact/member_contact.dart';
import '../admin_dashboard/providers/dashboard_providers.dart';
import '../members/presentation/member_components.dart';
import '../members/providers/member_providers.dart';
import '../owner_profile/owner_profile.dart';
import 'lead_widgets.dart';
import 'leads.dart';
import '../../shared/widgets/confirm_dialog.dart';
import '../../shared/widgets/round_action.dart';

class LeadDetailPage extends ConsumerStatefulWidget {
  const LeadDetailPage({super.key, required this.leadId});
  final String leadId;
  @override
  ConsumerState<LeadDetailPage> createState() => _LeadDetailPageState();
}

class _LeadDetailPageState extends ConsumerState<LeadDetailPage> {
  final _note = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _run(Future<Lead> Function(String gymId) action) async {
    final gym = ref.read(adminGymProvider);
    if (gym == null || _busy) return;
    final container = ProviderScope.containerOf(context, listen: false);
    setState(() => _busy = true);
    try {
      await action(gym.gymId);
      container
        ..invalidate(leadProvider(widget.leadId))
        ..invalidate(leadsProvider)
        ..invalidate(dashboardProvider);
    } on LeadFailure catch (failure) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(failure.message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  LeadRepository get _repo => ref.read(leadRepositoryProvider);

  Future<void> _followUp(Lead lead) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate:
          lead.nextFollowUpOn != null &&
              !lead.nextFollowUpOn!.isBefore(
                DateTime(now.year, now.month, now.day),
              )
          ? lead.nextFollowUpOn!
          : now.add(const Duration(days: 1)),
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 365)),
      helpText: 'Next follow-up',
    );
    if (picked == null) return;
    await _run(
      (gymId) => _repo.update(gymId, lead.id, {
        if (lead.status == LeadStatus.newLead) 'status': 'contacted',
        'nextFollowUpOn': _iso(picked),
      }),
    );
  }

  Future<void> _lost(Lead lead) async {
    // The dialog owns its text field; disposing it here while the dialog is
    // still animating out would crash.
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => const _LostReasonDialog(),
    );
    if (reason == null || reason.isEmpty) return;
    await _run(
      (gymId) => _repo.update(gymId, lead.id, {
        'status': 'lost',
        'lostReason': reason,
      }),
    );
  }

  void _convert(Lead lead) {
    final gym = ref.read(adminGymProvider);
    if (gym == null) return;
    context.push(
      '${AppRoutes.members}/new?gymId=${Uri.encodeQueryComponent(gym.gymId)}',
      extra: LeadPrefill(
        leadId: lead.id,
        firstName: lead.firstName,
        lastName: lead.lastName,
        phone: lead.phone,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = ref.watch(leadProvider(widget.leadId));
    final lead = state.asData?.value;
    final gym = ref.watch(adminGymProvider);
    if (lead == null) {
      return Center(
        child: state.hasError
            ? Text(
                state.error is LeadFailure
                    ? (state.error! as LeadFailure).message
                    : 'Enquiry could not be loaded.',
              )
            : const CircularProgressIndicator(),
      );
    }
    final open = lead.status.open;
    final gymName = currentOwnerProfile(ref)?.gymName ?? '';
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        Row(
          children: [
            IconButton(
              tooltip: 'Back',
              onPressed: () => context.pop(),
              icon: const Icon(Icons.arrow_back),
            ),
            Expanded(
              child: Text(lead.name, style: theme.textTheme.headlineSmall),
            ),
          ],
        ),
        // Who and where the enquiry stands.
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(lead.phone, style: theme.textTheme.bodyMedium),
            Chip(label: Text(lead.status.label)),
            Chip(label: Text(lead.source.label)),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        RoundActionRow(
          actions: [
            RoundAction(
              icon: Icons.call_outlined,
              label: 'Call',
              onTap: () => callMember(context, lead.phone),
            ),
            RoundAction(
              icon: Icons.chat_outlined,
              label: 'WhatsApp',
              onTap: () => whatsappMember(
                context,
                lead.phone,
                leadMessage(lead, gymName),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        // The one thing to know now: when to follow up.
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          decoration: BoxDecoration(
            color: lead.followUpDue ? AppPalette.amberWash : AppColors.glass,
            borderRadius: BorderRadius.circular(AppRadii.lg),
          ),
          child: Row(
            children: [
              Icon(
                Icons.event_repeat_outlined,
                color: lead.followUpDue ? AppPalette.amber : null,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      followUpLabel(lead, DateTime.now()),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: lead.followUpDue ? AppPalette.amber : null,
                      ),
                    ),
                    if (lead.trialStartDate != null &&
                        lead.trialEndDate != null)
                      Text(
                        'Trial ${shortDay(lead.trialStartDate!)} – '
                        '${shortDay(lead.trialEndDate!.subtract(const Duration(days: 1)))}'
                        '${lead.trialActive ? ' · on now' : ''}',
                        style: theme.textTheme.bodySmall,
                      ),
                    if (lead.referredBy != null)
                      Text(
                        'Referred by ${lead.referredBy!.name}',
                        style: theme.textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        if (lead.status == LeadStatus.joined && lead.convertedMember != null)
          FilledButton.icon(
            onPressed: gym == null
                ? null
                : () => context.push(
                    memberPath(scopeFor(gym, lead.convertedMember!.id)),
                  ),
            icon: const Icon(Icons.person_outline),
            label: Text('Open member ${lead.convertedMember!.memberCode}'),
          )
        else ...[
          FilledButton.icon(
            onPressed: _busy ? null : () => _convert(lead),
            icon: const Icon(Icons.how_to_reg_outlined),
            label: const Text('Convert to member'),
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              if (lead.status != LeadStatus.trial)
                OutlinedButton.icon(
                  onPressed: _busy
                      ? null
                      : () => _run((gymId) => _repo.startTrial(gymId, lead.id)),
                  icon: const Icon(Icons.fitness_center_outlined),
                  label: const Text('Start 3-day trial'),
                ),
              if (open)
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _followUp(lead),
                  icon: const Icon(Icons.event_repeat_outlined),
                  label: const Text('Next follow-up'),
                ),
              if (lead.status == LeadStatus.newLead)
                OutlinedButton.icon(
                  onPressed: _busy
                      ? null
                      : () => _run(
                          (gymId) => _repo.update(gymId, lead.id, {
                            'status': 'contacted',
                          }),
                        ),
                  icon: const Icon(Icons.check),
                  label: const Text('Mark contacted'),
                ),
              if (open)
                TextButton.icon(
                  onPressed: _busy ? null : () => _lost(lead),
                  icon: const Icon(Icons.close),
                  label: const Text('Mark lost'),
                ),
              if (lead.status == LeadStatus.lost)
                OutlinedButton(
                  onPressed: _busy
                      ? null
                      : () => _run(
                          (gymId) => _repo.update(gymId, lead.id, {
                            'status': 'contacted',
                          }),
                        ),
                  child: const Text('Reopen'),
                ),
            ],
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        Text('Notes', style: theme.textTheme.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: TextField(
                key: const ValueKey('lead-note'),
                controller: _note,
                enabled: !_busy,
                maxLength: 1000,
                decoration: const InputDecoration(
                  hintText: 'Called, will visit on Saturday',
                  counterText: '',
                ),
              ),
            ),
            IconButton(
              tooltip: 'Add note',
              onPressed: _busy
                  ? null
                  : () async {
                      final text = _note.text.trim();
                      if (text.isEmpty) return;
                      await _run(
                        (gymId) => _repo.addNote(gymId, lead.id, text),
                      );
                      _note.clear();
                    },
              icon: const Icon(Icons.send),
            ),
          ],
        ),
        for (final note in lead.notes)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.notes_outlined),
            title: Text(note.text),
            subtitle: Text(
              '${shortDay(note.createdAt)} · ${TimeOfDay.fromDateTime(note.createdAt).format(context)}',
            ),
          ),
        if (lead.notes.isEmpty)
          Text('No notes yet.', style: theme.textTheme.bodySmall),
      ],
    );
  }
}

String _iso(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';

class _LostReasonDialog extends StatefulWidget {
  const _LostReasonDialog();
  @override
  State<_LostReasonDialog> createState() => _LostReasonDialogState();
}

class _LostReasonDialogState extends State<_LostReasonDialog> {
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ConfirmDialog(
    title: 'Mark this enquiry as lost?',
    keepLabel: 'Keep open',
    confirmLabel: 'Mark lost',
    destructive: true,
    onKeep: () => Navigator.pop(context),
    onConfirm: () => Navigator.pop(context, _reason.text.trim()),
    content: TextField(
      key: const ValueKey('lost-reason'),
      controller: _reason,
      autofocus: true,
      maxLength: 300,
      decoration: const InputDecoration(
        labelText: 'Reason',
        hintText: 'Joined another gym, too expensive…',
      ),
    ),
  );
}
