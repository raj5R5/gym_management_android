import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:gym_management_app/core/storage/credential_storage.dart';
import 'package:gym_management_app/features/auth/data/auth_api_service.dart';
import 'package:gym_management_app/features/auth/data/auth_failure.dart';
import 'package:gym_management_app/features/auth/models/auth_models.dart';

// Generated non-production credentials; no real credentials or static tokens.
String syntheticCredential() => base64Url
    .encode(List.generate(32, (_) => Random.secure().nextInt(256)))
    .replaceAll('=', '');

AuthTokens syntheticTokens() => AuthTokens(
  accessToken: syntheticCredential(),
  refreshToken: syntheticCredential(),
  expiresIn: 600,
  tokenType: 'Bearer',
);

AuthIdentity syntheticIdentity() => AuthIdentity(
  user: const AuthUser(
    id: 'test-account',
    email: 'person@example.invalid',
    status: AccountStatus.active,
  ),
  gymAccess: [],
);

Map<String, dynamic> identityJson() => {
  'user': {
    'id': 'test-account',
    'email': 'person@example.invalid',
    'status': 'active',
  },
  'gymAccess': <Object>[],
};
Map<String, dynamic> tokenJson(AuthTokens tokens) => {
  'accessToken': tokens.accessToken,
  'refreshToken': tokens.refreshToken,
  'expiresIn': tokens.expiresIn,
  'tokenType': tokens.tokenType,
};
Map<String, dynamic> success(Map<String, dynamic> data) => {
  'success': true,
  'data': data,
  'meta': {'requestId': 'test-request'},
};
Map<String, dynamic> failureBody(String code) => {
  'success': false,
  'error': {'code': code, 'message': 'Test failure'},
  'meta': {'requestId': 'test-request'},
};

class FakeCredentialStorage implements CredentialStorage {
  String? value;
  int writes = 0;
  int clears = 0;
  Completer<void>? writeGate;
  Completer<void>? writeEntered;
  bool failRead = false;
  bool failWrite = false;
  bool failClear = false;
  @override
  Future<String?> readRefreshCredential() async {
    if (failRead) throw const CredentialStorageFailure();
    return value;
  }

  @override
  Future<void> writeRefreshCredential(String credential) async {
    writes++;
    if (writeEntered != null && !writeEntered!.isCompleted) {
      writeEntered!.complete();
    }
    if (writeGate != null) await writeGate!.future;
    if (failWrite) throw const CredentialStorageFailure();
    value = credential;
  }

  @override
  Future<void> clearRefreshCredential() async {
    clears++;
    if (failClear) throw const CredentialStorageFailure();
    value = null;
  }
}

class FakeAuthApi implements AuthApiService {
  final loginTokens = syntheticTokens();
  final rotatedTokens = syntheticTokens();
  final identity = syntheticIdentity();
  AuthFailure? loginFailure;
  AuthFailure? refreshFailure;
  AuthFailure? logoutFailure;
  AuthFailure? meFailure;
  Completer<void>? refreshGate;
  Completer<void>? loginGate;
  Completer<void>? meGate;
  final loginEntered = Completer<void>();
  final meEntered = Completer<void>();
  final refreshEntered = Completer<void>();
  int loginCalls = 0;
  int refreshCalls = 0;
  int meCalls = 0;
  final loggedOutCredentials = <String>[];
  @override
  Future<LoginResponse> login({
    required String email,
    required String password,
  }) async {
    loginCalls++;
    if (!loginEntered.isCompleted) loginEntered.complete();
    if (loginGate != null) await loginGate!.future;
    if (loginFailure != null) throw loginFailure!;
    return LoginResponse(identity: identity, tokens: loginTokens);
  }

  @override
  Future<AuthTokens> refresh(String refreshCredential) async {
    refreshCalls++;
    if (!refreshEntered.isCompleted) refreshEntered.complete();
    if (refreshGate != null) await refreshGate!.future;
    if (refreshFailure != null) throw refreshFailure!;
    return rotatedTokens;
  }

  @override
  Future<AuthIdentity> currentUser(String accessToken) async {
    meCalls++;
    if (!meEntered.isCompleted) meEntered.complete();
    if (meGate != null) await meGate!.future;
    if (meFailure != null) throw meFailure!;
    return identity;
  }

  @override
  Future<void> logout(String refreshCredential) async {
    loggedOutCredentials.add(refreshCredential);
    if (logoutFailure != null) throw logoutFailure!;
  }
}

class CallbackAdapter implements HttpClientAdapter {
  CallbackAdapter(this.respond);
  final FutureOr<ResponseBody> Function(RequestOptions) respond;
  final requests = <RequestOptions>[];
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return await respond(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody jsonResponse(Map<String, dynamic> data, {int status = 200}) =>
    ResponseBody.fromString(
      jsonEncode(data),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
