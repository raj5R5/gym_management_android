import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/session_state.dart';
import 'auth_providers.dart';

class SessionController extends Notifier<SessionState> {
  @override
  SessionState build() {
    final repository = ref.watch(authRepositoryProvider);
    final subscription = repository.changes.listen((session) {
      if (ref.mounted) state = session;
    });
    ref.onDispose(subscription.cancel);
    return repository.state;
  }

  Future<void> restoreSession() =>
      ref.read(authRepositoryProvider).restoreSession();
  Future<void> login({required String email, required String password}) =>
      ref.read(authRepositoryProvider).login(email: email, password: password);
  Future<void> logout() => ref.read(authRepositoryProvider).logout();
  Future<void> refreshSession() =>
      ref.read(authRepositoryProvider).refreshSession();
}

final sessionControllerProvider =
    NotifierProvider<SessionController, SessionState>(SessionController.new);
