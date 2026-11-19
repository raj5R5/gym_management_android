import 'package:flutter/material.dart';
import 'weight_plate.dart';

/// The same physical gym identity in authentication, session and account views.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 52});
  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Align(
      alignment: Alignment.centerLeft,
      child: WeightPlate(size: size, animate: false),
    ),
  );
}
