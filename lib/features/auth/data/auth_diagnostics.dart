import 'package:flutter/foundation.dart';

import 'auth_failure.dart';

enum AuthStage {
  restore,
  refresh,
  credentialRead,
  credentialWrite,
  credentialClear,
  loginApi,
  refreshApi,
  currentUserApi,
  logoutApi,
}

enum AuthEvent { started, succeeded, failed, absent, preserved, superseded }

/// Deliberately accepts no exception, URL, account, header, or credential value.
/// Available in release builds for bounded Android logcat diagnosis.
class AuthDiagnostics {
  const AuthDiagnostics({this.sink});

  final void Function(String)? sink;

  void record(
    AuthStage stage,
    AuthEvent event, {
    AuthFailure? failure,
    int? statusCode,
    String? requestId,
    int? elapsedMs,
  }) {
    final status = statusCode ?? failure?.statusCode;
    final id = requestId ?? failure?.requestId;
    // The backend generates UUID request identifiers. Reject arbitrary server
    // strings (including credential-shaped values) instead of printing them.
    final safeId =
        id != null &&
        RegExp(
          r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
        ).hasMatch(id);
    final line = [
      '[session]',
      'stage=${stage.name}',
      'event=${event.name}',
      if (failure != null) 'category=${failure.kind.name}',
      if (status != null && status >= 100 && status <= 599) 'http=$status',
      if (failure?.transportType != null)
        'transport=${failure!.transportType!.name}',
      if (safeId) 'request_id=$id',
      if (elapsedMs != null) 'elapsed_ms=$elapsedMs',
    ].join(' ');
    (sink ?? debugPrint)(line);
  }
}
