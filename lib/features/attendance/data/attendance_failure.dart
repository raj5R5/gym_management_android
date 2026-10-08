import 'package:dio/dio.dart';
import '../../auth/data/auth_failure.dart';

class AttendanceFailure implements Exception {
  const AttendanceFailure(
    this.message, {
    this.uncertain = false,
    this.recheck = false,
  });
  final String message;
  final bool uncertain, recheck;
  factory AttendanceFailure.fromDio(
    DioException error, {
    required bool writing,
  }) {
    if (writing &&
        (error.response == null && error.error is! AuthFailure ||
            (error.response?.statusCode ?? 0) >= 500)) {
      return const AttendanceFailure(
        'The attendance outcome is uncertain. Recheck open visits and today’s attendance before another attempt.',
        uncertain: true,
        recheck: true,
      );
    }
    final body = error.response?.data;
    final code = body is Map && body['error'] is Map
        ? (body['error'] as Map)['code']
        : null;
    return AttendanceFailure(
      switch (code) {
        'ATTENDANCE_MEMBERSHIP_REQUIRED' =>
          'The server found no valid current membership. Check the member’s membership history.',
        'ATTENDANCE_MEMBERSHIP_AMBIGUOUS' =>
          'The server found conflicting membership records. Resolve the membership conflict before check-in.',
        'ATTENDANCE_BRANCH_INACTIVE' =>
          'The assigned branch is inactive. Branch management is not available in this app yet.',
        'ATTENDANCE_BRANCH_MISMATCH' =>
          'The member’s branch assignment changed. Refresh the member before check-in.',
        'ATTENDANCE_ALREADY_OPEN' =>
          'This member is already checked in. Refresh open visits.',
        'ATTENDANCE_NOT_OPEN' =>
          'This visit is already closed or is no longer open. Refresh attendance.',
        'ATTENDANCE_NOT_FOUND' =>
          'This visit is no longer available in this gym. Refresh attendance.',
        'MEMBER_NOT_FOUND' => 'This member is no longer available in this gym.',
        'BRANCH_NOT_FOUND' =>
          'The assigned branch is no longer available in this gym.',
        'VALIDATION_ERROR' =>
          'The server could not validate this attendance request.',
        _ => AuthFailure.fromDio(error).message,
      },
      recheck: [
        'ATTENDANCE_ALREADY_OPEN',
        'ATTENDANCE_NOT_OPEN',
        'ATTENDANCE_NOT_FOUND',
      ].contains(code),
    );
  }
  @override
  String toString() => 'AttendanceFailure: $message';
}
