import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/theme/design_tokens.dart';
import '../admin_dashboard/providers/dashboard_providers.dart';
import '../members/models/member_models.dart';
import '../members/providers/member_overview_providers.dart';
import 'visit_models.dart';
import 'visit_repository.dart';
import '../../shared/widgets/page_section.dart';

/// Checks [member] in now. When their membership is not active, asks before
/// checking them in anyway. Reports the result in a snackbar.
Future<void> checkInMember(
  BuildContext context,
  WidgetRef ref,
  MemberProfile member, {
  bool override = false,
}) async {
  final gym = ref.read(adminGymProvider);
  if (gym == null) return;
  final messenger = ScaffoldMessenger.of(context);
  // The page may close while the request runs; keep the container, not ref.
  final container = ProviderScope.containerOf(context, listen: false);
  try {
    final result = await container
        .read(visitRepositoryProvider)
        .checkIn(gym.gymId, member.id, override: override);
    HapticFeedback.mediumImpact();
    container
      ..invalidate(memberVisitHistoryProvider(member.id))
      ..invalidate(todayVisitsProvider)
      ..invalidate(memberOverviewProvider)
      ..invalidate(dashboardProvider);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          result.alreadyCheckedIn
              ? '${member.firstName} already checked in today'
              : '${member.firstName} checked in',
        ),
      ),
    );
  } on MembershipNotActive catch (refusal) {
    if (!context.mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(refusal.title),
        content: Text(refusal.message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Don't check in"),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Check in anyway'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await checkInMember(context, ref, member, override: true);
    }
  } on VisitFailure catch (failure) {
    messenger.showSnackBar(SnackBar(content: Text(failure.message)));
  }
}

/// Visits on the member page: last visit, last 30 days, check-in and QR card.
class MemberVisitsCard extends ConsumerStatefulWidget {
  const MemberVisitsCard({super.key, required this.member});
  final MemberProfile member;
  @override
  ConsumerState<MemberVisitsCard> createState() => _MemberVisitsCardState();
}

class _MemberVisitsCardState extends ConsumerState<MemberVisitsCard> {
  bool _busy = false;

  Future<void> _checkIn() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await checkInMember(context, ref, widget.member);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final history = ref.watch(memberVisitHistoryProvider(widget.member.id));
    final data = history.asData?.value;
    final gym = ref.watch(adminGymProvider);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: PlainBlock(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text('Visits', style: theme.textTheme.titleMedium),
            ),
            const SizedBox(height: AppSpacing.sm),
            if (history.isLoading && data == null)
              const LinearProgressIndicator(minHeight: 2)
            else if (history.hasError)
              Row(
                children: [
                  const Expanded(child: Text('Visits could not be loaded.')),
                  TextButton(
                    onPressed: () => ref.invalidate(
                      memberVisitHistoryProvider(widget.member.id),
                    ),
                    child: const Text('Retry'),
                  ),
                ],
              )
            else if (data != null) ...[
              Row(
                children: [
                  Expanded(
                    child: _Figure(
                      label: 'Last visit',
                      value: data.lastVisitLabel,
                    ),
                  ),
                  Expanded(
                    child: _Figure(
                      label: 'Last 30 days',
                      value:
                          '${data.visitsLast30Days} ${data.visitsLast30Days == 1 ? 'visit' : 'visits'}',
                    ),
                  ),
                ],
              ),
              if (data.visits.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Recent: ${data.visits.take(5).map((visit) => visit.visitDate.substring(5).split('-').reversed.join('/')).join(', ')}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ],
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                FilledButton.icon(
                  onPressed: _busy ? null : _checkIn,
                  icon: const Icon(Icons.login),
                  label: const Text('Check in now'),
                ),
                OutlinedButton.icon(
                  onPressed: gym == null
                      ? null
                      : () => showMemberQr(context, gym.gymId, widget.member),
                  icon: const Icon(Icons.qr_code_2),
                  label: const Text('Member QR'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.value});
  final String label, value;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: Theme.of(context).textTheme.bodySmall),
      Text(value, style: Theme.of(context).textTheme.titleMedium),
    ],
  );
}

/// Shows the member's check-in QR, with a share action (WhatsApp, etc.).
Future<void> showMemberQr(
  BuildContext context,
  String gymId,
  MemberProfile member,
) => showDialog<void>(
  context: context,
  builder: (context) {
    final data = MemberQrCode.encode(gymId: gymId, memberId: member.id);
    return AlertDialog(
      title: Text(member.name),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // A white quiet zone keeps the code scannable on the dark theme.
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(AppSpacing.md),
            // Fixed size: dialogs measure intrinsic size, which QrImageView can't report.
            child: SizedBox.square(
              dimension: 220,
              child: QrImageView(
                data: data,
                size: 220,
                semanticsLabel: 'Check-in QR code for ${member.name}',
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            '${member.memberCode} · Show this at the front desk to check in.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        FilledButton.icon(
          onPressed: () => _shareQr(context, data, member),
          icon: const Icon(Icons.share_outlined),
          label: const Text('Share'),
        ),
      ],
    );
  },
);

Future<void> _shareQr(
  BuildContext context,
  String data,
  MemberProfile member,
) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    final painter = QrPainter(
      data: data,
      version: QrVersions.auto,
      gapless: true,
      eyeStyle: const QrEyeStyle(
        eyeShape: QrEyeShape.square,
        color: Colors.black,
      ),
      dataModuleStyle: const QrDataModuleStyle(
        dataModuleShape: QrDataModuleShape.square,
        color: Colors.black,
      ),
    );
    // Draw on white with a margin so the shared image scans reliably.
    const size = 720.0, margin = 60.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)
      ..drawRect(
        const Rect.fromLTWH(0, 0, size + margin * 2, size + margin * 2),
        Paint()..color = Colors.white,
      )
      ..translate(margin, margin);
    painter.paint(canvas, const Size.square(size));
    final image = await recorder.endRecording().toImage(
      (size + margin * 2).toInt(),
      (size + margin * 2).toInt(),
    );
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) throw StateError('QR image unavailable');
    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile.fromData(
            bytes.buffer.asUint8List(),
            mimeType: 'image/png',
            name: 'checkin-${member.memberCode}.png',
          ),
        ],
        text:
            'Hi ${member.firstName}, this is your gym check-in QR. Show it at the front desk.',
      ),
    );
  } catch (_) {
    messenger?.showSnackBar(
      const SnackBar(content: Text('The QR could not be shared.')),
    );
  }
}
