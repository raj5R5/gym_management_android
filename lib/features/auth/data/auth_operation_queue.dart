/// Container-owned ordering survives repository replacement. A native storage
/// operation already started cannot be cancelled; its completion must precede
/// any replacement repository's credential mutations. No process-global state.
class AuthOperationQueue {
  Future<void> _tail = Future.value();

  Future<T> run<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    // Callers receive failures; the queue itself remains available.
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }
}
