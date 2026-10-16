import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/admin_dashboard/providers/dashboard_providers.dart';
import '../../features/auth/models/session_state.dart';
import '../../features/auth/providers/session_controller.dart';
import '../router/app_routes.dart';
import 'foundation_screens.dart';
import '../../shared/widgets/brand_mark.dart';
import 'form_navigation_guard.dart';

class AdminShell extends ConsumerWidget {
  const AdminShell({super.key, required this.location, required this.child});
  final String location;
  final Widget child;
  static const destinations = [
    AppRoutes.dashboard,
    AppRoutes.members,
    AppRoutes.trainers,
    AppRoutes.plans,
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
    // The identity contract has no gym names. Use ordinal scope labels on the
    // member overview, while retaining the actual IDs as selector values.
    final memberOverview = RegExp(
      '^${AppRoutes.members}/[a-fA-F0-9]{24}\$',
    ).hasMatch(location);
    final trainerDetail = location.startsWith('${AppRoutes.trainers}/');
    final planDetail = location.startsWith('${AppRoutes.plans}/');
    final attendance =
        location == AppRoutes.attendance ||
        location.startsWith('${AppRoutes.attendance}/');
    final attendanceDetail = location.startsWith('${AppRoutes.attendance}/');
    final profileDetail =
        attendanceDetail ||
        memberDetail ||
        trainerDetail ||
        planDetail ||
        location.startsWith('${AppRoutes.dashboard}/');
    final index = memberDetail
        ? 1
        : trainerDetail
        ? 2
        : planDetail
        ? 3
        : location.startsWith('${AppRoutes.dashboard}/')
        ? 0
        : destinations.indexOf(location);
    final gymField = GlobalKey<FormFieldState<String>>();
    final shell = PopScope(
      canPop: profileDetail || index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !profileDetail) context.go(AppRoutes.dashboard);
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Gym Management'),
          automaticallyImplyLeading: false,
          leading: Builder(
            builder: (context) => IconButton(
              tooltip: 'Admin navigation',
              onPressed: () => Scaffold.of(context).openDrawer(),
              icon: const Icon(Icons.menu),
            ),
          ),
        ),
        drawer: Drawer(
          child: SafeArea(
            child: ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const BrandMark(),
                      const SizedBox(height: 20),
                      Text(
                        'Gym Management',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Admin navigation',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                ...{
                  'Dashboard': AppRoutes.dashboard,
                  'Members': AppRoutes.members,
                  'Trainers': AppRoutes.trainers,
                  'Plans': AppRoutes.plans,
                  'More': AppRoutes.more,
                }.entries.map(
                  (entry) => ListTile(
                    leading: Icon(switch (entry.value) {
                      AppRoutes.dashboard => Icons.dashboard_outlined,
                      AppRoutes.members => Icons.people_outline,
                      AppRoutes.trainers => Icons.fitness_center_outlined,
                      AppRoutes.plans => Icons.card_membership_outlined,
                      _ => Icons.more_horiz,
                    }),
                    title: Text(entry.key),
                    selected:
                        location == entry.value ||
                        location.startsWith('${entry.value}/'),
                    onTap: () {
                      Navigator.of(context).pop();
                      if (location == entry.value) return;
                      if (entry.value == AppRoutes.more && !profileDetail) {
                        // Account is a drawer page, not a tab. Retain the
                        // previous tab so Android Back has a route to pop.
                        // Detail/form exits still use go(), preserving the
                        // router's existing unsaved/busy-form exit guards.
                        context.push(entry.value);
                      } else {
                        context.go(entry.value);
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
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
                        key: gymField,
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
                                  memberOverview
                                      ? 'Gym ${gyms.indexOf(id) + 1}'
                                      : 'Gym $id',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (id) async {
                          if (id == null || id == selected.gymId) return;
                          final allowed = await ref
                              .read(formNavigationGuardProvider)
                              .allowExit();
                          if (!context.mounted ||
                              ref.read(adminGymProvider) != selected) {
                            return;
                          }
                          if (allowed) {
                            ref.read(adminGymProvider.notifier).selectGym(id);
                          } else {
                            gymField.currentState?.didChange(selected.gymId);
                          }
                        },
                      )
                    : Text(
                        memberOverview
                            ? 'Current gym'
                            : 'Current gym · All branches',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
              ),
              Expanded(child: child),
            ],
          ),
        ),
        // More remains a drawer-only account page. It has no matching tab,
        // so omit the bar rather than falsely selecting Dashboard.
        bottomNavigationBar: attendance || location == AppRoutes.more
            ? null
            : LayoutBuilder(
                builder: (context, constraints) {
                  final theme = Theme.of(context);
                  final baseStyle = theme.textTheme.labelMedium!.copyWith(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0,
                  );
                  // Match NavigationBar's own maximum label scaling. Measure
                  // the longest label before layout so all four labels use the
                  // same size and neither selection nor scaling causes a wrap.
                  final painter = TextPainter(
                    text: TextSpan(text: 'Dashboard', style: baseStyle),
                    textDirection: Directionality.of(context),
                    textScaler: MediaQuery.textScalerOf(
                      context,
                    ).clamp(maxScaleFactor: 1.3),
                  )..layout();
                  final available = constraints.maxWidth / 4 - 8;
                  final fontSize =
                      12 * (available / painter.width).clamp(0.0, 1.0);
                  painter.dispose();
                  return NavigationBar(
                    labelBehavior:
                        NavigationDestinationLabelBehavior.alwaysShow,
                    labelPadding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
                    labelTextStyle: WidgetStateProperty.resolveWith(
                      (states) => baseStyle.copyWith(
                        fontSize: fontSize,
                        color: states.contains(WidgetState.selected)
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    selectedIndex: index < 0 ? 0 : index,
                    onDestinationSelected: (value) =>
                        context.go(destinations[value]),
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
                      NavigationDestination(
                        icon: Icon(Icons.card_membership_outlined),
                        label: 'Plans',
                      ),
                    ],
                  );
                },
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
