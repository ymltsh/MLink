class ToolCancelled implements Exception {
  @override
  String toString() => '任务已取消';
}

class ToolCancellation {
  bool _cancelled = false;
  final Set<void Function()> _listeners = {};
  bool get isCancelled => _cancelled;

  void check() {
    if (_cancelled) throw ToolCancelled();
  }

  void add(void Function() listener) {
    if (_cancelled) {
      listener();
    } else {
      _listeners.add(listener);
    }
  }

  void remove(void Function() listener) => _listeners.remove(listener);

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final listener in _listeners.toList()) {
      listener();
    }
    _listeners.clear();
  }
}
