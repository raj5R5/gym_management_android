import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/design_tokens.dart';
import '../../shared/contact/member_contact.dart';
import '../auth/data/auth_failure.dart';
import '../auth/models/owner_registration.dart';
import '../auth/providers/auth_providers.dart';
import '../members/models/member_models.dart';
import '../owner_profile/owner_profile.dart';
import 'member_home.dart';
import '../../shared/widgets/confirm_dialog.dart';
import '../../shared/widgets/page_section.dart';

/// Where a member's app login stands, as the owner sees it.
class MemberAccessState {
  MemberAccessState.fromJson(Map<String, dynamic> json)
    : provisioned = json['provisioned'] as bool,
      email = json['email'] as String?,
      accessActive = (json['gymAccess'] as Map?)?['status'] == 'active',
      activated = json['activated'] as bool;
  final bool provisioned, accessActive, activated;
  final String? email;
}

/// A one-time code to hand to the member. Never stored on the device.
typedef ActivationCode = ({String code, DateTime expiresAt, String email});

class MemberAccessRepository {
  MemberAccessRepository(this._client);
  final Dio _client;

  String _path(String gymId, String memberId) =>
      'gyms/$gymId/members/$memberId/account';

  Future<Map<String, dynamic>> _call(
    Future<Response<dynamic>> Function() call,
  ) async {
    try {
      final body = (await call()).data;
      if (body is! Map<String, dynamic> || body['success'] != true) {
        throw const MemberAppFailure('Unexpected response.');
      }
      return body['data'] as Map<String, dynamic>;
    } on DioException catch (error) {
      final data = error.response?.data;
      final failure = data is Map ? data['error'] : null;
      final code = failure is Map ? failure['code'] : null;
      throw MemberAppFailure(switch (code) {
        'MEMBER_ACCOUNT_IDENTITY_CONFLICT' =>
          'That email already belongs to another account. Use a different email.',
        'MEMBER_ACCOUNT_ALREADY_PROVISIONED' =>
          'This member already has app access.',
        'MEMBER_ACCOUNT_ALREADY_ACTIVATED' =>
          'This member has already set a password.',
        'MEMBER_ACCOUNT_NOT_PROVISIONED' =>
          'This member does not have app access yet.',
        'FORBIDDEN' => 'Only active, adult members can get app access.',
        'VALIDATION_ERROR' => 'Check the email address.',
        _ => AuthFailure.fromDio(error).message,
      });
    } on TypeError {
      throw const MemberAppFailure('The server returned unexpected data.');
    }
  }

  ActivationCode _code(Map<String, dynamic> data) => (
    code: data['activationToken'] as String,
    expiresAt: DateTime.parse(data['activationExpiresAt'] as String).toLocal(),
    email: data['email'] as String,
  );

  Future<MemberAccessState> get(String gymId, String memberId) async =>
      MemberAccessState.fromJson(
        await _call(() => _client.get<dynamic>(_path(gymId, memberId))),
      );

  /// Null when the email already had a password (no code needed).
  Future<ActivationCode?> give(
    String gymId,
    String memberId, {
    required String email,
    required String displayName,
  }) async {
    final data = await _call(
      () => _client.post<dynamic>(
        _path(gymId, memberId),
        data: {'email': email, 'displayName': displayName},
      ),
    );
    return data['activationToken'] is String ? _code(data) : null;
  }

  Future<ActivationCode> newCode(String gymId, String memberId) async => _code(
    await _call(
      () => _client.post<dynamic>('${_path(gymId, memberId)}/reissue'),
    ),
  );

  Future<void> turnOff(String gymId, String memberId) =>
      _call(() => _client.post<dynamic>('${_path(gymId, memberId)}/revoke'));
}

final memberAccessRepositoryProvider = Provider<MemberAccessRepository>(
  (ref) => MemberAccessRepository(ref.watch(authenticatedApiClientProvider)),
);

final memberAccessProvider = FutureProvider.autoDispose
    .family<MemberAccessState, ({String gymId, String memberId})>(
      (ref, key) => ref
          .watch(memberAccessRepositoryProvider)
          .get(key.gymId, key.memberId),
      retry: (_, _) => null,
    );

/// The WhatsApp message carrying the code; the member pastes it whole.
String activationMessage({
  required String firstName,
  required String gymName,
  required ActivationCode code,
  required String expiry,
}) =>
    'Hi $firstName, your ${gymName.isEmpty ? 'gym' : gymName} app is ready.\n\n'
    '1. Install the MuscleDesk app.\n'
    '2. On the sign-in screen tap "Activate with gym code".\n'
    '3. Copy this whole message, tap Paste, and choose a password.\n\n'
    'Your email: ${code.email}\n'
    'Code: ${code.code}\n\n'
    'The code works once, until $expiry. Do not share it.';

/// Member profile card: give, resend or turn off the member's app login.
class MemberAppAccessCard extends ConsumerStatefulWidget {
  const MemberAppAccessCard({
    super.key,
    required this.gymId,
    required this.member,
  });
  final String gymId;
  final MemberProfile member;
  @override
  ConsumerState<MemberAppAccessCard> createState() =>
      _MemberAppAccessCardState();
}

class _MemberAppAccessCardState extends ConsumerState<MemberAppAccessCard> {
  bool _busy = false;

  ({String gymId, String memberId}) get _key =>
      (gymId: widget.gymId, memberId: widget.member.id);

  Future<void> _run(Future<ActivationCode?> Function() action) async {
    if (_busy) return;
    final container = ProviderScope.containerOf(context, listen: false);
    setState(() => _busy = true);
    try {
      final code = await action();
      container.invalidate(memberAccessProvider(_key));
      if (code != null && mounted) await _showCode(code);
    } on MemberAppFailure catch (failure) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(failure.message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _give() async {
    final email = await showDialog<String>(
      context: context,
      builder: (_) => _EmailDialog(name: widget.member.firstName),
    );
    if (email == null) return;
    await _run(
      () => ref
          .read(memberAccessRepositoryProvider)
          .give(
            widget.gymId,
            widget.member.id,
            email: email,
            displayName: widget.member.name,
          ),
    );
  }

  Future<void> _turnOff() async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Turn off app access for ${widget.member.firstName}?',
      message: 'Their membership and payments stay as they are.',
      keepLabel: 'Keep access',
      confirmLabel: 'Turn off access',
      destructive: true,
    );
    if (confirmed != true) return;
    await _run(() async {
      await ref
          .read(memberAccessRepositoryProvider)
          .turnOff(widget.gymId, widget.member.id);
      return null;
    });
  }

  Future<void> _showCode(ActivationCode code) {
    final localizations = MaterialLocalizations.of(context);
    final expiry =
        '${localizations.formatMediumDate(code.expiresAt)}, '
        '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(code.expiresAt))}';
    final message = activationMessage(
      firstName: widget.member.firstName,
      gymName: ref.read(ownerProfileProvider).value?.gymName ?? '',
      code: code,
      expiry: expiry,
    );
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Send the code'),
        content: Text(
          'Send this to ${widget.member.firstName} now. It works once, until '
          '$expiry, and is not shown again. You can always make a new one.',
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: message));
              if (context.mounted) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('Message copied')));
              }
            },
            child: const Text('Copy'),
          ),
          FilledButton.icon(
            onPressed: () {
              whatsappMember(context, widget.member.phone, message);
              Navigator.pop(context);
            },
            icon: const Icon(Icons.chat_outlined),
            label: const Text('WhatsApp'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = ref.watch(memberAccessProvider(_key));
    final access = state.asData?.value;
    final repository = ref.read(memberAccessRepositoryProvider);
    final (String status, List<Widget> actions) = switch (access) {
      null => (
        state.hasError
            ? (state.error is MemberAppFailure
                  ? (state.error! as MemberAppFailure).message
                  : 'Status could not be loaded.')
            : 'Checking…',
        <Widget>[
          if (state.hasError)
            TextButton(
              onPressed: () => ref.invalidate(memberAccessProvider(_key)),
              child: const Text('Retry'),
            ),
        ],
      ),
      MemberAccessState(provisioned: false) => (
        'Let ${widget.member.firstName} see their membership, dues, visits, '
            'PT sessions and receipts, and check in with a QR code.',
        <Widget>[
          OutlinedButton.icon(
            onPressed: _busy ? null : _give,
            icon: const Icon(Icons.phone_iphone_outlined),
            label: const Text('Give app access'),
          ),
        ],
      ),
      MemberAccessState(accessActive: false) => (
        'App access is turned off.',
        const <Widget>[],
      ),
      MemberAccessState(activated: false) => (
        'Waiting for ${widget.member.firstName} to activate with the code'
            '${access.email == null ? '' : ' (${access.email})'}.',
        <Widget>[
          OutlinedButton.icon(
            onPressed: _busy
                ? null
                : () => _run(
                    () => repository.newCode(widget.gymId, widget.member.id),
                  ),
            icon: const Icon(Icons.refresh),
            label: const Text('Send a new code'),
          ),
          TextButton(
            onPressed: _busy ? null : _turnOff,
            child: const Text('Turn off'),
          ),
        ],
      ),
      _ => (
        'App access on${access.email == null ? '' : ' · ${access.email}'}.',
        <Widget>[
          TextButton(
            onPressed: _busy ? null : _turnOff,
            child: const Text('Turn off'),
          ),
        ],
      ),
    };
    return PlainBlock(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Member app', style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.xs),
          Text(status, style: theme.textTheme.bodySmall),
          if (actions.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: actions,
            ),
          ],
        ],
      ),
    );
  }
}

class _EmailDialog extends StatefulWidget {
  const _EmailDialog({required this.name});
  final String name;
  @override
  State<_EmailDialog> createState() => _EmailDialogState();
}

class _EmailDialogState extends State<_EmailDialog> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  void _submit() {
    if (_form.currentState?.validate() ?? false) {
      // Phone keyboards often capitalise the first letter; emails are case-insensitive.
      Navigator.pop(context, _email.text.trim().toLowerCase());
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('App access for ${widget.name}'),
    content: Form(
      key: _form,
      child: TextFormField(
        key: const ValueKey('member-access-email'),
        controller: _email,
        autofocus: true,
        keyboardType: TextInputType.emailAddress,
        autocorrect: false,
        enableSuggestions: false,
        validator: ownerEmailError,
        onFieldSubmitted: (_) => _submit(),
        decoration: const InputDecoration(
          labelText: 'Their email',
          helperText: 'They sign in with this email.',
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _submit, child: const Text('Create code')),
    ],
  );
}
