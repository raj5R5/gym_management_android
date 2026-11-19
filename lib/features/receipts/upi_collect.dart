import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../app/router/app_routes.dart';
import '../../app/theme/design_tokens.dart';
import '../../shared/formatting/inr.dart';
import '../gym_settings/gym_settings.dart';
import '../owner_profile/owner_profile.dart';

/// Shows a UPI QR for the balance. Returns true when the owner wants to record
/// the payment next. Nothing is recorded automatically: the owner confirms the
/// money arrived and enters the UTR.
Future<bool> showUpiCollect(
  BuildContext context, {
  required int amountPaise,
  required String memberName,
  required String memberCode,
  required String planName,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (_) => _UpiCollectDialog(
        amountPaise: amountPaise,
        memberName: memberName,
        memberCode: memberCode,
        planName: planName,
      ),
    ) ??
    false;

class _UpiCollectDialog extends ConsumerWidget {
  const _UpiCollectDialog({
    required this.amountPaise,
    required this.memberName,
    required this.memberCode,
    required this.planName,
  });
  final int amountPaise;
  final String memberName, memberCode, planName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(gymSettingsProvider);
    final value = settings.asData?.value;
    final gymName = currentOwnerProfile(ref)?.gymName ?? 'Gym';
    final upiId = value?.upiId;
    return AlertDialog(
      title: Text('Collect ${formatCompactInrPaise(amountPaise)} by UPI'),
      content: settings.isLoading && value == null
          ? const SizedBox(
              height: 80,
              child: Center(child: CircularProgressIndicator()),
            )
          : upiId == null
          ? const Text(
              'Add your gym’s UPI ID in Gym settings to show a payment QR here.',
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.all(AppSpacing.md),
                  // Fixed size: dialogs measure intrinsic size.
                  child: SizedBox.square(
                    dimension: 220,
                    child: QrImageView(
                      data: upiPayUri(
                        upiId: upiId,
                        payeeName: value?.upiPayeeName ?? gymName,
                        amountPaise: amountPaise,
                        note: '$planName $memberCode',
                      ),
                      size: 220,
                      semanticsLabel:
                          'UPI payment QR for ${formatCompactInrPaise(amountPaise)}',
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  '$memberName scans this with any UPI app. Pays $upiId.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Once the money reaches your account, record the payment with its UTR number.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Close'),
        ),
        if (upiId == null && !settings.isLoading)
          FilledButton(
            onPressed: () {
              Navigator.pop(context, false);
              context.push(AppRoutes.gymSettings);
            },
            child: const Text('Add UPI ID'),
          )
        else if (upiId != null)
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Record payment'),
          ),
      ],
    );
  }
}
