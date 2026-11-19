import 'package:flutter/material.dart';

import '../../app/theme/design_tokens.dart';

enum AppTextVariant {
  display,
  title,
  heading,
  body,
  bodyStrong,
  small,
  caption,
  overline,
  tab,
}

/// Geist text in one of the design's type styles. Defaults to body white.
/// [AppTextVariant.overline] is set in uppercase.
class AppText extends StatelessWidget {
  const AppText(
    this.text, {
    super.key,
    this.variant = AppTextVariant.body,
    this.color = AppColors.text,
    this.textAlign,
    this.maxLines,
    this.overflow,
    this.style,
  });

  final String text;
  final AppTextVariant variant;
  final Color color;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;
  final TextStyle? style;

  static TextStyle styleOf(AppTextVariant variant) => switch (variant) {
    AppTextVariant.display => AppType.display,
    AppTextVariant.title => AppType.title,
    AppTextVariant.heading => AppType.heading,
    AppTextVariant.body => AppType.body,
    AppTextVariant.bodyStrong => AppType.bodyStrong,
    AppTextVariant.small => AppType.small,
    AppTextVariant.caption => AppType.caption,
    AppTextVariant.overline => AppType.overline,
    AppTextVariant.tab => AppType.tab,
  };

  @override
  Widget build(BuildContext context) => Text(
    variant == AppTextVariant.overline ? text.toUpperCase() : text,
    textAlign: textAlign,
    maxLines: maxLines,
    overflow: overflow,
    style: styleOf(variant).copyWith(color: color).merge(style),
  );
}
