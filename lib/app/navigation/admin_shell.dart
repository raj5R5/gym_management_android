import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/admin_dashboard/providers/dashboard_providers.dart';
import '../../features/auth/models/session_state.dart';
import '../../features/auth/providers/session_controller.dart';
import '../router/app_routes.dart';
import 'foundation_screens.dart';

class AdminShell extends ConsumerWidget {
  const AdminShell({super.key, required this.location, required this.child});
  final String location;
  final Widget child;
  static const destinations = [
    AppRoutes.dashboard,
    AppRoutes.members,
    AppRoutes.trainers,
    AppRoutes.more,
  ];
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionControllerProvider);
    final gyms = ref.watch(adminGymIdsProvider);
    final selected = ref.watch(adminGymProvider);
    // Do not render protected content during the router's asynchronous refresh.
    final refreshing =
        session is SessionLoading &&
        session.operation == SessionOperation.refreshing;
    if (session is! SessionAuthenticated && !refreshing || selected == null) {
      return const SizedBox.shrink();
    }
    final memberDetail = location.startsWith('${AppRoutes.members}/');
    final trainerDetail = location.startsWith('${AppRoutes.trainers}/');
    final profileDetail = memberDetail || trainerDetail;
    final index = memberDetail
        ? 1
        : trainerDetail
        ? 2
        : destinations.indexOf(location);
    final shell = PopScope(
      canPop: profileDetail || index <= 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !profileDetail) context.go(AppRoutes.dashboard);
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Gym Management'),
          automaticallyImplyLeading: false,
        ),
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: gyms.length > 1
                    ? DropdownButtonFormField<String>(
                        key: ValueKey(selected),
                        initialValue: selected.gymId,
                        decoration: const InputDecoration(
                          labelText: 'Admin gym',
                        ),
                        isExpanded: true,
                        items: gyms
                            .map(
                              (id) => DropdownMenuItem(
                                value: id,
                                child: Text(
                                  'Gym $id',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (id) {
                          if (id != null) {
                            ref.read(adminGymProvider.notifier).selectGym(id);
                          }
                        },
                      )
                    : Text(
                        'Gym: ${selected.gymId}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
              ),
              Expanded(child: child),
            ],
          ),
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: index < 0 ? 0 : index,
          onDestinationSelected: (value) => context.go(destinations[value]),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.dashboard_outlined),
              label: 'Dashboard',
            ),
            NavigationDestination(
              icon: Icon(Icons.people_outline),
              label: 'Members',
            ),
            NavigationDestination(
              icon: Icon(Icons.fitness_center),
              label: 'Trainers',
            ),
            NavigationDestination(icon: Icon(Icons.more_horiz), label: 'More'),
          ],
        ),
      ),
    );
    return Stack(
      children: [
        Offstage(
          offstage: refreshing,
          child: TickerMode(enabled: !refreshing, child: shell),
        ),
        if (refreshing) const StartupScreen(),
      ],
    );
  }
}
