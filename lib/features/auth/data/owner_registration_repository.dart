import 'package:dio/dio.dart';
import '../models/owner_registration.dart';
import 'owner_registration_failure.dart';

abstract interface class OwnerRegistrationRepository {
  Future<void> register(OwnerRegistrationRequest request);
}

/// Public transport only. No token storage, identity reuse or automatic retries.
class DioOwnerRegistrationRepository implements OwnerRegistrationRepository {
  DioOwnerRegistrationRepository(this._client);
  final Dio _client;
  @override
  Future<void> register(OwnerRegistrationRequest request) async {
    try {
      final response = await _client.post<dynamic>(
        'auth/register-owner',
        data: request.toJson(),
        options: Options(
          followRedirects: false,
          responseType: ResponseType.json,
          headers: {'Authorization': null, 'Cookie': null, 'Origin': null},
          extra: {'authRequired': false},
        ),
      );
      final body = response.data;
      if (response.statusCode != 201 ||
          body is! Map ||
          body['success'] != true ||
          body['data'] is! Map ||
          body['data']['accountCreated'] != true ||
          body['data']['gymCreated'] != true ||
          body['meta'] is! Map ||
          body['meta']['requestId'] is! String ||
          (body['meta']['requestId'] as String).isEmpty) {
        throw const OwnerRegistrationFailure(
          OwnerRegistrationFailureKind.unexpected,
        );
      }
    } on OwnerRegistrationFailure {
      rethrow;
    } on DioException catch (error) {
      throw OwnerRegistrationFailure.fromDio(error);
    } on FormatException {
      throw const OwnerRegistrationFailure(
        OwnerRegistrationFailureKind.validation,
      );
    } catch (_) {
      throw const OwnerRegistrationFailure(
        OwnerRegistrationFailureKind.unexpected,
      );
    }
  }
}
