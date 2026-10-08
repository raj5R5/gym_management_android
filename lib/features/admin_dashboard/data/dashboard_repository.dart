import 'package:dio/dio.dart';

import '../../auth/data/auth_failure.dart';
import '../models/dashboard_models.dart';

abstract interface class DashboardRepository {
  Future<GymDashboard> getDashboard(String gymId, DashboardQuery query);
}

/// M27 read-only data boundary, using the existing authenticated Dio instance.
class DioDashboardRepository implements DashboardRepository {
  DioDashboardRepository(this._client);
  final Dio _client;

  @override
  Future<GymDashboard> getDashboard(String gymId, DashboardQuery query) async {
    if (!RegExp(r'^[a-fA-F0-9]{24}$').hasMatch(gymId)) {
      throw const AuthFailure(AuthFailureKind.validation);
    }
    try {
      final response = await _client.get<dynamic>(
        'gyms/$gymId/dashboard',
        queryParameters: query.toParameters(),
      );
      final body = response.data;
      if (body is! Map<String, dynamic> ||
          body['success'] != true ||
          body['data'] is! Map<String, dynamic>) {
        throw const FormatException('Invalid dashboard envelope.');
      }
      final dashboard = GymDashboard.fromJson(
        body['data'] as Map<String, dynamic>,
      );
      // A filtered or mismatched period must not be presented as all-branch data.
      if (dashboard.period.branchId != null ||
          (query.from != null &&
              (dashboard.period.from.toString() != query.from.toString() ||
                  dashboard.period.to.toString() != query.to.toString()))) {
        throw const FormatException('Dashboard context mismatch.');
      }
      return dashboard;
    } on DioException catch (error) {
      throw AuthFailure.fromDio(error);
    } on AuthFailure {
      rethrow;
    } catch (_) {
      throw const AuthFailure(AuthFailureKind.unexpectedResponse);
    }
  }
}
