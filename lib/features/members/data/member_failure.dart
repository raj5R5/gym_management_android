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
      'MINOR_MEMBER_WORKFLOW_UNAVAILABLE' =>
        'Under-18 registration and profile uploads are unavailable until guardian authorization and verification are supported.',
      'DUPLICATE_MEMBER_CODE' =>
        'That member code already exists in this gym. Choose another code.',
      'DUPLICATE_MEMBER_PHONE' => _duplicatePhone(data),
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

/// Names the member who already has the phone, when the server says who.
String _duplicatePhone(Object? data) {
  final details = data is Map && data['error'] is Map
      ? (data['error'] as Map)['details']
      : null;
  final name = details is Map ? details['name'] : null;
  return name is String && name.trim().isNotEmpty
      ? 'This phone number already belongs to ${name.trim()}. Each member needs their own number.'
      : 'This phone number already belongs to a member of this gym. Each member needs their own number.';
}

const invalidMemberResponse = MemberFailure(
  'The server returned an unexpected member response.',
);
