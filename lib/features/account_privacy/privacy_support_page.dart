import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/router/app_routes.dart';
import '../../app/theme/design_tokens.dart';
import '../../core/config/public_app_info.dart';
import '../../core/platform/public_links.dart';
import '../../shared/widgets/feedback_notice.dart';
import '../../shared/widgets/profile_section.dart';

class PrivacySupportPage extends ConsumerWidget {
  const PrivacySupportPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = ref.watch(publicAppInfoProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Privacy & support')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            ProfileSection(
              title: info.appName,
              icon: Icons.shield_outlined,
              children: [
                if (info.publisher.isNotEmpty) Text(info.publisher),
                const Text(
                  'Review how account, gym, member, payment and optional photo information is handled.',
                ),
              ],
            ),
            PolicyLinkSection(
              title: 'Privacy policy',
              icon: Icons.policy_outlined,
              uri: info.privacyUrl,
            ),
            PolicyLinkSection(
              title: 'Account deletion',
              icon: Icons.person_remove_outlined,
              uri: info.deletionUrl,
            ),
            ProfileSection(
              title: 'Contact support',
              icon: Icons.support_agent_outlined,
              children: [
                if (info.supportEmail.isNotEmpty) ...[
                  SelectableText(info.supportEmail),
                  TextButton.icon(
                    onPressed: () => Clipboard.setData(
                      ClipboardData(text: info.supportEmail),
                    ),
                    icon: const Icon(Icons.copy_outlined),
                    label: const Text('Copy support email'),
                  ),
                ] else
                  const Text(
                    'Public support contact details are not configured in this development build.',
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class PolicyLinkSection extends ConsumerStatefulWidget {
  const PolicyLinkSection({
    super.key,
    required this.title,
    required this.icon,
    required this.uri,
  });
  final String title;
  final IconData icon;
  final Uri? uri;
  @override
  ConsumerState<PolicyLinkSection> createState() => _PolicyLinkSectionState();
}

class _PolicyLinkSectionState extends ConsumerState<PolicyLinkSection> {
  String? _error;
  bool _opening = false;
  @override
  Widget build(BuildContext context) => ProfileSection(
    title: widget.title,
    icon: widget.icon,
    children: [
      if (widget.uri case final uri?) ...[
        SelectableText(uri.toString()),
        Wrap(
          spacing: AppSpacing.sm,
          children: [
            OutlinedButton.icon(
              onPressed: _opening
                  ? null
                  : () async {
                      setState(() {
                        _opening = true;
                        _error = null;
                      });
                      try {
                        await ref.read(publicLinksProvider).open(uri);
                      } on PlatformException {
                        if (mounted) {
                          setState(
                            () => _error =
                                'The browser could not be opened. Copy the link instead.',
                          );
                        }
                      } on MissingPluginException {
                        if (mounted) {
                          setState(
                            () => _error =
                                'Opening links is unavailable on this platform. Copy the link instead.',
                          );
                        }
                      } finally {
                        if (mounted) setState(() => _opening = false);
                      }
                    },
              icon: const Icon(Icons.open_in_new),
              label: Text(_opening ? 'Opening…' : 'Open website'),
            ),
            TextButton.icon(
              onPressed: () =>
                  Clipboard.setData(ClipboardData(text: uri.toString())),
              icon: const Icon(Icons.copy_outlined),
              label: const Text('Copy link'),
            ),
          ],
        ),
        if (_error case final message?) FeedbackNotice(message: message),
      ] else
        const Text(
          'The public page is not configured in this development build. It must be configured and published before a Play release.',
        ),
    ],
  );
}

class PrivacySupportLink extends StatelessWidget {
  const PrivacySupportLink({super.key, this.enabled = true});
  final bool enabled;
  @override
  Widget build(BuildContext context) => TextButton.icon(
    onPressed: enabled ? () => context.push(AppRoutes.privacySupport) : null,
    icon: const Icon(Icons.policy_outlined),
    label: const Text('Privacy & support'),
  );
}
