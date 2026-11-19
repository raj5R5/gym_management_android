import 'package:flutter/material.dart';
import '../../app/theme/design_tokens.dart';
import 'soft_panel.dart';

/// A titled group of content.
///
/// Neutral sections sit straight on the page and space separates them;
/// sections with a [tone] (warnings, plans) and the screen's main block
/// ([card] true) keep a panel so they stand out.
class ProfileSection extends StatelessWidget {
  const ProfileSection({
    super.key,
    required this.title,
    required this.children,
    this.tone = AppTone.neutral,
    this.icon,
    this.subtitle,
    this.compactHeader = true,
    this.card,
  });
  final String title;
  final List<Widget> children;
  final AppTone tone;
  final IconData? icon;
  final String? subtitle;
  final bool compactHeader;

  /// Whether to draw a panel; defaults to true only for a non-neutral [tone].
  final bool? card;

  @override
  Widget build(BuildContext context) {
    final boxed = card ?? tone != AppTone.neutral;
    // Plain headings line up as text only; an icon there breaks the column.
    final content = _content(context, boxed ? icon : null);
    if (!boxed) {
      return Padding(
        padding: const EdgeInsets.only(
          top: AppSpacing.md,
          bottom: AppSpacing.xxl,
        ),
        child: content,
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: SoftPanel(
        tone: tone,
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: content,
      ),
    );
  }

  Widget _content(BuildContext context, IconData? icon) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (icon == null)
        Semantics(
          header: true,
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        )
      else
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(
              child: compactHeader
                  ? Icon(
                      icon,
                      size: 20,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    )
                  : Container(
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      decoration: BoxDecoration(
                        color: AppSurfaces.of(context).accent(
                          tone == AppTone.neutral ? AppTone.payment : tone,
                        ),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Color.alphaBlend(
                              Colors.white.withValues(alpha: .10),
                              AppSurfaces.of(context).accent(
                                tone == AppTone.neutral
                                    ? AppTone.payment
                                    : tone,
                              ),
                            ),
                            AppSurfaces.of(context).accent(
                              tone == AppTone.neutral ? AppTone.payment : tone,
                            ),
                          ],
                        ),
                        border: Border.all(
                          color: AppSurfaces.of(context).border,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppSurfaces.of(context).shadow,
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                        borderRadius: BorderRadius.circular(AppRadii.control),
                      ),
                      child: Icon(
                        icon,
                        color: AppSurfaces.of(context).onAccent(
                          tone == AppTone.neutral ? AppTone.payment : tone,
                        ),
                      ),
                    ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Semantics(
                header: true,
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ),
          ],
        ),
      if (subtitle != null) ...[
        const SizedBox(height: AppSpacing.sm),
        Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
      ],
      SizedBox(
        height: icon == null || compactHeader ? AppSpacing.sm : AppSpacing.md,
      ),
      ...children,
    ],
  );
}
