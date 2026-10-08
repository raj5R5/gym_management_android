import 'package:dio/dio.dart';
import '../../auth/data/auth_failure.dart';

class MemberFailure implements Exception {
  const MemberFailure(this.message);
  final String message;
  factory MemberFailure.fromDio(DioException error) {
    final data = error.response?.data;
    final code = data is Map && data['error'] is Map
        ? (data['error'] as Map)['code']
        : null;
    return MemberFailure(switch (code) {
      'DUPLICATE_MEMBER_CODE' =>
        'That member code already exists in this gym. Choose another code.',
      'MEMBER_NOT_FOUND' => 'This member is no longer available in this gym.',
      'SUBSCRIPTION_NOT_FOUND' => 'This membership is no longer available.',
      'VALIDATION_ERROR' =>
        'The server could not validate this information. Check the fields and try again.',
      _ => AuthFailure.fromDio(error).message,
    });
  }
  @override
  String toString() => 'MemberFailure: $message';
}

const invalidMemberResponse = MemberFailure(
  'The server returned an unexpected member response.',
);
