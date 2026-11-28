import '../../../shared/widgets/icon_label.dart';
import '../providers/member_overview_providers.dart';
import '../photos/member_photo_widgets.dart';
import '../photos/member_photo_providers.dart';
import '../photos/member_photo_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_routes.dart';
import '../../../app/navigation/form_navigation_guard.dart';
import '../../../app/theme/design_tokens.dart';
import '../../../core/config/app_config.dart';
import '../../../shared/formatting/inr.dart';
import '../../../shared/widgets/soft_panel.dart';
import '../../admin_dashboard/providers/dashboard_providers.dart';
import '../data/member_onboarding_service.dart';
import '../data/onboarding_failure.dart';
import '../models/pending_onboarding.dart';
import '../models/onboarding_wizard_state.dart';
import '../models/onboarding_correction.dart';
import '../../memberships/data/billing_failure.dart';
import '../../memberships/providers/plan_providers.dart';
import '../providers/member_providers.dart';
import 'member_phone_check.dart';
import '../providers/onboarding_providers.dart';

/// Presentation only. The existing service owns storage, exact replay and scope
/// checks. This gate freezes one validated fresh operation and delegates every
/// write to the service. Only explicit acknowledgement clears confirmation.
class OnboardingRecoveryGate extends ConsumerStatefulWidget {
  const OnboardingRecoveryGate({
    super.key,
    required this.scope,
    required this.service,
    required this.freshDraft,
    this.onRegistered,
  });
  final OnboardingScope scope;

  /// Called once with the new member's id when registration is confirmed.
  final ValueChanged<String>? onRegistered;
  final MemberOnboardingService service;
  final Widget Function(
    ValueChanged<OnboardingWizardState> confirm,
    OnboardingWizardState? initialDraft,
    OnboardingCorrection? correction,
  )
  freshDraft;

  @override
  ConsumerState<OnboardingRecoveryGate> createState() => _RecoveryGateState();
}

class _RecoveryGateState extends ConsumerState<OnboardingRecoveryGate> {
  bool _registeredReported = false;
  bool _busy = true;
  bool _restored = false;
  bool _verified = false;
  PendingOnboardingOperation? _operation;
  // Retain the exact prepared request/key if its initial storage write fails.
  // Once a durable record is observed, all retries use service.recover instead.
  PendingOnboardingOperation? _prepared;
  bool _stored = false;
  OnboardingCorrection? _correction;
  OnboardingWizardState? _correctionDraft;
  PendingOnboardingOperation? _replacement;
  bool _editingCorrection = false;
  String? _error;
  String? _feedback;
  OnboardingDiagnostics? _diagnostics;
  String _loadingMessage = 'Checking saved registration. Please wait.';

  @override
  void initState() {
    super.initState();
    _restore();
  }

  bool get _current {
    if (!mounted) return false;
    final gym = ref.read(adminGymProvider);
    final config = ref.read(appConfigProvider);
    return gym?.userId == widget.scope.userId &&
        gym?.gymId == widget.scope.gymId &&
        config.environment == widget.scope.environment &&
        config.apiBaseUrl.toString() == widget.scope.apiBaseUrl &&
        identical(ref.read(memberOnboardingServiceProvider), widget.service);
  }

  String _message(Object error) => error is MemberPhotoFailure
      ? '${error.message} The registration result remains saved.'
      : error is OnboardingFailure
      ? error.message
      : 'Saved registration could not be verified. It has not been discarded.';

  void _announceRecheck(String message) {
    // The owner may still be scrolled to the button after an unchanged record
    // is restored. Also announce the outcome where it is immediately visible.
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(SnackBar(content: Text(message)));
  }

  String _recheckOutcome(
    PendingOnboardingOperation? operation, {
    required bool stored,
  }) {
    if (!stored && operation != null && _replacement != null) {
      return 'Latest recheck: the saved registration could not be found. Your corrected details are retained, but another registration is blocked until the saved operation can be verified.';
    }
    if (!stored && operation != null) {
      return 'Latest recheck: no saved record was found. The original prepared request remains in memory. Retry saves the same request and key before sending anything.';
    }
    return switch (operation?.status) {
      PendingOnboardingStatus.rejected =>
        'Latest recheck: the saved request is still rejected. No request was sent. Review the available recovery action below.',
      PendingOnboardingStatus.reconciliationRequired =>
        'Latest recheck: this registration still needs verification. No request was sent. Return to Members and contact support.',
      PendingOnboardingStatus.confirmed =>
        'Latest recheck: the saved confirmation was verified. No request was sent. Review and acknowledge the registration.',
      null => 'Latest recheck: no saved operation was found.',
      _ =>
        'Latest recheck: the saved operation was read successfully. No request was sent. Use Retry saved registration to safely retry the same saved details.',
    };
  }

  Future<void> _restore({bool recheck = false}) async {
    try {
      final operation = await widget.service.restore(widget.scope);
      if (!_current) return;
      setState(() {
        if (operation != null) _prepared = null;
        if (operation != null &&
            _replacement != null &&
            (operation.sameSubmission(_replacement!) ||
                !operation.sameSubmission(_correction!.operation) ||
                operation.revision != _correction!.operation.revision)) {
          _replacement = null;
          _correction = null;
          _correctionDraft = null;
        }
        _operation =
            operation ??
            _prepared ??
            (_replacement != null ? _correction?.operation : null);
        _stored = operation != null;
        _restored = true;
        _verified = true;
        _error = null;
        _diagnostics = null;
        if (recheck) _feedback = _recheckOutcome(_operation, stored: _stored);
        _busy = false;
      });
      // A restored confirmation can follow a previously ambiguous submission.
      // Refresh totals even when no new POST was needed to resolve that outcome.
      if (operation?.result != null) ref.invalidate(dashboardProvider);
      if (recheck) _announceRecheck(_feedback!);
    } catch (error) {
      if (!_current) return;
      setState(() {
        _verified = false;
        _error = _message(error);
        _diagnostics = error is OnboardingFailure ? error.diagnostics : null;
        if (recheck) {
          _feedback =
              'Latest recheck failed. The saved operation has not been changed or discarded; registration remains blocked.';
        }
        _busy = false;
      });
      if (recheck) _announceRecheck('Recheck failed. ${_message(error)}');
    }
  }

  void _reload() {
    if (_busy || !_current) return;
    setState(() {
      _busy = true;
      _feedback = null;
      _diagnostics = null;
      _loadingMessage =
          'Rechecking saved registration in secure storage. No request is being sent.';
    });
    _restore(recheck: true);
  }

  Future<void> _beginCorrection() async {
    final expected = _operation;
    if (_busy ||
        !_current ||
        !_stored ||
        !_verified ||
        expected == null ||
        _replacement != null) {
      return;
    }
    setState(() {
      _busy = true;
      _loadingMessage =
          'Checking whether these details can be corrected. Please wait.';
    });
    try {
      final actual = await widget.service.restore(widget.scope);
      if (!_current) return;
      if (actual == null ||
          !actual.sameSubmission(expected) ||
          actual.revision != expected.revision) {
        throw const OnboardingFailure(OnboardingFailureKind.pendingOperation);
      }
      final correction = OnboardingCorrection.supported(actual);
      if (correction == null) {
        throw const OnboardingFailure(OnboardingFailureKind.pendingOperation);
      }
      final membership = actual.request.toJson()['membership'];
      final gym = ref.read(adminGymProvider)!;
      final planId = membership?['planId'] as String?;
      // Read current terms through the existing scoped provider; never invent
      // snapshots from an ID or silently replay stale pricing in an editable form.
      final plan =
          planId == null ||
              correction.code == OnboardingBackendCode.planNotFound
          ? null
          : await ref.read(
              planDetailProvider((gym: gym, planId: planId)).future,
            );
      if (!_current) return;
      setState(() {
        _operation = actual;
        _correction = correction;
        _correctionDraft = correction.draft(
          plan?.gymId == widget.scope.gymId && plan?.status == 'active'
              ? plan
              : null,
        );
        _editingCorrection = true;
        _busy = false;
        _error = null;
      });
    } catch (error) {
      if (!_current) return;
      setState(() {
        _busy = false;
        _verified = false;
        _error = error is BillingFailure
            ? 'The current plan could not be verified. Recheck the saved registration before correcting it.'
            : _message(error);
      });
    }
  }

  Future<void> _retryCorrection() async {
    final correction = _correction;
    final replacement = _replacement;
    if (_busy || !_current || correction == null || replacement == null) return;
    setState(() {
      _busy = true;
      _error = null;
      _feedback = null;
      _diagnostics = null;
      _loadingMessage = 'Saving the corrected registration. Please wait.';
    });
    await _perform(() async {
      // Reuse this replacement/key after any storage failure. The store decides
      // whether the original is still eligible; never delete the old record.
      await ref
          .read(memberPhotoServiceProvider)
          .bindRegistration(widget.scope, replacement.idempotencyKey);
      if (!_current) return;
      await widget.service.correct(correction.operation, replacement);
      if (!_current) return;
      await _submitPreparedWithPhoto(replacement);
    });
  }

  Future<void> _submitPreparedWithPhoto(
    PendingOnboardingOperation operation,
  ) async {
    await ref
        .read(memberPhotoServiceProvider)
        .bindRegistration(widget.scope, operation.idempotencyKey);
    if (_current) await widget.service.submit(operation);
  }

  Future<void> _submit(OnboardingWizardState draft) async {
    if (!_restored ||
        _busy ||
        (_operation != null && !_editingCorrection) ||
        _error != null ||
        !_current ||
        !draft.canConfirm(gymId: widget.scope.gymId) ||
        (_editingCorrection && _correction?.issue(draft) != null)) {
      return;
    }
    final PendingOnboardingOperation prepared;
    try {
      prepared = PendingOnboardingOperation.create(
        scope: widget.scope,
        request: draft.toRequest(
          gymId: widget.scope.gymId,
          paidAt: DateTime.now().toUtc(),
        ),
      );
    } catch (error) {
      setState(() => _error = _message(error));
      return;
    }
    // Synchronous lock before the first await: repeated taps cannot generate
    // another request/key. The store still guards against another active record.
    if (_editingCorrection) {
      _replacement = prepared;
      _correctionDraft = draft;
      _editingCorrection = false;
      await _retryCorrection();
      return;
    }
    setState(() {
      _prepared = prepared;
      _operation = prepared;
      _stored = false;
      _busy = true;
      _feedback = null;
      _diagnostics = null;
      _loadingMessage = 'Submitting registration. Please wait.';
    });
    await _perform(() async {
      await _submitPreparedWithPhoto(prepared);
    });
  }

  Future<void> _act({required bool acknowledge}) async {
    final operation = _operation;
    if (_busy || operation == null || !_current) return;
    setState(() {
      _busy = true;
      _error = null;
      _feedback = null;
      _diagnostics = null;
      _loadingMessage = acknowledge
          ? 'Acknowledging saved registration. Please wait.'
          : 'Retrying saved registration with its original request and key. Please wait.';
    });
    await _perform(() async {
      if (acknowledge) {
        if (operation.result != null) {
          await ref
              .read(memberPhotoServiceProvider)
              .bindConfirmed(
                widget.scope,
                operation.idempotencyKey,
                operation.result!.member.id,
              );
          if (!_current) return;
        }
        await widget.service.acknowledge(operation);
      } else if (!_stored && _prepared != null) {
        // A failed write may have saved data. Recheck before selecting the
        // retry path; never turn an unknown storage outcome into a new key.
        final prepared = _prepared!;
        final actual = await widget.service.restore(widget.scope);
        if (!_current) return;
        if (actual == null) {
          await _submitPreparedWithPhoto(prepared);
        } else {
          if (!actual.sameSubmission(prepared) ||
              actual.status == PendingOnboardingStatus.rejected ||
              actual.status == PendingOnboardingStatus.reconciliationRequired) {
            throw const OnboardingFailure(
              OnboardingFailureKind.pendingOperation,
            );
          }
          await widget.service.recover(widget.scope);
        }
      } else {
        await widget.service.recover(widget.scope);
      }
    });
  }

  Future<void> _perform(Future<void> Function() action) async {
    String? failure;
    OnboardingDiagnostics? diagnostics;
    try {
      await action();
    } catch (error) {
      failure = _message(error);
      diagnostics = error is OnboardingFailure ? error.diagnostics : null;
    }
    if (!_current) return;
    try {
      // Recover/acknowledge may have saved state before throwing. Only the
      // authoritative stored operation decides which screen is safe to display.
      final actual = await widget.service.restore(widget.scope);
      if (!_current) return;
      setState(() {
        if (actual != null) _prepared = null;
        if (actual != null &&
            _replacement != null &&
            (actual.sameSubmission(_replacement!) ||
                !actual.sameSubmission(_correction!.operation) ||
                actual.revision != _correction!.operation.revision)) {
          _replacement = null;
          _correction = null;
          _correctionDraft = null;
        }
        _operation =
            actual ??
            _prepared ??
            (_replacement != null ? _correction?.operation : null);
        _stored = actual != null;
        _restored = true;
        _verified = true;
        _busy = false;
        // An ambiguous acknowledgement failure must not unlock a fresh draft
        // until the owner explicitly rechecks storage successfully.
        _error = failure;
        _diagnostics = diagnostics;
        _feedback = failure != null
            ? 'Latest action failed. Follow the saved operation\'s recovery instructions; do not start a duplicate registration.'
            : actual?.result != null
            ? 'Latest action succeeded. Registration is confirmed and safely saved.'
            : 'Latest action completed. The saved state was verified.';
      });
      if (actual?.result case final result?) {
        if (!_registeredReported) {
          _registeredReported = true;
          widget.onRegistered?.call(result.member.id);
        }
        ref.invalidate(membersProvider);
        ref.invalidate(memberOverviewProvider);
        ref.invalidate(dashboardProvider);
      }
    } catch (error) {
      if (!_current) return;
      setState(() {
        _verified = false;
        _error = [?failure, _message(error)].join(' ');
        _diagnostics =
            diagnostics ??
            (error is OnboardingFailure ? error.diagnostics : null);
        _feedback =
            'Latest action could not be verified in secure storage. The saved operation remains blocked and has not been discarded.';
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => FormNavigationGuard(
    path: '${AppRoutes.members}/new',
    dirty: () => false,
    busy: () => _busy,
    // The wizard owns step Back; the recovery view blocks Back while busy.
    protectBack: false,
    child: _content(context),
  );

  Widget _content(BuildContext context) {
    if (_restored &&
        !_busy &&
        _error == null &&
        (_operation == null || _editingCorrection)) {
      return widget.freshDraft(_submit, _correctionDraft, _correction);
    }
    final operation = _operation;
    final result = operation?.result;
    final blocked =
        operation?.status == PendingOnboardingStatus.reconciliationRequired ||
        operation?.status == PendingOnboardingStatus.rejected;
    final correctable =
        _stored &&
        _verified &&
        _replacement == null &&
        operation != null &&
        OnboardingCorrection.supported(operation) != null;
    final savedState = switch (operation?.status) {
      PendingOnboardingStatus.pending =>
        'Previous registration · Outcome not yet verified',
      PendingOnboardingStatus.prepared => 'Saved — ready to retry',
      PendingOnboardingStatus.uncertain =>
        'Not yet confirmed — retry the saved registration',
      PendingOnboardingStatus.rejected =>
        correctable
            ? 'Not completed — ready to correct'
            : 'Rejected — verification required',
      PendingOnboardingStatus.reconciliationRequired =>
        'Outcome not yet verified — conflict needs verification',
      PendingOnboardingStatus.confirmed =>
        'Confirmed · Awaiting acknowledgement',
      null => null,
    };
    return PopScope(
      canPop: !_busy,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: AppSurfaces.of(context).canvasGradient,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: AppSpacing.contentWidth,
              ),
              child: SoftPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      result != null
                          ? 'Registration confirmed'
                          : correctable
                          ? 'Registration needs a correction'
                          : 'Saved registration',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    if (_busy) ...[
                      const Center(child: CircularProgressIndicator()),
                      const SizedBox(height: AppSpacing.lg),
                      Semantics(liveRegion: true, child: Text(_loadingMessage)),
                    ] else ...[
                      if (_feedback != null) ...[
                        Semantics(
                          liveRegion: true,
                          child: Text(
                            _feedback!,
                            key: const ValueKey('recoveryFeedback'),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                      ],
                      if (_diagnostics?.summary.isNotEmpty == true) ...[
                        Text('Latest API response: ${_diagnostics!.summary}'),
                        const SizedBox(height: AppSpacing.lg),
                      ],
                      if (_error != null) ...[
                        Semantics(liveRegion: true, child: Text(_error!)),
                        const SizedBox(height: AppSpacing.lg),
                      ],
                      if (savedState != null) ...[
                        Text(
                          'Saved state: $savedState',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: AppSpacing.lg),
                      ],
                      if (operation != null)
                        RegistrationPhotoRecovery(
                          scope: widget.scope,
                          operationKey: operation.idempotencyKey,
                          memberId: result?.member.id,
                        ),
                      if (result != null) ...[
                        Text(
                          '${result.member.firstName} ${result.member.lastName}',
                        ),
                        IconLabel(
                          'Member code: ${result.member.memberCode}',
                          icon: Icons.badge_outlined,
                        ),
                        Text('Member status: ${result.member.status}'),
                        const SizedBox(height: AppSpacing.lg),
                        if (result.subscription case final subscription?) ...[
                          IconLabel(
                            'Plan: ${subscription.planName}',
                            icon: Icons.card_membership_outlined,
                          ),
                          IconLabel(
                            'Membership status: ${subscription.status}',
                            icon: Icons.card_membership_outlined,
                          ),
                          IconLabel(
                            'Start date: ${subscription.startDate}',
                            icon: Icons.event_available_outlined,
                          ),
                          IconLabel(
                            'End date: ${subscription.endDate} (exclusive)',
                            icon: Icons.event_busy_outlined,
                          ),
                        ] else
                          const Text(
                            'Member registration only · No membership',
                          ),
                        IconLabel(
                          'Plan price: ${formatInrPaise(result.billing.planPricePaise)}',
                          icon: Icons.sell_outlined,
                        ),
                        IconLabel(
                          'Amount received: ${formatInrPaise(result.billing.amountReceivedPaise)}',
                          icon: Icons.payments_outlined,
                        ),
                        IconLabel(
                          'Outstanding balance: ${formatInrPaise(result.billing.outstandingBalancePaise)}',
                          icon: Icons.account_balance_wallet_outlined,
                        ),
                        if (result.payment case final payment?) ...[
                          IconLabel(
                            'Payment method: ${payment.method.label}',
                            icon: Icons.account_balance_wallet_outlined,
                          ),
                          if (payment.reference != null)
                            IconLabel(
                              'Reference: ${payment.reference}',
                              icon: Icons.receipt_long_outlined,
                            ),
                        ] else
                          const Text('No initial payment was recorded.'),
                        const SizedBox(height: AppSpacing.lg),
                        const Text('Saved. Tap Done to add the next member.'),
                        const SizedBox(height: AppSpacing.sm),
                        // Optional: the member reads back an SMS code now, or later from their page.
                        OutlinedButton.icon(
                          key: const ValueKey('verify-phone-now'),
                          onPressed: () => verifyMemberPhone(
                            context,
                            ref,
                            (
                              userId: widget.scope.userId,
                              gymId: widget.scope.gymId,
                              memberId: result.member.id,
                            ),
                            phone:
                                operation!.request.toJson()['member']['phone']
                                    as String,
                            firstName: result.member.firstName,
                          ),
                          icon: const Icon(Icons.sms_outlined),
                          label: const Text('Verify phone now'),
                        ),
                        TextButton(
                          onPressed: () async {
                            if (!_current || _busy) return;
                            try {
                              await ref
                                  .read(memberPhotoServiceProvider)
                                  .bindConfirmed(
                                    widget.scope,
                                    operation!.idempotencyKey,
                                    result.member.id,
                                  );
                            } catch (error) {
                              if (_current) _announceRecheck(_message(error));
                              return;
                            }
                            if (!context.mounted || !_current) return;
                            context.push(
                              '${AppRoutes.members}/${result.member.id}?gymId=${Uri.encodeQueryComponent(widget.scope.gymId)}',
                            );
                          },
                          child: const Text('View member details'),
                        ),
                        FilledButton(
                          onPressed: () => _act(acknowledge: true),
                          child: const Text('Done, add next member'),
                        ),
                      ] else if (operation != null) ...[
                        if (blocked) ...[
                          if (operation.attempts.lastOrNull?.rejection
                              case final rejection?)
                            Text(
                              'Saved rejection: HTTP ${rejection.status} · ${rejection.code.wireValue}',
                            ),
                          const Text(
                            'Your saved registration details have been kept.',
                          ),
                          Text(
                            operation.status ==
                                    PendingOnboardingStatus
                                        .reconciliationRequired
                                ? 'We cannot yet verify whether this registration was completed. Return to Members and contact support before registering this member again.'
                                : correctable
                                ? 'This registration was not completed. Fix the details below, then review and confirm again.'
                                : 'The previous registration cannot be safely corrected here. Its outcome or saved fields need verification before another registration can begin.',
                          ),
                          if (correctable) ...[
                            Text(
                              OnboardingCorrection.supported(
                                operation,
                              )!.explanation,
                            ),
                            const SizedBox(height: AppSpacing.lg),
                            FilledButton.icon(
                              onPressed: _beginCorrection,
                              icon: const Icon(Icons.edit_outlined),
                              label: const Text('Correct details and retry'),
                            ),
                          ] else if (_replacement != null) ...[
                            const Text(
                              'The corrected details are kept. Retry saves the same correction before sending it; no new registration key is generated.',
                            ),
                            FilledButton(
                              onPressed: _retryCorrection,
                              child: const Text(
                                'Retry saving corrected registration',
                              ),
                            ),
                          ] else
                            const Text(
                              'Return to Members and contact support to verify this registration. Do not register the member again.',
                            ),
                        ] else ...[
                          if (operation.attempts.lastOrNull?.rejection
                              case final rejection?)
                            Text(
                              'Last saved attempt: HTTP ${rejection.status} · ${rejection.code.wireValue}. Earlier uncertainty is still unresolved.',
                            ),
                          const Text(
                            'The previous registration must be checked before starting another. Retry saved registration sends the same saved details again, using duplicate protection. It does not start a new registration.',
                          ),
                          if (!_stored)
                            const Text(
                              'The prepared request has not been verified in storage yet. Retry saves the same request and key before sending anything.',
                            ),
                          const SizedBox(height: AppSpacing.lg),
                          FilledButton.icon(
                            onPressed: () => _act(acknowledge: false),
                            icon: const Icon(Icons.refresh),
                            label: const Text('Retry saved registration'),
                          ),
                        ],
                        const SizedBox(height: AppSpacing.lg),
                        TextButton(
                          onPressed: _reload,
                          child: const Text('Recheck saved registration'),
                        ),
                      ] else
                        FilledButton(
                          onPressed: _reload,
                          child: const Text('Retry recovery check'),
                        ),
                      const SizedBox(height: AppSpacing.lg),
                      const Text(
                        'Saved operations are never discarded automatically. Resolve this registration before starting another.',
                      ),
                    ],
                    const SizedBox(height: AppSpacing.lg),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => context.go(AppRoutes.members),
                      child: const Text('Return to Members'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
