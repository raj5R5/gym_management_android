import 'package:flutter/material.dart';
import '../../app/theme/design_tokens.dart';
import 'soft_panel.dart';

class ProfileSection extends StatelessWidget {
  const ProfileSection({
    super.key,
    required this.title,
    required this.children,
    this.tone = AppTone.neutral,
    this.icon,
    this.subtitle,
  });
  final String title;
  final List<Widget> children;
  final AppTone tone;
  final IconData? icon;
  final String? subtitle;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.md),
    child: SoftPanel(
      tone: tone,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (icon == null)
            Text(title, style: Theme.of(context).textTheme.titleLarge)
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ExcludeSemantics(
                  child: Container(
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    decoration: BoxDecoration(
                      color: AppSurfaces.of(context).panel(
                        tone == AppTone.neutral ? AppTone.payment : tone,
                        Theme.of(context).brightness,
                      ),
                      borderRadius: BorderRadius.circular(AppRadii.control),
                    ),
                    child: Icon(
                      icon,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                ),
              ],
            ),
          if (subtitle != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
          ],
          SizedBox(height: icon == null ? AppSpacing.sm : AppSpacing.md),
          ...children,
        ],
      ),
    ),
  );
}
