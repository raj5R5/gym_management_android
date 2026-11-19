import 'package:flutter_test/flutter_test.dart';
import 'package:gym_management_app/app/router/app_router.dart';
import 'package:gym_management_app/app/router/app_routes.dart';
import 'package:gym_management_app/features/auth/models/session_state.dart';

import '../features/auth/auth_fakes.dart';

void main() {
  const refreshing = SessionLoading(SessionOperation.refreshing);

  test('every shell page survives access-token recovery', () {
    // Regression: newer drawer pages were sent to startup mid-request, which
    // closed them while a write was still finishing.
    for (final path in [
      AppRoutes.paymentClaims,
      AppRoutes.pt,
      '${AppRoutes.pt}/abc',
      AppRoutes.leads,
      AppRoutes.expenses,
      AppRoutes.branches,
      AppRoutes.checkIn,
      AppRoutes.gymSettings,
      AppRoutes.members,
    ]) {
      expect(appRedirect(refreshing, path), isNull, reason: path);
    }
    expect(appRedirect(refreshing, AppRoutes.login), AppRoutes.startup);
  });

  test('activation stays public; signed-out shell pages go to login', () {
    expect(
      appRedirect(const SessionUnauthenticated(), AppRoutes.activate),
      isNull,
    );
    expect(
      appRedirect(const SessionUnauthenticated(), AppRoutes.paymentClaims),
      AppRoutes.login,
    );
    expect(
      appRedirect(
        SessionAuthenticated(syntheticIdentity()),
        AppRoutes.activate,
      ),
      isNull,
    );
  });
}
