import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../app/router/app_routes.dart';
import '../data/member_failure.dart';
import '../providers/member_providers.dart';

String memberPath(MemberScope scope, {bool edit = false}) =>
    '${AppRoutes.members}/${scope.memberId}${edit ? '/edit' : ''}?gymId=${Uri.encodeQueryComponent(scope.gymId)}';

class MemberError extends StatelessWidget {
  const MemberError({super.key, required this.error, required this.retry});
  final Object? error;
  final VoidCallback retry;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      children: [
        Semantics(
          liveRegion: true,
          child: Text(
            error is MemberFailure
                ? (error as MemberFailure).message
                : 'Member information could not be loaded. Please try again.',
          ),
        ),
        const SizedBox(height: 12),
        FilledButton(onPressed: retry, child: const Text('Retry')),
      ],
    ),
  );
}

class MemberContextChanged extends StatelessWidget {
  const MemberContextChanged({super.key});
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('The gym context changed. Return to Members to continue.'),
          TextButton(
            onPressed: () => context.go(AppRoutes.members),
            child: const Text('Return to Members'),
          ),
        ],
      ),
    ),
  );
}

class MemberSection extends StatelessWidget {
  const MemberSection({super.key, required this.title, required this.children});
  final String title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    ),
  );
}

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
