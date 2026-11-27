import '../../app/theme/design_tokens.dart';
import 'package:flutter/material.dart';

/// Previous / next for a paged list; hidden when there is only one page.
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
  Widget build(BuildContext context) {
    // Everything fits on one page: a pager with nowhere to go is noise.
    if (page == 1 && previous == null && next == null) {
      return const SizedBox.shrink();
    }
    return _controls();
  }

  Widget _controls() => Wrap(
    alignment: WrapAlignment.center,
    crossAxisAlignment: WrapCrossAlignment.center,
    spacing: AppSpacing.sm,
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
