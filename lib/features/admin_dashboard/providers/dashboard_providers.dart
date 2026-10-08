import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/models/auth_models.dart';
import '../../auth/models/session_state.dart';
import '../../auth/providers/auth_providers.dart';
import '../../auth/providers/session_controller.dart';
import '../data/dashboard_repository.dart';
import '../models/dashboard_models.dart';

final adminGymIdsProvider = Provider<List<String>>((ref) {
  final session = ref.watch(sessionControllerProvider);
  if (session is! SessionAuthenticated ||
      session.identity.user.status != AccountStatus.active) {
    return const [];
  }
  return List.unmodifiable(
    session.identity.gymAccess
        .where(
          (grant) =>
              grant.role == AuthRole.admin &&
              grant.status == AccountStatus.active,
        )
        .map((grant) => grant.gymId)
        .toSet(),
  );
});

typedef AdminGymContext = ({String userId, String gymId});

class AdminGymController extends Notifier<AdminGymContext?> {
  AdminGymContext? _context;
  @override
  AdminGymContext? build() {
    final session = ref.watch(sessionControllerProvider);
    // Preserve the validated scope during single-flight access-token recovery.
    // This avoids restarting dashboard requests while the interceptor retries.
    if (session is SessionLoading &&
        session.operation == SessionOperation.refreshing) {
      return _context;
    }
    final gyms = ref.watch(adminGymIdsProvider);
    if (session is! SessionAuthenticated || gyms.isEmpty) {
      return _context = null;
    }
    final previous = _context;
    return _context = (
      userId: session.identity.user.id,
      gymId:
          previous?.userId == session.identity.user.id &&
              gyms.contains(previous?.gymId)
          ? previous!.gymId
          : gyms.first,
    );
  }

  void selectGym(String gymId) {
    final current = state;
    if (current == null || !ref.read(adminGymIdsProvider).contains(gymId)) {
      throw ArgumentError('Select a gym from the authenticated admin grants.');
    }
    state = _context = (userId: current.userId, gymId: gymId);
  }
}

final adminGymProvider = NotifierProvider<AdminGymController, AdminGymContext?>(
  AdminGymController.new,
);

class DashboardQueryController extends Notifier<DashboardQuery> {
  @override
  DashboardQuery build() => const DashboardQuery.today();
  void selectRange(CalendarDate from, CalendarDate to) =>
      state = DashboardQuery.range(from, to);
  void useGymToday() => state = const DashboardQuery.today();
}

final dashboardQueryProvider =
    NotifierProvider<DashboardQueryController, DashboardQuery>(
      DashboardQueryController.new,
    );
final dashboardRepositoryProvider = Provider<DashboardRepository>(
  (ref) => DioDashboardRepository(ref.watch(authenticatedApiClientProvider)),
);

class DashboardController extends AsyncNotifier<GymDashboard?> {
  @override
  Future<GymDashboard?> build() async {
    final context = ref.watch(adminGymProvider);
    final query = ref.watch(dashboardQueryProvider);
    if (context == null) return null;
    return ref
        .watch(dashboardRepositoryProvider)
        .getDashboard(context.gymId, query);
  }

  Future<void> reload() async {
    // Riverpod owns replacement-future ordering. Old scope/filter results cannot
    // overwrite the current state. Errors are rendered by AsyncValue in the UI.
    ref.invalidateSelf();
    await future;
  }
}

final dashboardProvider =
    AsyncNotifierProvider<DashboardController, GymDashboard?>(
      DashboardController.new,
      // User-controlled retry; auth recovery remains owned by the interceptor.
      retry: (_, _) => null,
    );
