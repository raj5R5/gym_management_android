import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/router/app_routes.dart';
import '../../app/theme/design_tokens.dart';
import '../../shared/contact/member_contact.dart';
import '../../shared/widgets/glass.dart';
import '../admin_dashboard/providers/dashboard_providers.dart';
import '../members/models/member_overview.dart';
import '../members/providers/member_overview_providers.dart';
import '../owner_profile/owner_profile.dart';
import 'leads.dart';
import '../../shared/widgets/card_reveal.dart';

const _months = [
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
String shortDay(DateTime day) => '${day.day} ${_months[day.month - 1]}';

/// "Follow up today", "Overdue by 2 days", "Follow up 21 Nov", or the outcome.
String followUpLabel(Lead lead, DateTime today) {
  if (lead.status == LeadStatus.joined) {
    return lead.convertedMember == null
        ? 'Joined'
        : 'Joined as ${lead.convertedMember!.memberCode}';
  }
  if (lead.status == LeadStatus.lost) {
    return lead.lostReason == null ? 'Lost' : 'Lost · ${lead.lostReason}';
  }
  final next = lead.nextFollowUpOn;
  if (next == null) return 'No follow-up set';
  // Compare calendar days only; server dates parse as local midnight, so
  // build both sides the same way (mixing UTC and local skews by hours).
  final base = DateTime(today.year, today.month, today.day);
  final days = DateTime(
    next.year,
    next.month,
    next.day,
  ).difference(base).inDays;
  if (days < 0) return 'Overdue by ${-days} ${-days == 1 ? 'day' : 'days'}';
  if (days == 0) return 'Follow up today';
  if (days == 1) return 'Follow up tomorrow';
  return 'Follow up ${shortDay(next)}';
}

/// WhatsApp draft for an enquiry, depending on where they are.
String leadMessage(Lead lead, String gymName) {
  final sign = gymName.isEmpty ? '' : '\n– $gymName';
  if (lead.status == LeadStatus.trial && lead.trialEndDate != null) {
    return 'Hi ${lead.firstName}, hope you are enjoying your free trial! '
        'It runs until ${shortDay(lead.trialEndDate!.subtract(const Duration(days: 1)))}. '
        'Would you like to join? We can help you pick a plan.$sign';
  }
  return 'Hi ${lead.firstName}, thanks for your interest in joining us. '
      'Come by for a free 3-day trial whenever it suits you. '
      'Reply here with any questions.$sign';
}

class LeadTile extends ConsumerWidget {
  const LeadTile({super.key, required this.lead, this.compact = false});
  final Lead lead;
  final bool compact;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final gymName = currentOwnerProfile(ref)?.gymName ?? '';
    final label = followUpLabel(lead, DateTime.now());
    final urgent = lead.followUpDue;
    return GlassCard(
      padding: EdgeInsets.zero,
      radius: AppRadii.lg,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.lg),
        onTap: () => pushFromCard(context, '${AppRoutes.leads}/${lead.id}'),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              CircleAvatar(
                radius: compact ? 18 : 20,
                backgroundColor: AppPalette.graphite,
                child: Text(
                  lead.firstName.characters.first.toUpperCase(),
                  style: theme.textTheme.titleSmall,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      lead.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      compact
                          ? label
                          : '${lead.status.label} · ${lead.source.label} · $label',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: urgent ? AppPalette.amber : null,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Call ${lead.firstName}',
                onPressed: () => callMember(context, lead.phone),
                icon: const Icon(Icons.call_outlined, size: 20),
              ),
              IconButton(
                tooltip: 'WhatsApp ${lead.firstName}',
                onPressed: () => whatsappMember(
                  context,
                  lead.phone,
                  leadMessage(lead, gymName),
                ),
                icon: const Icon(Icons.chat_outlined, size: 20),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Add an enquiry: who, how they heard about us, and when to follow up.
class AddLeadSheet extends ConsumerStatefulWidget {
  const AddLeadSheet({super.key});
  @override
  ConsumerState<AddLeadSheet> createState() => _AddLeadSheetState();
}

class _AddLeadSheetState extends ConsumerState<AddLeadSheet> {
  final _form = GlobalKey<FormState>();
  final _first = TextEditingController();
  final _last = TextEditingController();
  final _phone = TextEditingController();
  final _note = TextEditingController();
  LeadSource _source = LeadSource.walkIn;
  MemberOverviewRow? _referrer;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final controller in [_first, _last, _phone, _note]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _pickReferrer() async {
    final picked = await showDialog<MemberOverviewRow>(
      context: context,
      builder: (_) => const MemberPickerDialog(title: 'Referred by'),
    );
    if (picked != null) setState(() => _referrer = picked);
  }

  Future<void> _save() async {
    final gym = ref.read(adminGymProvider);
    if (gym == null || _saving || !(_form.currentState?.validate() ?? false)) {
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final lead = await ref
          .read(leadRepositoryProvider)
          .create(
            gym.gymId,
            firstName: _first.text.trim(),
            lastName: _last.text.trim().isEmpty ? null : _last.text.trim(),
            phone: _phone.text.trim(),
            source: _referrer == null ? _source : LeadSource.referral,
            referredByMemberId: _referrer?.member.id,
            note: _note.text.trim().isEmpty ? null : _note.text.trim(),
          );
      if (mounted) Navigator.pop(context, lead.id);
    } on LeadFailure catch (failure) {
      if (!mounted) return;
      if (failure.existingLeadId case final existing?) {
        Navigator.pop(context, existing);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Already an open enquiry for this number. Opening it.',
            ),
          ),
        );
        return;
      }
      setState(() => _error = failure.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        MediaQuery.viewInsetsOf(context).bottom + AppSpacing.lg,
      ),
      child: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('New enquiry', style: theme.textTheme.titleLarge),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      key: const ValueKey('lead-first'),
                      controller: _first,
                      enabled: !_saving,
                      maxLength: 80,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'First name',
                        counterText: '',
                      ),
                      validator: (value) =>
                          (value ?? '').trim().isEmpty ? 'Required' : null,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: TextFormField(
                      controller: _last,
                      enabled: !_saving,
                      maxLength: 80,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Last name',
                        counterText: '',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                key: const ValueKey('lead-phone'),
                controller: _phone,
                enabled: !_saving,
                keyboardType: TextInputType.phone,
                maxLength: 25,
                decoration: const InputDecoration(
                  labelText: 'Phone',
                  prefixIcon: Icon(Icons.phone_outlined),
                  counterText: '',
                ),
                validator: (value) {
                  final digits = (value ?? '').replaceAll(RegExp(r'\D'), '');
                  return digits.length >= 7 && digits.length <= 15
                      ? null
                      : 'Enter a phone number';
                },
              ),
              const SizedBox(height: AppSpacing.md),
              DropdownButtonFormField<LeadSource>(
                initialValue: _source,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'How did they hear about us?',
                ),
                items: [
                  for (final source in LeadSource.values)
                    DropdownMenuItem(value: source, child: Text(source.label)),
                ],
                onChanged: _saving || _referrer != null
                    ? null
                    : (value) => setState(() => _source = value!),
              ),
              const SizedBox(height: AppSpacing.sm),
              OutlinedButton.icon(
                onPressed: _saving ? null : _pickReferrer,
                icon: const Icon(Icons.group_add_outlined),
                label: Text(
                  _referrer == null
                      ? 'Referred by a member? (optional)'
                      : 'Referred by ${_referrer!.member.name}',
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _note,
                enabled: !_saving,
                maxLength: 1000,
                decoration: const InputDecoration(
                  labelText: 'Note (optional)',
                  hintText: 'Wants evening batch, interested in quarterly',
                  counterText: '',
                ),
              ),
              Text(
                'A follow-up is set for today so it shows in your to-do list.',
                style: theme.textTheme.bodySmall,
              ),
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
              ],
              const SizedBox(height: AppSpacing.md),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(_saving ? 'Saving…' : 'Save enquiry'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Searches members by name, code or phone; pops the chosen row.
class MemberPickerDialog extends ConsumerStatefulWidget {
  const MemberPickerDialog({super.key, required this.title});
  final String title;
  @override
  ConsumerState<MemberPickerDialog> createState() => _MemberPickerState();
}

class _MemberPickerState extends ConsumerState<MemberPickerDialog> {
  String _query = '';
  @override
  Widget build(BuildContext context) {
    final results = _query.length < 2
        ? null
        : ref.watch(
            memberOverviewProvider(
              MemberOverviewQuery(search: _query, limit: 8),
            ),
          );
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Search members',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (value) => setState(() => _query = value.trim()),
            ),
            const SizedBox(height: AppSpacing.sm),
            if (results?.asData?.value case final page?)
              for (final row in page.rows)
                ListTile(
                  dense: true,
                  title: Text(row.member.name),
                  subtitle: Text(row.member.memberCode),
                  onTap: () => Navigator.pop(context, row),
                )
            else if (results?.isLoading ?? false)
              const LinearProgressIndicator(minHeight: 2),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
