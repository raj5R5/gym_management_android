import 'package:dio/dio.dart';
import '../../auth/data/auth_failure.dart';

class TrainerFailure implements Exception {
  const TrainerFailure(this.message, {this.possiblySent = false});
  final String message;
  final bool possiblySent;
  factory TrainerFailure.fromDio(DioException error) {
    final data = error.response?.data;
    final code = data is Map && data['error'] is Map
        ? (data['error'] as Map)['code']
        : null;
    return TrainerFailure(
      switch (code) {
        'DUPLICATE_TRAINER_CODE' =>
          'That trainer code already exists in this gym. Choose another code.',
        'TRAINER_NOT_FOUND' =>
          'This trainer is no longer available in this gym.',
        'VALIDATION_ERROR' =>
          'The server could not validate this information. Check the fields and try again.',
        _ => AuthFailure.fromDio(error).message,
      },
      possiblySent:
          error.response == null || (error.response?.statusCode ?? 0) >= 500,
    );
  }
  @override
  String toString() => 'TrainerFailure: $message';
}

const invalidTrainerResponse = TrainerFailure(
  'The server returned an unexpected trainer response.',
  possiblySent: true,
);
