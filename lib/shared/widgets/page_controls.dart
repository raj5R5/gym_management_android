import 'package:flutter/material.dart';

class PageControls extends StatelessWidget {
  const PageControls({
    super.key,
    required this.page,
    required this.total,
    required this.previous,
    required this.next,
  });
  final int page, total;
  final VoidCallback? previous, next;
  @override
  Widget build(BuildContext context) => Wrap(
    alignment: WrapAlignment.center,
    crossAxisAlignment: WrapCrossAlignment.center,
    spacing: 8,
    children: [
      IconButton(
        tooltip: 'Previous page',
        onPressed: previous,
        icon: const Icon(Icons.chevron_left),
      ),
      Text('Page $page · $total total'),
      IconButton(
        tooltip: 'Next page',
        onPressed: next,
        icon: const Icon(Icons.chevron_right),
      ),
    ],
  );
}
