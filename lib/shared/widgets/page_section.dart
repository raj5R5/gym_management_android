import 'package:flutter/material.dart';

import '../../app/theme/design_tokens.dart';

/// A titled block that sits straight on the page background.
///
/// Space, not a card, separates it from its neighbours: on the dark
/// background a card around every block only adds edges. Keep a card for
/// the one block that matters most on a screen (a balance, a membership).
class PageSection extends StatelessWidget {
  const PageSection({
    super.key,
    required this.title,
    required this.children,
    this.subtitle,
    this.trailing,
    this.top = AppSpacing.xxxl,
  });

  final String title;
  final String? subtitle;

  /// A small action beside the title, such as a "See all" button.
  final Widget? trailing;
  final List<Widget> children;

  /// Space above the title.
  final double top;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(top: top),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(title, style: theme.textTheme.titleMedium),
                ),
              ),
              ?trailing,
            ],
          ),
          if (subtitle != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(subtitle!, style: theme.textTheme.bodySmall),
            ),
          const SizedBox(height: AppSpacing.md),
          ...children,
        ],
      ),
    );
  }
}

/// Rows with a thin line only between them, never above the first or below
/// the last. [indent] starts the line where the row text starts, so leading
/// icons stay in one clean column.
class SeparatedRows extends StatelessWidget {
  const SeparatedRows({super.key, required this.children, this.indent = 0});

  final List<Widget> children;
  final double indent;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (var i = 0; i < children.length; i++) ...[
        if (i > 0) Divider(height: 1, indent: indent),
        children[i],
      ],
    ],
  );
}

/// Content that sits on the page with space around it instead of a card.
/// Use where a [GlassCard] only grouped a block that is not the screen's
/// main one.
class PlainBlock extends StatelessWidget {
  const PlainBlock({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
    child: child,
  );
}
