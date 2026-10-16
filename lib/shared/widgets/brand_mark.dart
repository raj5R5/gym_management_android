import 'package:flutter/material.dart';

/// The same restrained identity in authentication, session and account views.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 52});
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ExcludeSemantics(
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: colors.primary,
            borderRadius: BorderRadius.circular(size * .27),
          ),
          child: Icon(
            Icons.fitness_center_outlined,
            size: size * .48,
            color: colors.onPrimary,
          ),
        ),
      ),
    );
  }
}
