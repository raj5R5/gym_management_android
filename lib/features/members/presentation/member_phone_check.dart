import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/design_tokens.dart';
import '../../gym_join/gym_join.dart';
import '../models/member_models.dart';
import '../providers/member_providers.dart';

/// Shows whether the member's phone is verified, and checks it with an SMS
/// code the member reads back to the owner.
class MemberPhoneCheck extends ConsumerWidget {
  const MemberPhoneCheck({
    super.key,
    required this.scope,
    required this.member,
  });
  final MemberScope scope;
  final MemberProfile member;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (member.phoneVerified) {
      return const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.verified_outlined, size: 16),
          SizedBox(width: 4),
          Text('Phone verified'),
        ],
      );
    }
    return ActionChip(
      key: const ValueKey('verify-member-phone'),
      avatar: const Icon(Icons.sms_outlined, size: 16),
      label: const Text('Verify phone'),
      onPressed: () => verifyMemberPhone(
        context,
        ref,
        scope,
        phone: member.phone,
        firstName: member.firstName,
      ),
    );
  }
}

/// Opens the verify-phone dialog; refreshes the member when it succeeds.
Future<void> verifyMemberPhone(
  BuildContext context,
  WidgetRef ref,
  MemberScope scope, {
  required String phone,
  required String firstName,
}) async {
  final verified = await showDialog<bool>(
    context: context,
    builder: (_) =>
        _VerifyDialog(scope: scope, phone: phone, firstName: firstName),
  );
  if (verified == true) {
    ref.invalidate(memberSummaryProvider(scope));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$firstName\'s phone is verified.')),
      );
    }
  }
}

class _VerifyDialog extends ConsumerStatefulWidget {
  const _VerifyDialog({
    required this.scope,
    required this.phone,
    required this.firstName,
  });
  final MemberScope scope;
  final String phone, firstName;
  @override
  ConsumerState<_VerifyDialog> createState() => _VerifyDialogState();
}

class _VerifyDialogState extends ConsumerState<_VerifyDialog> {
  final _code = TextEditingController();
  bool _sent = false, _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function(GymJoinRepository) action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action(ref.read(gymJoinRepositoryProvider));
    } on GymJoinFailure catch (failure) {
      if (mounted) setState(() => _error = failure.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _send() => _run((repository) async {
    final already = await repository.sendMemberPhoneCode(
      widget.scope.gymId,
      widget.scope.memberId,
    );
    if (!mounted) return;
    if (already) {
      Navigator.of(context).pop(true);
    } else {
      setState(() => _sent = true);
    }
  });

  Future<void> _confirm() => _run((repository) async {
    await repository.confirmMemberPhone(
      widget.scope.gymId,
      widget.scope.memberId,
      _code.text,
    );
    if (mounted) Navigator.of(context).pop(true);
  });

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Verify phone'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _sent
              ? 'We texted a code to ${widget.phone}. Ask ${widget.firstName} to read it out.'
              : 'We will text a code to ${widget.phone}. '
                    '${widget.firstName} reads it back to you to confirm the number is theirs.',
        ),
        if (_sent) ...[
          const SizedBox(height: AppSpacing.md),
          TextField(
            key: const ValueKey('member-phone-code'),
            controller: _code,
            enabled: !_busy,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(8),
            ],
            decoration: const InputDecoration(labelText: 'Code'),
            onSubmitted: (_) => _confirm(),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
      ],
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.of(context).pop(false),
        child: const Text('Later'),
      ),
      FilledButton(
        onPressed: _busy ? null : (_sent ? _confirm : _send),
        child: Text(_sent ? 'Verify' : 'Send code'),
      ),
    ],
  );
}
