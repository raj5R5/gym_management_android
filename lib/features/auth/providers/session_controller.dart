import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/session_state.dart';
import 'auth_providers.dart';

class SessionController extends Notifier<SessionState> {
  bool _loggingOut = false;
  Future<void>? _logoutFlight;

  @override
  SessionState build() {
    final repository = ref.watch(authRepositoryProvider);
    _loggingOut = false;
    _logoutFlight = null;
    final subscription = repository.changes.listen((session) {
      if (ref.mounted && !_loggingOut) state = session;
    });
    ref.onDispose(subscription.cancel);
    return repository.state;
  }

  Future<void> restoreSession() =>
      ref.read(authRepositoryProvider).restoreSession();
  Future<void> login({required String email, required String password}) =>
      ref.read(authRepositoryProvider).login(email: email, password: password);
  Future<void> logout() {
    final pending = _logoutFlight;
    if (pending != null) return pending;
    final repository = ref.read(authRepositoryProvider);
    // The repository blocks bearer use immediately. Keep only the presentation
    // operation visible until cleanup completes so login cannot race logout.
    _loggingOut = true;
    state = const SessionLoading(SessionOperation.loggingOut);
    late final Future<void> flight;
    flight = repository.logout().whenComplete(() {
      if (!ref.mounted || !identical(_logoutFlight, flight)) return;
      _loggingOut = false;
      _logoutFlight = null;
      state = repository.state;
    });
    _logoutFlight = flight;
    return flight;
  }

  Future<void> refreshSession() =>
      ref.read(authRepositoryProvider).refreshSession();
}

final sessionControllerProvider =
    NotifierProvider<SessionController, SessionState>(SessionController.new);
