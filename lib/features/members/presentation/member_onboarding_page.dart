import '../photos/member_photo_widgets.dart';
import '../photos/member_photo_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_routes.dart';
import '../../../app/navigation/form_navigation_guard.dart';
import '../../memberships/presentation/plans_page.dart';
import '../../../app/theme/design_tokens.dart';
import '../../../core/config/app_config.dart';
import '../../../shared/widgets/soft_panel.dart';
import '../../admin_dashboard/providers/dashboard_providers.dart';
import '../../memberships/providers/membership_providers.dart';
import '../models/member_draft.dart';
import '../models/member_models.dart';
import '../models/onboarding_wizard_state.dart';
import '../models/onboarding_correction.dart';
import '../models/pending_onboarding.dart';
import '../providers/member_providers.dart';
import '../providers/onboarding_providers.dart';
import 'member_components.dart';
import 'onboarding_recovery_gate.dart';
import 'onboarding_plan_selection.dart';
import 'onboarding_payment_step.dart';
import 'onboarding_review_step.dart';

class MemberOnboardingPage extends ConsumerWidget {
  const MemberOnboardingPage({super.key, required this.gymId});
  final String? gymId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gym = ref.watch(adminGymProvider);
    if (gym == null) return const SizedBox.shrink();
    if (gym.gymId != gymId) return const MemberContextChanged();
    final config = ref.watch(appConfigProvider);
    if (config.apiBaseUrl == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(AppSpacing.xl),
          child: Text(
            'Configure the API connection before checking saved registrations.',
          ),
        ),
      );
    }
    final scope = OnboardingScope.fromConfig(
      config,
      userId: gym.userId,
      gymId: gym.gymId,
    );
    final service = ref.watch(memberOnboardingServiceProvider);
    // Recheck durable recovery before showing a draft in a different scope.
    return OnboardingRecoveryGate(
      key: ValueKey((scope.storageKey, service)),
      scope: scope,
      service: service,
      freshDraft: (confirm, initialDraft, correction) => _OnboardingWizard(
        gym: gym,
        onConfirm: confirm,
        initialDraft: initialDraft,
        correction: correction,
      ),
    );
  }
}

class _OnboardingWizard extends ConsumerStatefulWidget {
  const _OnboardingWizard({
    required this.gym,
    required this.onConfirm,
    this.initialDraft,
    this.correction,
  });
  final OnboardingWizardState? initialDraft;
  final OnboardingCorrection? correction;
  final AdminGymContext gym;
  final ValueChanged<OnboardingWizardState> onConfirm;

  @override
  ConsumerState<_OnboardingWizard> createState() => _OnboardingWizardState();
}

class _OnboardingWizardState extends ConsumerState<_OnboardingWizard> {
  final _form = GlobalKey<FormState>();
  final _paymentForm = GlobalKey<FormState>();
  final _scroll = ScrollController();
  late OnboardingWizardState _draft;
  late final Object _initialValues;
  bool _creatingPlan = false;
  @override
  void initState() {
    super.initState();
    _draft = widget.initialDraft ?? const OnboardingWizardState();
    _initialValues = _draft.draftValues;
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _move(OnboardingWizardState draft) {
    FocusScope.of(context).unfocus();
    setState(() => _draft = draft);
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  void _next() {
    final target = memberPhotoTarget(ref);
    if (target != null &&
        ref.read(memberPhotoControllerProvider(target)).asData?.value.busy ==
            true) {
      return;
    }
    if (_draft.step == OnboardingWizardStep.memberDetails &&
        !_form.currentState!.validate()) {
      return;
    }
    if (_draft.step == OnboardingWizardStep.payment &&
        !(_paymentForm.currentState?.validate() ?? false)) {
      return;
    }
    final issue = widget.correction?.issue(_draft);
    if (issue != null && issue.step == _draft.step) {
      setState(() {});
      return;
    }
    _move(_draft.next());
  }

  void _back() {
    if (_draft.step != OnboardingWizardStep.memberDetails) {
      _move(_draft.previous());
    } else if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.members);
    }
  }

  Future<void> _createPlan() async {
    if (_creatingPlan) return;
    _creatingPlan = true;
    FocusScope.of(context).unfocus();
    try {
      await context.push<bool>(planPath(widget.gym.gymId));
      if (!mounted || ref.read(adminGymProvider) != widget.gym) return;
      // Saving and cancelling both return to the same mounted draft.
      ref.invalidate(activePlansProvider);
      setState(() => _draft = _draft.copyWith(planPage: 1));
    } finally {
      _creatingPlan = false;
    }
  }

  Widget _field(
    String key,
    String label,
    String value,
    void Function(String) change, {
    required String? Function(String?) validator,
    required int maximum,
    TextInputType keyboard = TextInputType.text,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.lg),
    child: TextFormField(
      key: ValueKey(key),
      initialValue: value,
      onChanged: (value) => setState(() => change(value)),
      validator: validator,
      maxLength: maximum,
      keyboardType: keyboard,
      textInputAction: TextInputAction.next,
      decoration: InputDecoration(labelText: label, counterText: ''),
    ),
  );

  Widget _details() => Form(
    key: _form,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Start with their contact details. Gender is optional.'),
        const SizedBox(height: AppSpacing.xl),
        _field(
          'memberCode',
          'Member code',
          _draft.memberCode,
          (value) => _draft = _draft.copyWith(memberCode: value),
          validator: validateMemberCode,
          maximum: 32,
        ),
        _field(
          'firstName',
          'First name',
          _draft.firstName,
          (value) => _draft = _draft.copyWith(firstName: value),
          validator: validateName,
          maximum: 80,
        ),
        _field(
          'lastName',
          'Last name',
          _draft.lastName,
          (value) => _draft = _draft.copyWith(lastName: value),
          validator: validateName,
          maximum: 80,
        ),
        _field(
          'phone',
          'Phone',
          _draft.phone,
          (value) => _draft = _draft.copyWith(phone: value),
          validator: validatePhone,
          maximum: 25,
          keyboard: TextInputType.phone,
        ),
        _field(
          'dateOfBirth',
          'Date of birth (optional, YYYY-MM-DD)',
          _draft.dateOfBirth,
          (value) => _draft = _draft.copyWith(dateOfBirth: value),
          validator: validateBirthDate,
          maximum: 10,
          keyboard: TextInputType.datetime,
        ),
        DropdownButtonFormField<String>(
          isExpanded: true,
          initialValue: _draft.gender,
          decoration: const InputDecoration(labelText: 'Gender (optional)'),
          items: [
            const DropdownMenuItem(value: '', child: Text('Not specified')),
            for (final gender in memberGenders)
              DropdownMenuItem(
                value: gender,
                child: Text(
                  gender.replaceAll('_', ' '),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (value) =>
              setState(() => _draft = _draft.copyWith(gender: value ?? '')),
        ),
        if (memberPhotoTarget(ref) case final target?) ...[
          const SizedBox(height: 16),
          MemberPhotoEditor(target: target),
        ],
      ],
    ),
  );

  Widget _membership(BillingRequest request) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text('Choose how you want to register this member.'),
      const SizedBox(height: AppSpacing.lg),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Register member only'),
        subtitle: const Text(
          'Skip payment. A membership can be purchased later.',
        ),
        value: _draft.registerMemberOnly,
        onChanged: (value) =>
            setState(() => _draft = _draft.copyWith(registerMemberOnly: value)),
      ),
      const SizedBox(height: AppSpacing.lg),
      if (_draft.registerMemberOnly)
        const Text('The review will include member details only.')
      else
        OnboardingPlanSelection(
          plans: ref.watch(activePlansProvider(request)),
          selectedPlan: _draft.selectedPlan,
          onSelect: (plan) => setState(() => _draft = _draft.selectPlan(plan)),
          retry: () => ref.invalidate(activePlansProvider(request)),
          onCreatePlan: _createPlan,
          onPage: (page) =>
              setState(() => _draft = _draft.copyWith(planPage: page)),
        ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final photoTarget = memberPhotoTarget(ref);
    final photoBusy =
        photoTarget != null &&
        ref
                .watch(memberPhotoControllerProvider(photoTarget))
                .asData
                ?.value
                .busy ==
            true;
    final review = _draft.step == OnboardingWizardStep.review;
    // Plans are gym-scoped; no member has been created in this local draft.
    final request = (scope: scopeFor(widget.gym, ''), page: _draft.planPage);
    final selectingPlan =
        _draft.step == OnboardingWizardStep.membershipPlan &&
        !_draft.registerMemberOnly;
    final plans = selectingPlan
        ? ref.watch(activePlansProvider(request))
        : null;
    final planReady =
        !selectingPlan ||
        (!plans!.isLoading &&
            !plans.hasError &&
            plans.asData?.value != null &&
            plans.asData!.value!.pagination.total > 0 &&
            _draft.canContinue);
    return FormNavigationGuard(
      path: '${AppRoutes.members}/new',
      dirty: () => _draft.draftValues != _initialValues,
      busy: () =>
          photoTarget != null &&
          ref
                  .read(memberPhotoControllerProvider(photoTarget))
                  .asData
                  ?.value
                  .busy ==
              true,
      hasPreviousStep: _draft.step != OnboardingWizardStep.memberDetails,
      backWithinForm: _back,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: AppSurfaces.of(context).canvasGradient,
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final horizontal = constraints.maxWidth > AppSpacing.contentWidth
                ? (constraints.maxWidth - AppSpacing.contentWidth) / 2 +
                      AppSpacing.lg
                : AppSpacing.lg;
            return SingleChildScrollView(
              controller: _scroll,
              padding: EdgeInsets.fromLTRB(
                horizontal,
                AppSpacing.lg,
                horizontal,
                AppSpacing.xl,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SoftPanel(
                    tone: AppTone.neutral,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.correction == null
                              ? 'NEW MEMBER'
                              : 'CORRECT REGISTRATION',
                          style: Theme.of(
                            context,
                          ).textTheme.labelMedium?.copyWith(letterSpacing: 1.6),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          'Add member',
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          widget.correction?.explanation ??
                              'Review all details before confirming registration.',
                        ),
                        const SizedBox(height: AppSpacing.xl),
                        OnboardingProgress(
                          step: _draft.step,
                          paymentSkipped: _draft.registerMemberOnly,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  SoftPanel(
                    child: Column(
                      key: ValueKey(_draft.step),
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Semantics(
                          liveRegion: true,
                          child: Text(
                            'Step ${_draft.step.index + 1} of 4',
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          _draft.step.title,
                          key: const Key('onboarding-step-title'),
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        if (widget.correction?.issue(_draft)
                            case final issue?) ...[
                          Semantics(
                            liveRegion: true,
                            child: Text(issue.message),
                          ),
                          if (review)
                            TextButton(
                              onPressed: () =>
                                  _move(_draft.copyWith(step: issue.step)),
                              child: Text('Fix ${issue.step.title}'),
                            ),
                          const SizedBox(height: AppSpacing.md),
                        ],
                        switch (_draft.step) {
                          OnboardingWizardStep.memberDetails => _details(),
                          OnboardingWizardStep.membershipPlan => _membership(
                            request,
                          ),
                          OnboardingWizardStep.payment => OnboardingPaymentStep(
                            draft: _draft,
                            formKey: _paymentForm,
                            onChanged: (draft) =>
                                setState(() => _draft = draft),
                          ),
                          OnboardingWizardStep.review => OnboardingReviewStep(
                            draft: _draft,
                            gymId: widget.gym.gymId,
                            onEdit: (step) =>
                                _move(_draft.copyWith(step: step)),
                          ),
                        },
                        const SizedBox(height: AppSpacing.xl),
                        Wrap(
                          spacing: AppSpacing.md,
                          runSpacing: AppSpacing.md,
                          children: [
                            OutlinedButton.icon(
                              onPressed: photoBusy ? null : _back,
                              icon: const Icon(Icons.arrow_back),
                              label: const Text('Back'),
                            ),
                            FilledButton.icon(
                              style: AppButtonStyles.primary(context),
                              onPressed: photoBusy
                                  ? null
                                  : review
                                  ? _draft.canConfirm(
                                              gymId: widget.gym.gymId,
                                            ) &&
                                            widget.correction?.issue(_draft) ==
                                                null
                                        ? () => widget.onConfirm(_draft)
                                        : null
                                  : !planReady
                                  ? null
                                  : _next,
                              icon: Icon(
                                review ? Icons.check : Icons.arrow_forward,
                              ),
                              label: Text(
                                review ? 'Confirm registration' : 'Continue',
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class OnboardingProgress extends StatelessWidget {
  const OnboardingProgress({
    super.key,
    required this.step,
    required this.paymentSkipped,
  });
  final OnboardingWizardStep step;
  final bool paymentSkipped;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surfaces = AppSurfaces.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context);
        final labels = constraints.maxWidth >= 560 && scale.scale(14) <= 21;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final item in OnboardingWizardStep.values) ...[
              if (item.index > 0)
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(top: scale.scale(14) / 2 + 9),
                    child: Container(height: 1, color: surfaces.border),
                  ),
                ),
              Semantics(
                label:
                    'Step ${item.index + 1}: ${item.title}${paymentSkipped && item == OnboardingWizardStep.payment ? ', skipped' : ''}',
                selected: item == step,
                child: ExcludeSemantics(
                  child: Column(
                    children: [
                      Container(
                        width: scale.scale(14) + 18,
                        height: scale.scale(14) + 18,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: item == step
                              ? theme.colorScheme.primary
                              : item.index < step.index &&
                                    !(paymentSkipped &&
                                        item == OnboardingWizardStep.payment)
                              ? surfaces.active
                              : theme.colorScheme.surface,
                          border: Border.all(color: surfaces.border),
                        ),
                        child: Text(
                          '${item.index + 1}',
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: item == step
                                ? theme.colorScheme.onPrimary
                                : item.index < step.index &&
                                      !(paymentSkipped &&
                                          item == OnboardingWizardStep.payment)
                                ? surfaces.onStatus
                                : theme.colorScheme.onSurface,
                          ),
                        ),
                      ),
                      if (labels) ...[
                        const SizedBox(height: AppSpacing.sm),
                        SizedBox(
                          width: 115,
                          child: Text(
                            item.title,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.labelSmall,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}
