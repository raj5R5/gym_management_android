import 'package:flutter/material.dart';

import '../../app/theme/design_tokens.dart';

/// Asks one clear question before an action.
///
/// Write the [title] as the real question ("Cancel package?"), keep
/// [message] to the one fact that matters, and label both buttons with what
/// they do ("Keep package" / "Cancel package"), never a bare "Cancel".
/// [destructive] marks actions that drop or remove something.
///
/// Returns true only when the action button was tapped.
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  String? message,
  required String confirmLabel,
  required String keepLabel,
  bool destructive = false,
  bool dismissible = true,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    barrierDismissible: dismissible,
    builder: (context) => ConfirmDialog(
      title: title,
      message: message,
      confirmLabel: confirmLabel,
      keepLabel: keepLabel,
      destructive: destructive,
      onKeep: () => Navigator.pop(context, false),
      onConfirm: () => Navigator.pop(context, true),
    ),
  );
  return confirmed == true;
}

/// The pop-up behind [showConfirmDialog]. Use it directly when the dialog
/// needs extra [content], such as a reason field.
class ConfirmDialog extends StatelessWidget {
  const ConfirmDialog({
    super.key,
    required this.title,
    this.message,
    this.content,
    required this.confirmLabel,
    required this.keepLabel,
    required this.onKeep,
    required this.onConfirm,
    this.destructive = false,
  });

  final String title;
  final String? message;
  final Widget? content;
  final String confirmLabel, keepLabel;
  final VoidCallback onKeep;

  /// Null disables the action button.
  final VoidCallback? onConfirm;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      scrollable: true,
      title: Text(title),
      content: message == null && content == null
          ? null
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (message != null)
                  Text(
                    message!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: AppColors.textMuted,
                    ),
                  ),
                if (message != null && content != null)
                  const SizedBox(height: AppSpacing.lg),
                ?content,
              ],
            ),
      actions: [
        TextButton(onPressed: onKeep, child: Text(keepLabel)),
        FilledButton(
          style: destructive ? AppButtonStyles.warning(context) : null,
          onPressed: onConfirm,
          child: Text(confirmLabel),
        ),
      ],
    );
  }
}
