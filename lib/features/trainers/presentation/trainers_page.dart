import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/router/app_routes.dart';
import '../../admin_dashboard/providers/dashboard_providers.dart';
import '../data/trainer_failure.dart';
import '../models/trainer_models.dart';
import '../providers/trainer_providers.dart';
import 'trainer_components.dart';
import '../../../shared/widgets/page_controls.dart';

class TrainersPageView extends ConsumerWidget {
  const TrainersPageView({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gym = ref.watch(adminGymProvider);
    return gym == null
        ? const SizedBox.shrink()
        : _TrainersList(key: ValueKey(gym), gym: gym);
  }
}

class _TrainersList extends ConsumerStatefulWidget {
  const _TrainersList({super.key, required this.gym});
  final AdminGymContext gym;
  @override
  ConsumerState<_TrainersList> createState() => _TrainersListState();
}

class _TrainersListState extends ConsumerState<_TrainersList> {
  late final TextEditingController _search;
  @override
  void initState() {
    super.initState();
    _search = TextEditingController(
      text: ref.read(trainerQueryProvider).search,
    );
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      await ref.read(trainersProvider.notifier).reload();
    } on TrainerFailure {
      /* AsyncValue renders the safe failure. */
    }
  }

  void _apply(TrainerStatus? status) {
    FocusScope.of(context).unfocus();
    ref
        .read(trainerQueryProvider.notifier)
        .apply(search: _search.text, status: status);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(trainersProvider);
    final query = ref.watch(trainerQueryProvider);
    final result = state.asData?.value;
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            children: [
              Text(
                'Trainers',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              IconButton(
                tooltip: 'Refresh trainers',
                onPressed: state.isLoading ? null : _refresh,
                icon: const Icon(Icons.refresh),
              ),
              FilledButton.icon(
                onPressed: () => context.push(
                  '${AppRoutes.trainers}/new?gymId=${widget.gym.gymId}',
                ),
                icon: const Icon(Icons.person_add_outlined),
                label: const Text('Add trainer'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _search,
            maxLength: 100,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              labelText: 'Search trainers',
              hintText: 'Code, name, phone or specialization',
              suffixIcon: IconButton(
                tooltip: 'Search',
                onPressed: () => _apply(query.status),
                icon: const Icon(Icons.search),
              ),
            ),
            onSubmitted: (_) => _apply(query.status),
            onChanged: (value) {
              if (value.isEmpty && query.search.isNotEmpty) {
                _apply(query.status);
              }
            },
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<TrainerStatus?>(
            isExpanded: true,
            key: ValueKey(query.status),
            initialValue: query.status,
            decoration: const InputDecoration(labelText: 'Trainer status'),
            items: [
              const DropdownMenuItem(value: null, child: Text('All statuses')),
              ...TrainerStatus.values.map(
                (status) =>
                    DropdownMenuItem(value: status, child: Text(status.name)),
              ),
            ],
            onChanged: _apply,
          ),
          const SizedBox(height: 16),
          if (state.isLoading)
            const Center(
              child: CircularProgressIndicator(
                semanticsLabel: 'Loading trainers',
              ),
            )
          else if (state.hasError)
            TrainerError(error: state.error, retry: _refresh)
          else if (result != null) ...[
            if (result.trainers.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  query.search.isEmpty &&
                          query.status == null &&
                          query.page == 1
                      ? 'No trainers yet. Add your first trainer.'
                      : 'No trainers match this page or filter.',
                ),
              ),
            ...result.trainers.map(
              (trainer) => Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Theme.of(
                      context,
                    ).colorScheme.secondaryContainer,
                    foregroundColor: Theme.of(
                      context,
                    ).colorScheme.onSecondaryContainer,
                    child: Text(
                      trainer.firstName.characters.first.toUpperCase(),
                    ),
                  ),
                  title: Text(trainer.name),
                  subtitle: Text(
                    '${trainer.trainerCode} · ${trainer.phone}\n${trainer.status.name}${trainer.branchId == null ? ' · No branch assigned' : ' · Branch: ${trainer.branchId}'}${(trainer.specializations ?? []).isEmpty ? '' : '\n${trainer.specializations!.join(', ')}'}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push(
                    trainerPath(scopeFor(widget.gym, trainer.id)),
                  ),
                ),
              ),
            ),
            PageControls(
              page: result.pagination.page,
              total: result.pagination.total,
              previous: result.pagination.hasPrevious
                  ? () => ref
                        .read(trainerQueryProvider.notifier)
                        .page(query.page - 1)
                  : null,
              next: result.pagination.hasNext
                  ? () => ref
                        .read(trainerQueryProvider.notifier)
                        .page(query.page + 1)
                  : null,
            ),
          ],
        ],
      ),
    );
  }
}
