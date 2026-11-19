import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_management_app/features/auth/data/auth_diagnostics.dart';
import 'package:gym_management_app/features/auth/data/auth_failure.dart';

import 'auth_fakes.dart';

void main() {
  test('diagnostics contain only typed stages, failures and safe metadata', () {
    final lines = <String>[];
    final diagnostics = AuthDiagnostics(sink: lines.add);
    const id = 'a4eb1081-e162-4f8a-9cb1-91d918503315';
    diagnostics.record(
      AuthStage.refreshApi,
      AuthEvent.failed,
      failure: const AuthFailure(
        AuthFailureKind.server,
        statusCode: 503,
        requestId: id,
        transportType: DioExceptionType.badResponse,
      ),
      elapsedMs: 30100,
    );
    expect(
      lines.single,
      '[session] stage=refreshApi event=failed '
      'category=server http=503 transport=badResponse '
      'request_id=$id elapsed_ms=30100',
    );
    // A malformed backend identifier must not become a credential log channel.
    for (final value in [
      syntheticCredential(),
      'Bearer secret',
      'password\nnext',
    ]) {
      diagnostics.record(
        AuthStage.currentUserApi,
        AuthEvent.failed,
        failure: AuthFailure(AuthFailureKind.network, requestId: value),
      );
      expect(lines.last.contains(value), isFalse);
      expect(lines.last.contains('request_id='), isFalse);
    }
  });
}
