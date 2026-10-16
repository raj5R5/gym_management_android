import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final formNavigationGuardProvider = Provider((ref) => FormNavigationRegistry());

/// Presentation-only exit protection. Durable recovery records are never touched.
class FormNavigationRegistry {
  final Map<Object, _FormExit> _forms = {};
  bool _asking = false;

  void register(
    Object owner,
    String path,
    BuildContext context,
    bool Function() dirty,
    bool Function() busy,
  ) {
    _forms[owner] = _FormExit(path, context, dirty, busy);
  }

  void unregister(Object owner) => _forms.remove(owner);

  Future<bool> allowExit({String? path}) async {
    if (_asking) return false;
    final forms = _forms.values
        .where((form) => path == null || form.path == path)
        .toList();
    if (forms.any((form) => form.busy())) return false;
    final changed = forms.where((form) => form.dirty()).toList();
    if (changed.isEmpty) return true;
    _asking = true;
    try {
      final context = changed.last.context;
      if (!context.mounted) return false;
      FocusScope.of(context).unfocus();
      final discard = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          scrollable: true,
          title: const Text('Discard unsaved changes?'),
          content: const Text(
            'Your changes have not been saved. Keep editing to finish, or discard them to leave this form.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep editing'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Discard changes'),
            ),
          ],
        ),
      );
      return discard == true &&
          forms.every(
            (form) =>
                _forms.containsValue(form) &&
                form.context.mounted &&
                !form.busy(),
          );
    } finally {
      _asking = false;
    }
  }
}

class _FormExit {
  _FormExit(this.path, this.context, this.dirty, this.busy);
  final String path;
  final BuildContext context;
  final bool Function() dirty, busy;
}

class FormNavigationGuard extends ConsumerStatefulWidget {
  const FormNavigationGuard({
    super.key,
    required this.path,
    required this.dirty,
    required this.busy,
    required this.child,
    this.backWithinForm,
    this.hasPreviousStep = false,
    this.protectBack = true,
  });
  final String path;
  final bool Function() dirty, busy;
  final VoidCallback? backWithinForm;
  final bool hasPreviousStep;
  final bool protectBack;
  final Widget child;

  @override
  ConsumerState<FormNavigationGuard> createState() =>
      _FormNavigationGuardState();
}

class _FormNavigationGuardState extends ConsumerState<FormNavigationGuard> {
  late final FormNavigationRegistry _registry;
  bool _allowPop = false;

  @override
  void initState() {
    super.initState();
    _registry = ref.read(formNavigationGuardProvider);
    _registry.register(
      this,
      widget.path,
      context,
      () => !_allowPop && widget.dirty(),
      () => widget.busy(),
    );
  }

  @override
  void dispose() {
    _registry.unregister(this);
    super.dispose();
  }

  Future<void> _back() async {
    if (widget.busy()) return;
    if (widget.hasPreviousStep) {
      widget.backWithinForm?.call();
      return;
    }
    if (!await _registry.allowExit(path: widget.path) || !mounted) return;
    setState(() => _allowPop = true);
    // PopScope must rebuild before Navigator performs the approved pop.
    await WidgetsBinding.instance.endOfFrame;
    if (mounted && !widget.busy()) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) => !widget.protectBack
      ? widget.child
      : PopScope(
          canPop:
              !widget.busy() &&
              (_allowPop || (!widget.dirty() && !widget.hasPreviousStep)),
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _back();
          },
          child: widget.child,
        );
}
