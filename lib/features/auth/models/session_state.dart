import '../data/auth_failure.dart';
import 'auth_models.dart';

sealed class SessionState {
  const SessionState();
}

class SessionInitial extends SessionState {
  const SessionInitial();
}

enum SessionOperation { restoring, login, refreshing, loggingOut }

class SessionLoading extends SessionState {
  const SessionLoading(this.operation);
  final SessionOperation operation;
}

class SessionUnauthenticated extends SessionState {
  const SessionUnauthenticated();
}

class SessionAuthenticated extends SessionState {
  const SessionAuthenticated(this.identity);
  final AuthIdentity identity;
}

class SessionError extends SessionState {
  const SessionError(this.failure);
  final AuthFailure failure;
}
