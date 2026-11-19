import 'package:dio/dio.dart';

import '../models/member_overview.dart';
import 'member_failure.dart';

abstract interface class MemberOverviewRepository {
  Future<MemberOverviewPage> list(String gymId, MemberOverviewQuery query);
}

/// One request returns each member's current membership state, days left and
/// dues, plus filter counts. Replaces per-member summary reads in lists.
class DioMemberOverviewRepository implements MemberOverviewRepository {
  DioMemberOverviewRepository(this._client);
  final Dio _client;

  @override
  Future<MemberOverviewPage> list(
    String gymId,
    MemberOverviewQuery query,
  ) async {
    if (!RegExp(r'^[a-fA-F0-9]{24}$').hasMatch(gymId)) {
      throw const MemberFailure('Invalid member context.');
    }
    try {
      final response = await _client.get<dynamic>(
        'gyms/$gymId/member-overview',
        queryParameters: query.toParameters(),
      );
      final body = response.data;
      if (body is! Map<String, dynamic> ||
          body['success'] != true ||
          body['data'] is! Map<String, dynamic>) {
        throw const FormatException('Invalid member overview envelope.');
      }
      return MemberOverviewPage.fromJson(body['data'] as Map<String, dynamic>);
    } on DioException catch (error) {
      throw MemberFailure.fromDio(error);
    } on MemberFailure {
      rethrow;
    } catch (_) {
      throw invalidMemberResponse;
    }
  }
}
