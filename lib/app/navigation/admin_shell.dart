import 'package:flutter/material.dart';
import '../../features/branches/branches.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/admin_dashboard/providers/dashboard_providers.dart';
import '../../features/auth/models/session_state.dart';
import '../../features/auth/providers/session_controller.dart';
import '../router/app_routes.dart';
import '../theme/design_tokens.dart';
import 'foundation_screens.dart';
import '../../features/owner_profile/owner_profile_widgets.dart';
import '../../features/owner_profile/owner_profile.dart';
import '../../features/owner_profile/owner_signup_photo.dart';
import '../../shared/widgets/glass_tab_bar.dart';
import '../../shared/widgets/titanium_surface.dart';
import 'form_navigation_guard.dart';
import '../../features/notifications/notifications_page.dart';

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
    ref.watch(ownerSignupPhotoRecoveryProvider);
    final ownerProfile = currentOwnerProfile(ref);
    final branchNames = ref.watch(branchNamesProvider);
    final memberDetail = location.startsWith('${AppRoutes.members}/');
    // The identity contract has no gym names. Use ordinal scope labels on the
    // member overview, while retaining the actual IDs as selector values.
    final memberOverview = RegExp(
      '^${AppRoutes.members}/[a-fA-F0-9]{24}\$',
    ).hasMatch(location);
    final trainerDetail = location.startsWith('${AppRoutes.trainers}/');
    final planDetail = location.startsWith('${AppRoutes.plans}/');
    final profileDetail =
        location == AppRoutes.ownerProfile ||
        location == AppRoutes.gymSettings ||
        location == AppRoutes.accountSecurity ||
        location == AppRoutes.joinRequests ||
        location.startsWith(AppRoutes.checkIn) ||
        location == AppRoutes.expenses ||
        location.startsWith(AppRoutes.leads) ||
        location.startsWith(AppRoutes.pt) ||
        location == AppRoutes.paymentClaims ||
        location.startsWith(AppRoutes.reports) ||
        location == AppRoutes.notifications ||
        location == AppRoutes.branches ||
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
    final showTabs =
        location != AppRoutes.more &&
        location != AppRoutes.ownerProfile &&
        location != AppRoutes.gymSettings &&
        location != AppRoutes.checkInScan;
    final tabSpace = GlassTabBar.space(context);
    final shell = PopScope(
      canPop: profileDetail || index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !profileDetail) context.go(AppRoutes.dashboard);
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          // The gym being managed is the one header line; with several
          // branches the picker below names it instead.
          title: gyms.length > 1
              ? null
              : Text(
                  ownerProfile?.gymName ?? 'Current gym',
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
          flexibleSpace: TitaniumGlass(
            radius: 0,
            opacity: AppGlass.navigation(Theme.of(context).brightness),
            blur: AppGlass.navigationBlur,
            highlightOpacity: AppGlass.navigationHighlight,
            child: const SizedBox.expand(),
          ),
          automaticallyImplyLeading: false,
          actions: const [NotificationBell()],
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
                OwnerDrawerHeader(
                  openProfile: () {
                    Navigator.of(context).pop();
                    // Open the editor once the profile is loaded; otherwise
                    // More shows the loading/retry state for the profile.
                    final target = ownerProfile != null
                        ? AppRoutes.ownerProfile
                        : AppRoutes.more;
                    if (location == target) return;
                    if (!profileDetail) {
                      context.push(target);
                    } else {
                      context.go(target);
                    }
                  },
                ),
                ...{
                  'Dashboard': AppRoutes.dashboard,
                  'Members': AppRoutes.members,
                  'Trainers': AppRoutes.trainers,
                  'Personal training': AppRoutes.pt,
                  'Plans': AppRoutes.plans,
                  'Check in': AppRoutes.checkIn,
                  'Enquiries': AppRoutes.leads,
                  'Expenses': AppRoutes.expenses,
                  'Reports': AppRoutes.reports,
                  'Branches': AppRoutes.branches,
                  'More': AppRoutes.more,
                }.entries.map(
                  (entry) => ListTile(
                    leading: Icon(switch (entry.value) {
                      AppRoutes.dashboard => Icons.dashboard_outlined,
                      AppRoutes.members => Icons.people_outline,
                      AppRoutes.trainers => Icons.fitness_center_outlined,
                      AppRoutes.plans => Icons.card_membership_outlined,
                      AppRoutes.checkIn => Icons.qr_code_scanner,
                      AppRoutes.leads => Icons.contact_phone_outlined,
                      AppRoutes.pt => Icons.sports_gymnastics_outlined,
                      AppRoutes.reports => Icons.insert_chart_outlined,
                      AppRoutes.branches => Icons.storefront_outlined,
                      AppRoutes.expenses =>
                        Icons.account_balance_wallet_outlined,
                      _ => Icons.more_horiz,
                    }),
                    title: Text(entry.key),
                    selected:
                        location == entry.value ||
                        location.startsWith('${entry.value}/'),
                    onTap: () {
                      Navigator.of(context).pop();
                      if (location == entry.value) return;
                      if ({
                            AppRoutes.more,
                            AppRoutes.checkIn,
                            AppRoutes.leads,
                            AppRoutes.pt,
                            AppRoutes.reports,
                            AppRoutes.expenses,
                            AppRoutes.branches,
                          }.contains(entry.value) &&
                          !profileDetail) {
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
          bottom: !showTabs,
          child: Column(
            children: [
              if (gyms.length > 1)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: DropdownButtonFormField<String>(
                    key: gymField,
                    initialValue: selected.gymId,
                    decoration: const InputDecoration(labelText: 'Branch'),
                    isExpanded: true,
                    items: gyms
                        .map(
                          (id) => DropdownMenuItem(
                            value: id,
                            child: Text(
                              // Branch names come from the owner summary;
                              // the identity contract itself has no names.
                              branchNames[id] ??
                                  (memberOverview
                                      ? 'Gym ${gyms.indexOf(id) + 1}'
                                      : 'Gym $id'),
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
                  ),
                ),
              Expanded(
                child: showTabs
                    ? MediaQuery.removePadding(
                        context: context,
                        removeBottom: true,
                        child: Padding(
                          padding: EdgeInsets.only(bottom: tabSpace),
                          // Page transitions (see TitaniumPageTransitions)
                          // animate each change; a second entrance here would
                          // fade the whole stack in again.
                          child: child,
                        ),
                      )
                    : child,
              ),
            ],
          ),
        ),
        // More remains a drawer-only account page. It has no matching tab,
        // so omit the bar rather than falsely selecting Dashboard.
        extendBody: showTabs,
        bottomNavigationBar: showTabs
            ? GlassTabBar(
                // -1 on drawer pages (Check in, Expenses): no tab is lit, so
                // every tab, including Dashboard, navigates when tapped.
                selectedIndex: index,
                onSelected: (value) => context.go(destinations[value]),
                tabs: const [
                  GlassTab(
                    label: 'Dashboard',
                    icon: Icons.space_dashboard_outlined,
                    selectedIcon: Icons.space_dashboard_rounded,
                  ),
                  GlassTab(
                    label: 'Members',
                    icon: Icons.group_outlined,
                    selectedIcon: Icons.group_rounded,
                  ),
                  GlassTab(
                    label: 'Trainers',
                    icon: Icons.fitness_center_outlined,
                    selectedIcon: Icons.fitness_center_rounded,
                  ),
                  GlassTab(
                    label: 'Plans',
                    icon: Icons.card_membership_outlined,
                    selectedIcon: Icons.card_membership_rounded,
                  ),
                ],
              )
            : null,
      ),
    );
    return Stack(
      children: [
        Offstage(
          offstage: refreshing,
          child: TickerMode(
            enabled: !refreshing,
            child: TitaniumCanvas(
              animated: location == AppRoutes.dashboard,
              child: shell,
            ),
          ),
        ),
        if (refreshing) const StartupScreen(),
      ],
    );
  }
}
